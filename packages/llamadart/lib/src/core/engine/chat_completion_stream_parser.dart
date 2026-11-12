import 'dart:async';

import '../exceptions.dart';
import '../llama_logger.dart';
import '../models/chat/chat_template_result.dart';
import '../models/chat/completion_chunk.dart';
import '../models/inference/generation_usage.dart';
import '../models/tools/tool_definition.dart';
import '../template/chat_format.dart';
import '../template/chat_format_registry.dart';
import '../template/chat_parse_result.dart';
import '../template/chat_template_engine.dart';
import '../template/handlers/cohere2_moe_handler.dart';
import '../template/handlers/command_r7b_handler.dart';
import '../template/handlers/llama3_handler.dart';
import '../template/peg_chat_parser.dart';
import '../template/template_internal_metadata.dart';
import '../template/thinking_utils.dart';
import '../template/tool_call_parsing_utils.dart';
import '../template/xml_tool_call_format.dart';

enum _ToolStreamingMode { undecided, raw, parsed }

class _ThinkingSplitEmission {
  const _ThinkingSplitEmission({
    required this.text,
    required this.isThinking,
    this.endsThinking = false,
  });

  final String text;
  final bool isThinking;
  final bool endsThinking;
}

/// The thinking tags a stream has seen so far.
class _ThoughtTagState {
  var sawStartTag = false;
  var sawEndTag = false;

  /// Whether an end tag outside a thought is content unless a start tag
  /// follows it.
  ///
  /// Without a start tag, the parse ends the thought at the first end tag and
  /// keeps the rest as content. A later start tag makes each end tag before it
  /// end a thought, so the stream checks the pending text for one.
  bool get endTagIsContent => sawEndTag && !sawStartTag;
}

class _ThinkingSplitResult {
  const _ThinkingSplitResult({
    required this.pendingBuffer,
    required this.isThinking,
    required this.emissions,
    this.bodyStarted = false,
  });

  final String pendingBuffer;
  final bool isThinking;
  final List<_ThinkingSplitEmission> emissions;

  /// Whether a body opening, or an end tag that ends no thought, started
  /// content in which thinking tags are text.
  final bool bodyStarted;
}

/// Parses generated token streams into OpenAI-style chat completion chunks.
///
/// This keeps the streaming parser state machine separate from [LlamaEngine]:
/// routing raw text vs structured tool envelopes, splitting thinking deltas,
/// suppressing partial tool-call envelopes, and reconciling final parsed output.
class ChatCompletionStreamParser {
  const ChatCompletionStreamParser._();

  /// Parses [tokenStream] into incremental content, thinking, and tool chunks.
  ///
  /// The final chunk's finish reason is `length` when [stoppedAtLimit]
  /// returns true after [tokenStream] ends. Such a reply withholds all tool
  /// calls, including complete calls before an incomplete parallel call:
  /// the call set is not safe to execute. Otherwise parsed calls finish with
  /// `tool_calls`, and a reply without calls finishes with `stop`.
  /// The final chunk carries what [usage] returns after [tokenStream] ends.
  ///
  /// A reply that ended at a limit, or that [cancelled] reports cancelled,
  /// may stop short of what a PEG parser requires, such as the tool call of
  /// `ToolChoice.required`. When the parse of the whole reply fails, it is
  /// parsed as partial output instead and its tool calls are withheld. Any
  /// other reply that does not parse throws [LlamaInferenceException].
  ///
  /// Calls [runtimeToolCalls] returns after [tokenStream] ends, which the
  /// runtime parsed itself and never wrote into the text, follow the calls
  /// parsed from the text when tool-call parsing is enabled.
  static Stream<LlamaCompletionChunk> parse({
    required Stream<String> tokenStream,
    required LlamaChatTemplateResult templateResult,
    required bool parseToolCallsEnabled,
    required bool enableThinking,
    required String modelName,
    required String completionId,
    List<ToolDefinition>? tools,
    bool Function()? stoppedAtLimit,
    bool Function()? cancelled,
    LlamaGenerationUsage? Function()? usage,
    List<LlamaCompletionChunkToolCall>? Function()? runtimeToolCalls,
  }) async* {
    var result = templateResult;
    var tokens = tokenStream;
    // The parse ends the thought a handler closed for thinking off at a
    // marker, as llama.cpp ends the thought it keeps open, so text before one
    // may be reasoning.
    if (thoughtClosedForThinkingOffOf(templateResult) &&
        !templateResult.thinkingForcedOpen) {
      final markers = closedThoughtMarkers(templateResult.format);
      final held = StreamIterator(_heldUntilAny(tokenStream, markers));
      if (await held.moveNext()) {
        // Such a reply that reaches a marker then parses as after the
        // forced-open prompt llama.cpp renders.
        if (reopensClosedThought(templateResult.format) &&
            markers.any(held.current.contains)) {
          result = _withForcedOpenThought(templateResult);
        }
        tokens = _resumed(held);
      } else {
        tokens = const Stream.empty();
      }
    }
    yield* _parse(
      tokenStream: tokens,
      templateResult: result,
      parseToolCallsEnabled: parseToolCallsEnabled,
      enableThinking: enableThinking,
      modelName: modelName,
      completionId: completionId,
      tools: tools,
      stoppedAtLimit: stoppedAtLimit,
      cancelled: cancelled,
      usage: usage,
      runtimeToolCalls: runtimeToolCalls,
    );
  }

  static Stream<LlamaCompletionChunk> _parse({
    required Stream<String> tokenStream,
    required LlamaChatTemplateResult templateResult,
    required bool parseToolCallsEnabled,
    required bool enableThinking,
    required String modelName,
    required String completionId,
    List<ToolDefinition>? tools,
    bool Function()? stoppedAtLimit,
    bool Function()? cancelled,
    LlamaGenerationUsage? Function()? usage,
    List<LlamaCompletionChunkToolCall>? Function()? runtimeToolCalls,
  }) async* {
    final buffer = StringBuffer();
    var streamedContent = '';
    var streamedReasoning = '';
    const structuredPartialParseInterval = 8;
    const plainPartialParseProbeInterval = 4;
    const signalDrivenPartialParseMinTokens = 2;
    const partialParseMinIntervalMs = 24;
    var tokensSincePartialParse = 0;
    var sawStructuredOutputSignal = false;
    var didInitialPartialParse = false;
    var lastPartialParseAtMs = 0;
    final partialParseStopwatch = Stopwatch()..start();
    final traits = _traitsOf(templateResult);
    final bareCallOpenings = [
      if (bareFirstCallOf(templateResult))
        for (final tool in tools ?? const <ToolDefinition>[])
          XmlToolCallFormat.qwen3Coder.bareCallOpening(tool.name),
    ];
    final gatedOpening = _usesPegParser(templateResult)
        ? null
        : bareCallOpenings.isEmpty
        ? traits.toolCallOpening
        : (String text, int from) => ToolCallParsingUtils.literalOpening(text, [
            XmlToolCallFormat.qwen3CoderScopeStart,
            ...bareCallOpenings,
          ], from);
    final toolCallOpening = parseToolCallsEnabled ? gatedOpening : null;
    final isGptOss = templateResult.format == ChatFormat.gptOss.index;
    final isFunctionaryV32 =
        templateResult.format == ChatFormat.functionaryV32.index;
    final thinkingForcedClosed =
        !templateResult.thinkingForcedOpen &&
        thinkingForcedClosedOf(templateResult);
    final thoughtClosedForThinkingOff = thoughtClosedForThinkingOffOf(
      templateResult,
    );
    final pegParsedWithoutTools =
        !parseToolCallsEnabled && _usesPegParser(templateResult);
    // Functionary v3.2, MiniMax M1 and Muse Glimmer stream through their
    // partial parse with tools. A PEG parse after a closed thought has no
    // reasoning.
    final keepsThoughtTagsAsContent =
        traits.keepsThoughtTagsAsContent ||
        ((isFunctionaryV32 ||
                templateResult.format == ChatFormat.minimaxM1.index ||
                templateResult.format == ChatFormat.museGlimmer.index) &&
            !parseToolCallsEnabled) ||
        ((traits.closedThoughtKeepsTagsAsContent || pegParsedWithoutTools) &&
            thinkingForcedClosed);
    final isLlama3 =
        templateResult.format == ChatFormat.llama3.index ||
        templateResult.format == ChatFormat.llama3BuiltinTools.index;
    // Builtin calls may follow prose, while JSON calls must start the output,
    // so only the content gate waits at the builtin opening.
    final builtinOpening =
        parseToolCallsEnabled &&
            templateResult.format == ChatFormat.llama3BuiltinTools.index
        ? Llama3Handler.builtinCallOpening
        : null;
    final isQwen3CoderXml =
        templateResult.format == ChatFormat.qwen3CoderXml.index;
    final verbatimForcedThought =
        templateResult.thinkingForcedOpen && traits.keepsForcedThoughtVerbatim;
    final verbatimThoughtOpenings = verbatimForcedThought
        ? traits.forcedThoughtContentOpenings
        : const <String>[];
    final promptOpensNoThought =
        !templateResult.thinkingForcedOpen && !thoughtClosedForThinkingOff;
    // After a prompt that opens no thought, a reply has a thought only at its
    // start in these formats. A Seed-OSS or PEG-parsed reply keeps it as
    // generated, as the parse takes it.
    final verbatimLeadingThought =
        (templateResult.format == ChatFormat.seedOss.index ||
            pegParsedWithoutTools) &&
        promptOpensNoThought;
    final leadingThoughtOnly =
        verbatimLeadingThought ||
        (promptOpensNoThought && traits.takesThoughtOnlyAtReplyStart);
    final exactReplyStart =
        leadingThoughtOnly && traits.thoughtStartsReplyExactly;
    final verbatimThought = verbatimForcedThought || verbatimLeadingThought;
    final endsAtFirstEndTag = verbatimThought || leadingThoughtOnly;
    // After a prompt that opens no thought, the parse keeps an end tag before
    // any start tag as content, with every thinking tag after it.
    final unopenedEndTagIsContent =
        traits.closedThoughtKeepsTagsAsContent &&
        !templateResult.thinkingForcedOpen &&
        !thoughtClosedForThinkingOff;
    // Thinking tags in a Cohere2 MoE text or action are text.
    final bodyOpenings =
        templateResult.format == ChatFormat.cohere2Moe.index &&
            !templateResult.thinkingForcedOpen
        ? Cohere2MoeHandler.forcedThoughtContentOpenings
        : const <String>[];
    final contentGate = _ContentGate(
      toolCallOpening ?? builtinOpening ?? _noOpening,
      trimsLeading: !pegParsedWithoutTools,
    );
    final reasoningGate = _ReasoningGate(
      forcedOpen: templateResult.thinkingForcedOpen,
      forcedThoughtOpening: isQwen3CoderXml ? toolCallOpening : null,
      thoughtCallOpening: traits.parsesCallsInsideThoughts
          ? toolCallOpening
          : null,
      unescapes:
          toolCallOpening != null && !isQwen3CoderXml && !verbatimThought,
      trimsLeading: !pegParsedWithoutTools,
    );
    final gptOssFrames = _GptOssFrameStream(
      parseToolCalls: parseToolCallsEnabled,
    );
    final thoughtTags = _ThoughtTagState();
    // Without tools, Cohere2 MoE and Command R7B content streams raw, but
    // their parse drops the markers that wrap it.
    final responseMarkers =
        !parseToolCallsEnabled &&
            (templateResult.format == ChatFormat.cohere2Moe.index ||
                templateResult.format == ChatFormat.commandR7B.index)
        ? _MarkerFilter(CommandR7BHandler.responseMarkers)
        : null;
    var atForcedThoughtStart =
        gatedOpening != null &&
        templateResult.thinkingForcedOpen &&
        !verbatimForcedThought;
    var verbatimThoughtEnded = false;
    var atReplyStart = leadingThoughtOnly;
    // Channel-framed replies need their parser even without tool calling.
    final rawWithoutTools =
        !parseToolCallsEnabled &&
        !traits.hasRepeatedContentChannels &&
        !traits.endsThoughtAtToolCallOpening &&
        templateResult.format != ChatFormat.gemma4.index &&
        templateResult.format != ChatFormat.kimiK3.index;
    // A forced-open thought can transition straight into a tool envelope
    // without producing `</think>`. Start in parsed mode so that envelope is
    // never streamed as reasoning before the final structured parse. Gated
    // formats stream raw: Hermes parses such an envelope as reasoning, and
    // the Qwen3-Coder XML reasoning gate holds it back.
    // LFM's non-executable reasoning policy needs envelope-aware parsing:
    // raw thought-tag splitting also sees literal tags inside arguments.
    final parsesLfmToolChannels =
        parseToolCallsEnabled &&
        templateResult.format == ChatFormat.lfm2.index &&
        !traits.parsesCallsInsideThoughts;
    var streamingMode = parsesLfmToolChannels
        ? _ToolStreamingMode.parsed
        : rawWithoutTools || toolCallOpening != null
        ? _ToolStreamingMode.raw
        : templateResult.thinkingForcedOpen ||
              isFunctionaryV32 ||
              _usesPegParser(templateResult) ||
              traits.mayEmbedToolEnvelopeAfterContent
        ? _ToolStreamingMode.parsed
        : _ToolStreamingMode.undecided;
    var undecidedPrefix = '';
    final thinkingTags = ChatTemplateEngine.thinkingTagsFor(
      templateResult.format,
    );
    final startTag = thinkingTags.startTag;
    final endTag = thinkingTags.endTag;
    var isThinking = templateResult.thinkingForcedOpen;
    var pendingBuffer = '';

    await for (final token in tokenStream) {
      buffer.write(token);

      // GPT-OSS reasoning uses assistant channel frames, and the other formats
      // here extract no reasoning. Generic thought tags are literal text,
      // including when they occur inside tool arguments.
      if (isGptOss) {
        final (:content, :reasoning) = gptOssFrames.add(token);
        if (reasoning.isNotEmpty) {
          streamedReasoning += reasoning;
          if (enableThinking) {
            yield _chunk(
              completionId: completionId,
              modelName: modelName,
              delta: LlamaCompletionChunkDelta(thinking: reasoning),
            );
          }
        }
        if (content.isNotEmpty) {
          streamedContent += content;
          yield _chunk(
            completionId: completionId,
            modelName: modelName,
            delta: LlamaCompletionChunkDelta(content: content),
          );
        }
        continue;
      }
      if (keepsThoughtTagsAsContent) {
        final text = contentGate.add(token);
        if (text.isNotEmpty) {
          streamedContent += text;
          yield _chunk(
            completionId: completionId,
            modelName: modelName,
            delta: LlamaCompletionChunkDelta(content: text),
          );
        }
        continue;
      }

      if (streamingMode == _ToolStreamingMode.undecided) {
        undecidedPrefix += token;
        final decisionPrefix = _stripLeadingThinkingForToolDecision(
          undecidedPrefix,
          startTag: startTag,
          endTag: endTag,
        );
        if (decisionPrefix == null) {
          continue;
        }
        final mode = _decideToolStreamingMode(
          decisionPrefix,
          typedEnvelopes: isLlama3,
        );
        if (mode == _ToolStreamingMode.undecided) {
          continue;
        }

        if (mode == _ToolStreamingMode.raw) {
          streamingMode = _ToolStreamingMode.raw;
        } else {
          streamingMode = _ToolStreamingMode.parsed;
          undecidedPrefix = '';
        }
      }

      if (streamingMode == _ToolStreamingMode.raw) {
        if (undecidedPrefix.isNotEmpty) {
          pendingBuffer += undecidedPrefix;
          undecidedPrefix = '';
        } else if (token.isNotEmpty) {
          pendingBuffer += token;
        }

        // The parse drops a start tag the model repeats at the start of a
        // forced-open thought and treats the thought as opened by that tag.
        if (atForcedThoughtStart) {
          final rest = pendingBuffer.trimLeft();
          if (rest.length < startTag.length && startTag.startsWith(rest)) {
            continue;
          }
          atForcedThoughtStart = false;
          if (rest.startsWith(startTag)) {
            pendingBuffer = rest.substring(startTag.length);
            thoughtTags.sawStartTag = true;
            reasoningGate.leaveForcedThought();
          }
        }
        if (atReplyStart) {
          final rest = exactReplyStart
              ? pendingBuffer
              : trimLeftAsciiSpace(pendingBuffer);
          if ((rest.length < startTag.length && startTag.startsWith(rest)) ||
              (exactReplyStart &&
                  rest.length < endTag.length &&
                  endTag.startsWith(rest))) {
            continue;
          }
          atReplyStart = false;
          if (rest.startsWith(startTag)) {
            pendingBuffer = rest.substring(startTag.length);
            isThinking = true;
          } else {
            if (exactReplyStart && rest.startsWith(endTag)) {
              pendingBuffer = rest.substring(endTag.length);
            }
            verbatimThoughtEnded = true;
          }
        }

        final split = verbatimThoughtEnded
            ? _ThinkingSplitResult(
                pendingBuffer: '',
                isThinking: false,
                emissions: [
                  _ThinkingSplitEmission(
                    text: pendingBuffer,
                    isThinking: false,
                  ),
                ],
              )
            : _splitThinkingBuffer(
                pendingBuffer: pendingBuffer,
                isThinking: isThinking,
                startTag: startTag,
                endTag: endTag,
                tagState: thoughtTags,
                endsAtFirstEndTag: endsAtFirstEndTag,
                thoughtContentOpenings: verbatimThoughtOpenings,
                bodyOpenings: bodyOpenings,
                unopenedEndTagIsContent: unopenedEndTagIsContent,
              );
        if (split.bodyStarted ||
            (endsAtFirstEndTag &&
                split.emissions.any((emission) => emission.endsThinking))) {
          verbatimThoughtEnded = true;
        }
        pendingBuffer = split.pendingBuffer;
        isThinking = split.isThinking;
        for (final emission in split.emissions) {
          var text = emission.text;
          if (emission.isThinking) {
            text = reasoningGate.add(text);
            if (emission.endsThinking) {
              text += reasoningGate.end();
            }
            if (text.isEmpty) {
              continue;
            }
            streamedReasoning += text;
          } else {
            text = contentGate.add(responseMarkers?.add(text) ?? text);
            if (text.isEmpty) {
              continue;
            }
            streamedContent += text;
          }
          if (emission.isThinking && !enableThinking) {
            continue;
          }
          yield _chunk(
            completionId: completionId,
            modelName: modelName,
            delta: emission.isThinking
                ? LlamaCompletionChunkDelta(thinking: text)
                : LlamaCompletionChunkDelta(content: text),
          );
        }
        continue;
      }

      tokensSincePartialParse++;
      final tokenHasSignal = _mayNeedStructuredPartialParse(token);
      if (tokenHasSignal) {
        sawStructuredOutputSignal = true;
      }
      final elapsedMs = partialParseStopwatch.elapsedMilliseconds;
      final intervalElapsed =
          elapsedMs - lastPartialParseAtMs >= partialParseMinIntervalMs;
      final signalParseReady =
          tokenHasSignal &&
          intervalElapsed &&
          tokensSincePartialParse >= signalDrivenPartialParseMinTokens;
      final periodicParseReady =
          (sawStructuredOutputSignal &&
              tokensSincePartialParse >= structuredPartialParseInterval) ||
          (!sawStructuredOutputSignal &&
              tokensSincePartialParse >= plainPartialParseProbeInterval);
      final shouldRunPartialParse =
          !didInitialPartialParse || signalParseReady || periodicParseReady;
      if (!shouldRunPartialParse) {
        continue;
      }
      didInitialPartialParse = true;
      tokensSincePartialParse = 0;
      lastPartialParseAtMs = elapsedMs;

      try {
        final partialParsed = parseRenderedOutput(
          templateResult.format,
          buffer.toString(),
          isPartial: true,
          parseToolCalls: parseToolCallsEnabled,
          thinkingForcedOpen: templateResult.thinkingForcedOpen,
          thoughtClosedForThinkingOff: thoughtClosedForThinkingOff,
          singleToolCall: singleToolCallOf(templateResult),
          parser: templateResult.parser,
          tools: tools,
        );

        // A partial parse may keep a thought tag that is still arriving as
        // reasoning text; the final parse drops the tag once it completes and
        // keeps the start of one that the output ends in.
        var partialReasoning = withoutTrailingTagPrefix(
          partialParsed.reasoningContent ?? '',
          [startTag, endTag],
        ).trimRight();
        if (parsesLfmToolChannels) {
          // A pending backslash may become an unescaped newline next token.
          if (partialReasoning.endsWith(r'\')) {
            partialReasoning = partialReasoning.substring(
              0,
              partialReasoning.length - 1,
            );
          }
          partialReasoning = partialReasoning.trim();
        }
        final partialContent = partialParsed.content.trimRight();
        if (partialReasoning.length > streamedReasoning.length) {
          final delta = partialReasoning.substring(streamedReasoning.length);
          if (delta.isNotEmpty && enableThinking) {
            yield _chunk(
              completionId: completionId,
              modelName: modelName,
              delta: LlamaCompletionChunkDelta(thinking: delta),
            );
          }
        }

        final suppressToolEnvelopeContent =
            _isToolCallEnvelopeBuffer(
              buffer.toString(),
              startTag: startTag,
              endTag: endTag,
              thinkingForcedOpen: templateResult.thinkingForcedOpen,
              exactReplyStart: exactReplyStart,
            ) &&
            !partialParsed.hasToolCalls;
        if (!suppressToolEnvelopeContent &&
            partialContent.length > streamedContent.length) {
          final delta = partialContent.substring(streamedContent.length);
          if (delta.isNotEmpty) {
            yield _chunk(
              completionId: completionId,
              modelName: modelName,
              delta: LlamaCompletionChunkDelta(content: delta),
            );
          }
        }

        if (partialReasoning.length >= streamedReasoning.length) {
          streamedReasoning = partialReasoning;
        }
        if (!suppressToolEnvelopeContent &&
            partialContent.length >= streamedContent.length) {
          streamedContent = partialContent;
        }
      } catch (_) {
        // Partial parser failures are expected during incremental generation.
        // Keep buffering and let the final parse determine structured output.
      }
    }

    // Whitespace-only output never provides enough signal to leave the
    // undecided state. Preserve it verbatim at EOF, while continuing to
    // withhold non-whitespace partial control-marker prefixes.
    if (streamingMode == _ToolStreamingMode.undecided &&
        undecidedPrefix.trim().isEmpty &&
        undecidedPrefix.isNotEmpty) {
      streamingMode = _ToolStreamingMode.raw;
      pendingBuffer += undecidedPrefix;
      undecidedPrefix = '';
    }

    // Match PEG partial-close withholding for marker-free Ministral thoughts.
    // Tool-marked replies retain their existing EOF bytes.
    if (templateResult.format == ChatFormat.ministral.index &&
        !buffer.toString().contains('[TOOL_CALLS]') &&
        isThinking &&
        endTag.startsWith(pendingBuffer)) {
      pendingBuffer = '';
    }

    // A verbatim thought that has not ended holds only the start of a tag that
    // would end it; the final parse, which keeps it, supplies it.
    if (verbatimThought && isThinking && !pegParsedWithoutTools) {
      pendingBuffer = '';
    }

    pendingBuffer = isThinking
        ? reasoningGate.finish(pendingBuffer)
        : contentGate.add(responseMarkers?.add(pendingBuffer) ?? pendingBuffer);
    if (streamingMode == _ToolStreamingMode.raw && pendingBuffer.isNotEmpty) {
      if (isThinking) {
        streamedReasoning += pendingBuffer;
      } else {
        streamedContent += pendingBuffer;
      }
      if (!isThinking || enableThinking) {
        yield _chunk(
          completionId: completionId,
          modelName: modelName,
          delta: isThinking
              ? LlamaCompletionChunkDelta(thinking: pendingBuffer)
              : LlamaCompletionChunkDelta(content: pendingBuffer),
        );
      }
    }

    final fullOutput = buffer.toString();
    final endedAtLimit = stoppedAtLimit?.call() == true;
    final wasCancelled = cancelled?.call() == true;
    ChatParseResult parseOutput({required bool isPartial}) =>
        parseRenderedOutput(
          templateResult.format,
          fullOutput,
          isPartial: isPartial,
          cancelled: wasCancelled,
          parseToolCalls: parseToolCallsEnabled,
          thinkingForcedOpen: templateResult.thinkingForcedOpen,
          thoughtClosedForThinkingOff: thoughtClosedForThinkingOff,
          thinkingForcedClosed: thinkingForcedClosed,
          singleToolCall: singleToolCallOf(templateResult),
          bareFirstCall: bareFirstCallOf(templateResult),
          parser: templateResult.parser,
          tools: tools,
        );
    ChatParseResult parsed;
    var parsedAsPartial = false;
    try {
      parsed = parseOutput(isPartial: false);
    } on LlamaInferenceException {
      if (!endedAtLimit && !wasCancelled) rethrow;
      parsed = parseOutput(isPartial: true);
      parsedAsPartial = true;
    }
    // Only a backend-reported limit authorizes replacing answer bytes with
    // diagnostic data. EOF/cancellation keep their established terminal policy.
    if (endedAtLimit && !wasCancelled && parsesLfmToolChannels) {
      final partial = parseOutput(isPartial: true);
      if (partial.partialToolCalls.isNotEmpty) parsed = partial;
    }
    final runtimeCalls = parseToolCallsEnabled
        ? runtimeToolCalls?.call() ?? const <LlamaCompletionChunkToolCall>[]
        : const <LlamaCompletionChunkToolCall>[];
    if (runtimeCalls.isNotEmpty) {
      final calls = [...parsed.toolCalls, ...runtimeCalls];
      parsed = ChatParseResult(
        content: parsed.content,
        reasoningContent: parsed.reasoningContent,
        toolCalls: [
          for (var i = 0; i < calls.length; i++)
            LlamaCompletionChunkToolCall(
              index: i,
              id: calls[i].id,
              type: calls[i].type,
              function: calls[i].function,
            ),
        ],
        partialToolCalls: parsed.partialToolCalls,
      );
    }

    final finalReasoning = parsesLfmToolChannels
        ? (parsed.reasoningContent ?? '').trimLeft()
        : parsed.reasoningContent ?? '';
    final reasoningDelta = _computeFinalReconciliationDelta(
      streamedValue: streamedReasoning,
      finalValue: finalReasoning,
      channel: 'thinking',
    );
    if (reasoningDelta != null && reasoningDelta.isNotEmpty && enableThinking) {
      yield _chunk(
        completionId: completionId,
        modelName: modelName,
        delta: LlamaCompletionChunkDelta(thinking: reasoningDelta),
      );
    }

    final suppressFinalToolEnvelopeContent =
        toolCallOpening == null &&
        // Gemma 4 and MiniMax M1 sanitize their envelopes and retain
        // post-call text.
        templateResult.format != ChatFormat.gemma4.index &&
        templateResult.format != ChatFormat.minimaxM1.index &&
        !traits.retainsTextAroundToolCalls &&
        parsed.hasToolCalls &&
        _isToolCallEnvelopeBuffer(
          fullOutput,
          startTag: startTag,
          endTag: endTag,
          thinkingForcedOpen: templateResult.thinkingForcedOpen,
          exactReplyStart: exactReplyStart,
          thinkingTagsAreContent: verbatimForcedThought,
        );
    final contentDelta = suppressFinalToolEnvelopeContent
        ? null
        : _computeFinalReconciliationDelta(
            streamedValue: streamedContent,
            finalValue: parsed.content,
            channel: 'content',
          );
    if (contentDelta != null && contentDelta.isNotEmpty) {
      yield _chunk(
        completionId: completionId,
        modelName: modelName,
        delta: LlamaCompletionChunkDelta(content: contentDelta),
      );
    }

    LlamaLogger.instance.debug(
      'Parsed completion: contentChars=${parsed.content.length}, '
      'reasoningChars=${parsed.reasoningContent?.length ?? 0}, '
      'toolCallCount=${parsed.toolCalls.length}',
    );

    if (parsed.hasToolCalls && !endedAtLimit && !parsedAsPartial) {
      final toolCallsWithIds = parsed.toolCalls
          .map(
            (toolCall) => LlamaCompletionChunkToolCall(
              index: toolCall.index,
              id: (toolCall.id == null || toolCall.id!.isEmpty)
                  ? 'call_${toolCall.index}'
                  : toolCall.id,
              type: toolCall.type,
              function: toolCall.function,
            ),
          )
          .toList(growable: false);
      yield _chunk(
        completionId: completionId,
        modelName: modelName,
        delta: LlamaCompletionChunkDelta(toolCalls: toolCallsWithIds),
        finishReason: 'tool_calls',
        usage: usage?.call(),
      );
    } else {
      yield _chunk(
        completionId: completionId,
        modelName: modelName,
        delta: LlamaCompletionChunkDelta(
          partialToolCalls:
              endedAtLimit &&
                  !wasCancelled &&
                  parsed.partialToolCalls.isNotEmpty
              ? parsed.partialToolCalls
              : null,
        ),
        finishReason: endedAtLimit ? 'length' : 'stop',
        usage: usage?.call(),
      );
    }
  }

  static LlamaCompletionChunk _chunk({
    required String completionId,
    required String modelName,
    required LlamaCompletionChunkDelta delta,
    String? finishReason,
    LlamaGenerationUsage? usage,
  }) {
    return LlamaCompletionChunk(
      id: 'chatcmpl-$completionId',
      object: 'chat.completion.chunk',
      created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      model: modelName,
      choices: [
        LlamaCompletionChunkChoice(
          index: 0,
          delta: delta,
          finishReason: finishReason,
        ),
      ],
      usage: usage,
    );
  }

  static bool _mayNeedStructuredPartialParse(String token) {
    for (var i = 0; i < token.length; i++) {
      switch (token.codeUnitAt(i)) {
        case 0x22: // "
        case 0x2C: // ,
        case 0x3A: // :
        case 0x3C: // <
        case 0x3E: // >
        case 0x5B: // [
        case 0x5C: // \
        case 0x5D: // ]
        case 0x7B: // {
        case 0x7D: // }
          return true;
      }
    }
    return false;
  }

  /// The traits of [templateResult]'s format, or none for an unknown format.
  static ChatFormatTraits _traitsOf(LlamaChatTemplateResult templateResult) =>
      templateResult.format < ChatFormat.values.length
      ? chatFormatRegistration(ChatFormat.values[templateResult.format]).traits
      : ChatFormatTraits.none;

  /// Whether the parse uses [PegChatParser], whose partial parse holds back
  /// a possible tool-call opening itself.
  static bool _usesPegParser(LlamaChatTemplateResult templateResult) {
    final format = templateResult.format;
    return format < ChatFormat.values.length &&
        pegParseFormat(ChatFormat.values[format], templateResult.parser) !=
            null;
  }

  static int _noOpening(String text, int from) => text.length;

  /// [held]'s current text, then the rest of it.
  static Stream<String> _resumed(StreamIterator<String> held) async* {
    try {
      yield held.current;
      while (await held.moveNext()) {
        yield held.current;
      }
    } finally {
      await held.cancel();
    }
  }

  /// [result] with its prompt's thought forced open.
  static LlamaChatTemplateResult _withForcedOpenThought(
    LlamaChatTemplateResult result,
  ) => withSingleToolCall(
    withThinkingForcedClosed(
      LlamaChatTemplateResult(
        prompt: result.prompt,
        format: result.format,
        grammar: result.grammar,
        grammarLazy: result.grammarLazy,
        additionalStops: result.additionalStops,
        preservedTokens: result.preservedTokens,
        grammarTriggers: result.grammarTriggers,
        thinkingForcedOpen: true,
        parser: result.parser,
        tokenCount: result.tokenCount,
      ),
      closed: thinkingForcedClosedOf(result),
    ),
    single: singleToolCallOf(result),
  );

  /// [tokens] with their text held until it contains one of [markers], or
  /// [tokens] ends.
  static Stream<String> _heldUntilAny(
    Stream<String> tokens,
    List<String> markers,
  ) async* {
    final longest = markers.fold(
      0,
      (length, marker) => marker.length > length ? marker.length : length,
    );
    String? held = '';
    await for (final token in tokens) {
      if (held == null) {
        yield token;
        continue;
      }
      final scanFrom = held.length - longest;
      final text = held + token;
      final from = scanFrom < 0 ? 0 : scanFrom;
      if (markers.any((marker) => text.contains(marker, from))) {
        yield text;
        held = null;
      } else {
        held = text;
      }
    }
    if (held != null && held.isNotEmpty) yield held;
  }

  /// [text] without a trailing proper prefix of any of [tags].
  static int? _firstNonWhitespaceIndex(String value) {
    for (var i = 0; i < value.length; i++) {
      if (!_isWhitespaceCodeUnit(value.codeUnitAt(i))) {
        return i;
      }
    }
    return null;
  }

  static _ToolStreamingMode _decideToolStreamingMode(
    String value, {
    required bool typedEnvelopes,
  }) {
    const maxProbeChars = 256;
    final start = _firstNonWhitespaceIndex(value);
    if (start == null) {
      return _ToolStreamingMode.undecided;
    }

    final trimmed = value.substring(start);
    if (trimmed.isEmpty) {
      return _ToolStreamingMode.undecided;
    }

    final first = trimmed.codeUnitAt(0);
    _ToolStreamingMode mode;
    if (first == 0x7B) {
      mode = _decideJsonEnvelopeMode(trimmed, typedEnvelopes: typedEnvelopes);
    } else if (first == 0x3C) {
      mode = _decideXmlEnvelopeMode(trimmed);
    } else if (first == 0x5B) {
      mode = _decideBracketEnvelopeMode(trimmed);
    } else {
      mode = _ToolStreamingMode.raw;
    }

    if (mode == _ToolStreamingMode.undecided &&
        trimmed.length >= maxProbeChars) {
      return _ToolStreamingMode.raw;
    }

    return mode;
  }

  /// [value] without the thoughts that start it, or null while one may still
  /// be arriving. With [exactReplyStart], only a thought or an end tag that
  /// starts [value], with no whitespace before it, is stripped, as the parse
  /// takes it.
  static String? _stripLeadingThinkingForToolDecision(
    String value, {
    required String startTag,
    required String endTag,
    bool exactReplyStart = false,
  }) {
    if (exactReplyStart) {
      if (startTag.startsWith(value) || endTag.startsWith(value)) {
        return null;
      }
      if (value.startsWith(endTag)) return value.substring(endTag.length);
      if (!value.startsWith(startTag)) return value;
      final afterStart = value.substring(startTag.length);
      final endIndex = afterStart.indexOf(endTag);
      return endIndex < 0
          ? null
          : afterStart.substring(endIndex + endTag.length);
    }
    var remaining = value;
    while (true) {
      final start = _firstNonWhitespaceIndex(remaining);
      if (start == null) {
        return remaining;
      }

      final leading = remaining.substring(0, start);
      final trimmed = remaining.substring(start);
      if (startTag.startsWith(trimmed) || endTag.startsWith(trimmed)) {
        return null;
      }

      if (trimmed.startsWith(endTag)) {
        remaining = leading + trimmed.substring(endTag.length);
        continue;
      }

      if (trimmed.startsWith(startTag)) {
        final afterStart = trimmed.substring(startTag.length);
        final endIndex = afterStart.indexOf(endTag);
        if (endIndex < 0) {
          return null;
        }
        remaining = leading + afterStart.substring(endIndex + endTag.length);
        continue;
      }

      return remaining;
    }
  }

  static _ToolStreamingMode _decideJsonEnvelopeMode(
    String text, {
    required bool typedEnvelopes,
  }) {
    var i = 1;
    while (i < text.length && _isWhitespaceCodeUnit(text.codeUnitAt(i))) {
      i++;
    }

    if (i >= text.length) {
      return _ToolStreamingMode.undecided;
    }

    if (text.codeUnitAt(i) != 0x22) {
      return _ToolStreamingMode.raw;
    }

    i++;
    final keyStart = i;
    while (i < text.length) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x22) {
        final key = text.substring(keyStart, i);
        return _isGenericEnvelopeKey(key) || (typedEnvelopes && key == 'type')
            ? _ToolStreamingMode.parsed
            : _ToolStreamingMode.raw;
      }
      if (ch == 0x5C) {
        if (i + 1 >= text.length) {
          return _ToolStreamingMode.undecided;
        }
        i += 2;
        continue;
      }
      i++;
    }

    return _ToolStreamingMode.undecided;
  }

  static bool _isGenericEnvelopeKey(String key) {
    return key == 'tool_call' ||
        key == 'tool_calls' ||
        key == 'response' ||
        key == 'name';
  }

  static bool _isToolCallEnvelopeBuffer(
    String text, {
    required String startTag,
    required String endTag,
    required bool thinkingForcedOpen,
    bool exactReplyStart = false,
    bool thinkingTagsAreContent = false,
  }) {
    if (thinkingForcedOpen &&
        _containsForcedOpenXmlToolEnvelope(text, endTag: endTag)) {
      return true;
    }

    // The parse ends a verbatim forced-open thought at the first end tag and
    // keeps every later thinking tag as content.
    final thoughtEnd = thinkingTagsAreContent ? text.indexOf(endTag) : -1;
    final decisionText = thoughtEnd >= 0
        ? text.substring(thoughtEnd + endTag.length)
        : _stripLeadingThinkingForToolDecision(
            text,
            startTag: startTag,
            endTag: endTag,
            exactReplyStart: exactReplyStart,
          );
    if (decisionText == null) {
      return true;
    }

    final start = _firstNonWhitespaceIndex(decisionText);
    if (start == null) {
      return false;
    }

    final trimmed = decisionText.substring(start);
    if (trimmed.isEmpty) {
      return false;
    }

    if (RegExp(r'^\{\s*"tool_calls?"\s*:').hasMatch(trimmed)) {
      return true;
    }

    final first = trimmed.codeUnitAt(0);
    if (first == 0x5B) {
      return _decideBracketEnvelopeMode(trimmed) != _ToolStreamingMode.raw;
    }
    if (first == 0x3C) {
      final lower = trimmed.toLowerCase();
      return lower.startsWith('<tool_call') ||
          lower.startsWith('<tool_calls') ||
          lower.startsWith('<|tool_call') ||
          lower.startsWith('<|start_action|>') ||
          lower.startsWith('<function') ||
          lower.startsWith('<function_call') ||
          lower.startsWith('<start_function_call') ||
          lower.startsWith('<|python_tag|>');
    }

    return false;
  }

  static bool _containsXmlToolEnvelope(String text) {
    final lower = text.toLowerCase();
    return lower.contains('<tool_call') ||
        lower.contains('<tool_calls') ||
        lower.contains('<function=') ||
        lower.contains('<function_call');
  }

  static bool _containsForcedOpenXmlToolEnvelope(
    String text, {
    required String endTag,
  }) {
    final thoughtEnd = text.indexOf(endTag);
    if (thoughtEnd < 0) {
      return _containsXmlToolEnvelope(text);
    }

    final afterThought = text.substring(thoughtEnd + endTag.length);
    final first = _firstNonWhitespaceIndex(afterThought);
    if (first == null) {
      return false;
    }
    final lower = afterThought.substring(first).toLowerCase();
    return lower.startsWith('<tool_call') ||
        lower.startsWith('<tool_calls') ||
        lower.startsWith('<function=') ||
        lower.startsWith('<function_call');
  }

  static _ToolStreamingMode _decideBracketEnvelopeMode(String text) {
    const marker = '[TOOL_CALLS]';
    final upper = text.toUpperCase();
    if (upper.startsWith(marker)) {
      return _ToolStreamingMode.parsed;
    }
    if (marker.startsWith(upper)) {
      return _ToolStreamingMode.undecided;
    }
    return _decideBareActionArrayEnvelopeMode(text);
  }

  static _ToolStreamingMode _decideBareActionArrayEnvelopeMode(String text) {
    var i = 1;
    while (i < text.length && _isWhitespaceCodeUnit(text.codeUnitAt(i))) {
      i++;
    }
    if (i >= text.length) {
      return _ToolStreamingMode.undecided;
    }
    if (text.codeUnitAt(i) != 0x7B) {
      return _ToolStreamingMode.raw;
    }

    i++;
    while (i < text.length && _isWhitespaceCodeUnit(text.codeUnitAt(i))) {
      i++;
    }
    if (i >= text.length) {
      return _ToolStreamingMode.undecided;
    }
    if (text.codeUnitAt(i) != 0x22) {
      return _ToolStreamingMode.raw;
    }

    final key = _readLeadingJsonObjectKey(text, i);
    if (!key.complete) {
      return _ToolStreamingMode.undecided;
    }
    if (key.value == null) {
      return _ToolStreamingMode.raw;
    }

    i = key.nextIndex;
    while (i < text.length && _isWhitespaceCodeUnit(text.codeUnitAt(i))) {
      i++;
    }
    if (i >= text.length) {
      return _ToolStreamingMode.undecided;
    }
    if (text.codeUnitAt(i) != 0x3A) {
      return _ToolStreamingMode.raw;
    }

    return _isCommandBareActionKey(key.value!)
        ? _ToolStreamingMode.parsed
        : _ToolStreamingMode.raw;
  }

  static ({bool complete, String? value, int nextIndex})
  _readLeadingJsonObjectKey(String text, int quoteIndex) {
    final buffer = StringBuffer();
    var i = quoteIndex + 1;
    while (i < text.length) {
      final ch = text.codeUnitAt(i);
      if (ch == 0x22) {
        return (complete: true, value: buffer.toString(), nextIndex: i + 1);
      }
      if (ch == 0x5C) {
        if (i + 1 >= text.length) {
          return (complete: false, value: null, nextIndex: i);
        }
        buffer.writeCharCode(text.codeUnitAt(i + 1));
        i += 2;
        continue;
      }
      buffer.writeCharCode(ch);
      i++;
    }

    return (complete: false, value: null, nextIndex: text.length);
  }

  static bool _isCommandBareActionKey(String key) {
    return key == 'tool_name' || key == 'tool_call_id';
  }

  static _ToolStreamingMode _decideXmlEnvelopeMode(String text) {
    final lower = text.toLowerCase();
    const parsedPrefixes = <String>[
      '<tool_call',
      '<tool_calls',
      '<|tool_call',
      '<|start_action|>',
      '<|start_text|>',
      '<function',
      '<function_call',
      '<start_function_call',
      '<|python_tag|>',
      '<tool_response',
    ];

    for (final prefix in parsedPrefixes) {
      if (lower.startsWith(prefix)) {
        return _ToolStreamingMode.parsed;
      }
      if (prefix.startsWith(lower)) {
        return _ToolStreamingMode.undecided;
      }
    }

    final tagNameMatch = RegExp(
      r'^<\s*/?\s*([a-zA-Z_][a-zA-Z0-9_:-]*)',
    ).firstMatch(lower);
    if (tagNameMatch != null) {
      final tagName = tagNameMatch.group(1);
      if (tagName == 'tool_call' ||
          tagName == 'tool_calls' ||
          tagName == 'function' ||
          tagName == 'function_call' ||
          tagName == 'start_function_call' ||
          tagName == 'tool_response') {
        return _ToolStreamingMode.parsed;
      }
      return _ToolStreamingMode.raw;
    }

    if (RegExp(r'^<\s*/?\s*[a-zA-Z_][a-zA-Z0-9_:-]*$').hasMatch(lower)) {
      return _ToolStreamingMode.undecided;
    }

    return _ToolStreamingMode.raw;
  }

  static _ThinkingSplitResult _splitThinkingBuffer({
    required String pendingBuffer,
    required bool isThinking,
    required String startTag,
    required String endTag,
    required _ThoughtTagState tagState,
    bool endsAtFirstEndTag = false,
    List<String> thoughtContentOpenings = const [],
    List<String> bodyOpenings = const [],
    bool unopenedEndTagIsContent = false,
  }) {
    final emissions = <_ThinkingSplitEmission>[];
    var localPendingBuffer = pendingBuffer;
    var localIsThinking = isThinking;
    var bodyStarted = false;

    while (localPendingBuffer.isNotEmpty) {
      if (!localIsThinking) {
        final startIdx = localPendingBuffer.indexOf(startTag);
        var endIdx = localPendingBuffer.indexOf(endTag);
        if (endIdx != -1 && tagState.endTagIsContent && !(startIdx > endIdx)) {
          endIdx = -1;
        }
        if (unopenedEndTagIsContent &&
            !tagState.sawStartTag &&
            endIdx != -1 &&
            (startIdx == -1 || endIdx < startIdx)) {
          emissions.add(
            _ThinkingSplitEmission(text: localPendingBuffer, isThinking: false),
          );
          localPendingBuffer = '';
          bodyStarted = true;
          break;
        }
        var bodyIdx = -1;
        for (final opening in bodyOpenings) {
          final at = localPendingBuffer.indexOf(opening);
          if (at != -1 && (bodyIdx == -1 || at < bodyIdx)) bodyIdx = at;
        }
        if (bodyIdx != -1 &&
            (startIdx == -1 || bodyIdx < startIdx) &&
            (endIdx == -1 || bodyIdx < endIdx)) {
          emissions.add(
            _ThinkingSplitEmission(text: localPendingBuffer, isThinking: false),
          );
          localPendingBuffer = '';
          bodyStarted = true;
          break;
        }

        if (startIdx != -1 && (endIdx == -1 || startIdx < endIdx)) {
          final before = localPendingBuffer.substring(0, startIdx);
          if (before.isNotEmpty) {
            emissions.add(
              _ThinkingSplitEmission(text: before, isThinking: false),
            );
          }
          localIsThinking = true;
          tagState.sawStartTag = true;
          localPendingBuffer = localPendingBuffer.substring(
            startIdx + startTag.length,
          );
          continue;
        } else if (endIdx != -1) {
          emissions.add(
            _ThinkingSplitEmission(
              text: localPendingBuffer.substring(0, endIdx),
              isThinking: true,
              endsThinking: true,
            ),
          );
          localIsThinking = false;
          tagState.sawEndTag = true;
          localPendingBuffer = localPendingBuffer.substring(
            endIdx + endTag.length,
          );
          continue;
        }

        var potentialMatch = false;
        if (bodyOpenings.isNotEmpty) {
          final emitIdx = withoutTrailingTagPrefix(localPendingBuffer, [
            startTag,
            ...bodyOpenings,
          ]).length;
          if (emitIdx < localPendingBuffer.length) {
            if (emitIdx > 0) {
              emissions.add(
                _ThinkingSplitEmission(
                  text: localPendingBuffer.substring(0, emitIdx),
                  isThinking: false,
                ),
              );
              localPendingBuffer = localPendingBuffer.substring(emitIdx);
            }
            break;
          }
        }
        // An end tag that ends a thought the prompt opened must not stream
        // as content when it arrives split across tokens.
        final emitIdx = withoutTrailingTagPrefix(localPendingBuffer, [
          startTag,
          if (!tagState.endTagIsContent) endTag,
        ]).length;
        if (emitIdx < localPendingBuffer.length) {
          if (emitIdx > 0) {
            emissions.add(
              _ThinkingSplitEmission(
                text: localPendingBuffer.substring(0, emitIdx),
                isThinking: false,
              ),
            );
            localPendingBuffer = localPendingBuffer.substring(emitIdx);
          }
          potentialMatch = true;
        }
        if (!potentialMatch) {
          emissions.add(
            _ThinkingSplitEmission(text: localPendingBuffer, isThinking: false),
          );
          localPendingBuffer = '';
        }
        break;
      }

      var endIdx = localPendingBuffer.indexOf(endTag);
      var contentIdx = endIdx == -1 ? -1 : endIdx + endTag.length;
      for (final opening in thoughtContentOpenings) {
        final at = localPendingBuffer.indexOf(opening);
        if (at != -1 && (endIdx == -1 || at < endIdx)) {
          endIdx = at;
          contentIdx = at;
        }
      }
      if (endIdx != -1) {
        emissions.add(
          _ThinkingSplitEmission(
            text: localPendingBuffer.substring(0, endIdx),
            isThinking: true,
            endsThinking: true,
          ),
        );
        localIsThinking = false;
        tagState.sawEndTag = true;
        localPendingBuffer = localPendingBuffer.substring(contentIdx);
        if (endsAtFirstEndTag) {
          if (localPendingBuffer.isNotEmpty) {
            emissions.add(
              _ThinkingSplitEmission(
                text: localPendingBuffer,
                isThinking: false,
              ),
            );
          }
          localPendingBuffer = '';
          break;
        }
        continue;
      }

      final held =
          localPendingBuffer.length -
          withoutTrailingTagPrefix(localPendingBuffer, [
            endTag,
            ...thoughtContentOpenings,
          ]).length;
      final potentialMatch = held > 0;
      if (potentialMatch) {
        final emitIdx = localPendingBuffer.length - held;
        if (emitIdx > 0) {
          emissions.add(
            _ThinkingSplitEmission(
              text: localPendingBuffer.substring(0, emitIdx),
              isThinking: true,
            ),
          );
          localPendingBuffer = localPendingBuffer.substring(emitIdx);
        }
      }
      if (!potentialMatch) {
        emissions.add(
          _ThinkingSplitEmission(text: localPendingBuffer, isThinking: true),
        );
        localPendingBuffer = '';
      }
      break;
    }

    return _ThinkingSplitResult(
      pendingBuffer: localPendingBuffer,
      isThinking: localIsThinking,
      emissions: emissions,
      bodyStarted: bodyStarted,
    );
  }

  static String? _computeFinalReconciliationDelta({
    required String streamedValue,
    required String finalValue,
    required String channel,
  }) {
    if (!finalValue.startsWith(streamedValue)) {
      // Streams trim leading whitespace that a final parse may keep, for
      // example in a forced-open thought that never closes.
      final trimmed = finalValue.trimLeft();
      if (streamedValue.isNotEmpty && trimmed.startsWith(streamedValue)) {
        finalValue = trimmed;
      }
    }

    if (finalValue.length <= streamedValue.length) {
      return null;
    }

    if (!finalValue.startsWith(streamedValue)) {
      LlamaLogger.instance.warning(
        'Skipping final $channel delta due to prefix mismatch '
        '(streamed=${streamedValue.length}, final=${finalValue.length})',
      );
      return null;
    }

    return finalValue.substring(streamedValue.length);
  }

  static bool _isWhitespaceCodeUnit(int codeUnit) {
    return codeUnit == 0x20 || // space
        codeUnit == 0x09 || // \t
        codeUnit == 0x0A || // \n
        codeUnit == 0x0D; // \r
  }
}

/// Drops [markers] from streamed text, holding back a trailing prefix of one
/// until it completes. The final parse reconciles a prefix that never does.
class _MarkerFilter {
  _MarkerFilter(this.markers);

  final List<String> markers;
  var _pending = '';

  /// Adds [text] and returns the newly released text.
  String add(String text) {
    _pending += text;
    for (final marker in markers) {
      _pending = _pending.replaceAll(marker, '');
    }
    var held = 0;
    for (final marker in markers) {
      for (var length = marker.length - 1; length > held; length--) {
        if (_pending.endsWith(marker.substring(0, length))) {
          held = length;
          break;
        }
      }
    }
    final released = _pending.substring(0, _pending.length - held);
    _pending = _pending.substring(_pending.length - held);
    return released;
  }
}

/// Releases raw content that the final parse keeps.
///
/// The parse trims content, keeping only the whitespace after content that
/// ends the output, and the parse of a tool-call format drops tool-call
/// envelopes from it. Text from a possible envelope opening on, found by the
/// [_opening] scanner, and trailing whitespace wait for more output. After a
/// whole opening, nothing more is released, and the final parse supplies the
/// rest of the content, as it does that whitespace. Leading whitespace is
/// dropped when [trimsLeading] is true and otherwise waits for other text.
class _ContentGate {
  _ContentGate(this._opening, {required this.trimsLeading});

  final int Function(String text, int from) _opening;
  final bool trimsLeading;
  var _pending = '';
  var _scanFrom = 0;
  var _releasedAny = false;

  /// Adds [content] and returns the newly released text.
  String add(String content) {
    _pending += content;
    _scanFrom = _opening(_pending, _scanFrom);
    var end = _scanFrom;
    while (end > 0 && _isTrimmed(_pending.codeUnitAt(end - 1))) {
      end--;
    }
    var start = 0;
    if (trimsLeading && !_releasedAny) {
      while (start < end && _isTrimmed(_pending.codeUnitAt(start))) {
        start++;
      }
    }
    if (start == end) {
      return '';
    }
    final released = _pending.substring(start, end);
    _pending = _pending.substring(end);
    _scanFrom -= end;
    _releasedAny = true;
    return released;
  }

  static bool _isTrimmed(int codeUnit) =>
      String.fromCharCode(codeUnit).trim().isEmpty;
}

/// Releases GPT-OSS output as its parse classifies it.
///
/// Text outside assistant frames and the bodies of `final`, `commentary` and
/// other non-call frames are content, `analysis` bodies are reasoning, and
/// tool-call bodies wait for the final parse. A frame header waits for
/// `<|message|>`, since the parse drops a header that never completes. The
/// parse trims each part and joins a channel's non-empty parts with a
/// newline, so leading whitespace of a part is dropped and trailing
/// whitespace waits for more text.
class _GptOssFrameStream {
  _GptOssFrameStream({required this.parseToolCalls});

  static const _assistantStart = '<|start|>assistant';
  static const _messageTag = '<|message|>';
  static const _endTag = '<|end|>';
  static const _continuations = ['<|channel|>', 'to=functions.'];

  final bool parseToolCalls;
  final _content = _JoinedParts();
  final _reasoning = _JoinedParts();
  var _pending = '';
  var _headerScanFrom = 0;
  var _atOutputStart = true;
  var _inHeader = false;
  var _inBody = false;
  _JoinedParts? _body;

  /// Adds [text] and returns the newly released content and reasoning.
  ({String content, String reasoning}) add(String text) {
    _pending += text;
    final content = StringBuffer();
    final reasoning = StringBuffer();
    void release(_JoinedParts? channel, String text) {
      if (identical(channel, _content)) {
        content.write(_content.add(text));
      } else if (identical(channel, _reasoning)) {
        reasoning.write(_reasoning.add(text));
      }
    }

    while (true) {
      if (_atOutputStart) {
        final leading = _pending.trimLeft();
        if (leading.isEmpty) break;
        if (_continuations.any(leading.startsWith)) {
          // The prompt already ended with an assistant header.
          _pending = leading;
          _atOutputStart = false;
          _inHeader = true;
          continue;
        }
        if (_continuations.any((literal) => literal.startsWith(leading))) {
          break;
        }
        _atOutputStart = false;
      }
      if (_inHeader) {
        final message = _pending.indexOf(_messageTag, _headerScanFrom);
        if (message < 0) {
          _headerScanFrom = _pending.length - _messageTag.length + 1;
          if (_headerScanFrom < 0) _headerScanFrom = 0;
          break;
        }
        _body = _bodyChannel(_pending.substring(0, message));
        _pending = _pending.substring(message + _messageTag.length);
        _headerScanFrom = 0;
        _inHeader = false;
        _inBody = true;
        continue;
      }
      if (_inBody) {
        final end = _pending.indexOf(_endTag);
        if (end < 0) {
          final hold = _trailingPrefixLength(_pending, _endTag);
          release(_body, _pending.substring(0, _pending.length - hold));
          _pending = _pending.substring(_pending.length - hold);
          break;
        }
        release(_body, _pending.substring(0, end));
        _body?.endPart();
        _pending = _pending.substring(end + _endTag.length);
        _inBody = false;
        continue;
      }
      final start = _pending.indexOf(_assistantStart);
      if (start < 0) {
        final hold = _trailingPrefixLength(_pending, _assistantStart);
        release(_content, _pending.substring(0, _pending.length - hold));
        _pending = _pending.substring(_pending.length - hold);
        break;
      }
      release(_content, _pending.substring(0, start));
      _content.endPart();
      _pending = _pending.substring(start + _assistantStart.length);
      _inHeader = true;
    }
    return (content: content.toString(), reasoning: reasoning.toString());
  }

  _JoinedParts? _bodyChannel(String header) {
    if (parseToolCalls && header.contains(RegExp(r'to=functions\.[^<\s]'))) {
      return null;
    }
    final channel = RegExp(
      r'<\|channel\|>([a-zA-Z0-9_-]+)',
    ).firstMatch(header)?.group(1);
    return channel == 'analysis' ? _reasoning : _content;
  }

  static int _trailingPrefixLength(String text, String literal) {
    for (var length = literal.length - 1; length > 0; length--) {
      if (text.endsWith(literal.substring(0, length))) return length;
    }
    return 0;
  }
}

/// A channel whose trimmed, non-empty parts are joined with a newline.
class _JoinedParts {
  var _hasParts = false;
  var _inPart = false;
  var _whitespace = '';

  /// Adds [text] to the current part and returns the released text.
  String add(String text) {
    if (!_inPart) {
      text = text.trimLeft();
      if (text.isEmpty) return '';
      _inPart = true;
      text = '${_hasParts ? '\n' : ''}$text';
      _hasParts = true;
    } else {
      text = '$_whitespace$text';
    }
    final body = text.trimRight();
    _whitespace = text.substring(body.length);
    return body;
  }

  /// Ends the current part, dropping its trailing whitespace.
  void endPart() {
    _inPart = false;
    _whitespace = '';
  }
}

/// Releases raw reasoning that the final parse keeps.
///
/// The parse replaces escaped `\n` and `\r` unless [unescapes] is false,
/// trims the end of each thought, trims its start unless [trimsLeading] is
/// false, and joins non-empty thoughts with a newline. Whitespace that may end
/// a thought waits for more reasoning. The final parse keeps a forced-open
/// thought that never ends untrimmed; the final reconciliation adds its
/// trailing whitespace only when the thought has no leading whitespace.
///
/// With a forced-thought opening scanner, a tool-call opening also ends a
/// forced-open thought, as the Qwen3-Coder XML parse does when the output has
/// no thinking tag. Text from a possible opening on waits: `</think>` releases
/// it, and at the end of the stream the final parse supplies the rest.
///
/// With a thought call opening, the parse removes tool calls from any thought.
/// Text from a possible opening on waits, and a thought that ends while held
/// stops all later release, so the final parse supplies the rest.
class _ReasoningGate {
  _ReasoningGate({
    required bool forcedOpen,
    required this.unescapes,
    required this.trimsLeading,
    int Function(String text, int from)? forcedThoughtOpening,
    int Function(String text, int from)? thoughtCallOpening,
  }) : _inForcedThought = forcedOpen,
       _forcedThoughtOpening = forcedThoughtOpening,
       _thoughtCallOpening = thoughtCallOpening;

  final bool unescapes;
  final bool trimsLeading;
  final int Function(String text, int from)? _forcedThoughtOpening;
  final int Function(String text, int from)? _thoughtCallOpening;
  var _sealed = false;
  var _pending = '';
  var _started = false;
  var _separate = false;
  var _heldAtOpening = false;
  bool _inForcedThought;

  /// Treats the current thought as opened by a start tag.
  void leaveForcedThought() {
    _inForcedThought = false;
  }

  /// Adds [reasoning] of the current thought and returns the released text.
  String add(String reasoning) {
    if (_sealed) {
      return '';
    }
    _pending += reasoning;
    final opening =
        _thoughtCallOpening ??
        (_inForcedThought ? _forcedThoughtOpening : null);
    final openingAt = opening == null ? _pending.length : opening(_pending, 0);
    _heldAtOpening = openingAt < _pending.length;
    final head = _pending.substring(0, openingAt);
    final hold = unescapes && head.endsWith(r'\') ? 1 : 0;
    final text = _unescape(head.substring(0, head.length - hold));
    var end = text.length;
    while (end > 0 && _isTrimmed(text.codeUnitAt(end - 1))) {
      end--;
    }
    _pending =
        text.substring(end) +
        head.substring(head.length - hold) +
        _pending.substring(openingAt);
    return _release(text.substring(0, end));
  }

  /// Ends the current thought and returns the released text.
  String end() {
    if (_sealed || (_thoughtCallOpening != null && _heldAtOpening)) {
      _sealed = true;
      _pending = '';
      return '';
    }
    final released = _release(_unescape(_pending).trimRight());
    _pending = '';
    _separate = _separate || _started || _inForcedThought;
    _started = false;
    _inForcedThought = false;
    _heldAtOpening = false;
    return released;
  }

  /// Adds the last [reasoning] of the stream and returns the released text.
  ///
  /// A forced-open thought held at a tool-call opening stays held.
  String finish(String reasoning) {
    final released = add(reasoning);
    return _heldAtOpening ? released : released + end();
  }

  String _release(String text) {
    if (!_started) {
      if (trimsLeading) {
        text = text.trimLeft();
      }
      if (text.isEmpty) {
        return '';
      }
      _started = true;
      if (_separate) {
        _separate = false;
        return '\n$text';
      }
    }
    return text;
  }

  String _unescape(String text) =>
      unescapes ? text.replaceAll(r'\n', '\n').replaceAll(r'\r', '\r') : text;

  static bool _isTrimmed(int codeUnit) =>
      String.fromCharCode(codeUnit).trim().isEmpty;
}
