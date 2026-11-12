import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../api/media_model.dart';
import '../../api/media_resolver.dart';
import '../../core/runtime/media_queue.dart';
import 'content_usage.dart';
import 'converters/remote_media.dart';
import 'media/audio_file_stub.dart'
    if (dart.library.io) 'media/audio_file_io.dart';
import 'media/media_config.dart';

/// Dedicated batch speech and image models for standard Genkit generation.
///
/// Register loaded typed engines through [LlamaDartMediaModel] definitions. The chat plugin may
/// coexist with this plugin; model refs use the separate `llamadart-media` name.
/// All media operations are serialized in this plugin, including file reads and
/// capability checks. Direct use or registration of the same engine elsewhere
/// can conflict with this queue. Image runtimes also enforce a process-wide slot.
///
/// Native only for this preview. `generateStream` emits progress in chunk
/// `custom.llamadartProgress`, followed by complete, validated content. It never
/// promises partial transcripts, incremental audio or partially decoded images.
class LlamaDartMediaPlugin extends genkit.GenkitPlugin {
  /// Registers [models] without loading or probing their engines.
  ///
  /// Model names and engine instances must be unique. Ownership defaults to
  /// borrowed; set a definition's `ownsEngine` to transfer disposal to the plugin.
  /// [mediaResolver] optionally resolves HTTP(S) audio using caller-owned policy
  /// and transport. Local files and data URLs work without a resolver.
  LlamaDartMediaPlugin({
    required Iterable<LlamaDartMediaModel> models,
    this.mediaResolver,
  }) : _models = List<LlamaDartMediaModel>.unmodifiable(models) {
    final names = <String>{};
    final engines = Set<Object>.identity();
    for (final model in _models) {
      if (!names.add(model.name) || !engines.add(_engine(model))) {
        throw ArgumentError('Media model names and engines must be unique.');
      }
    }
  }

  /// Optional application-owned HTTP(S) audio resolver; never disposed here.
  final LlamaDartMediaResolver? mediaResolver;
  final List<LlamaDartMediaModel> _models;
  final MediaQueue _queue = MediaQueue();
  List<genkit.Action>? _actions;

  /// Plugin namespace used by [modelRef].
  @override
  String get name => 'llamadart-media';

  /// References a registered batch model with its documented configuration map.
  ///
  /// Speech recognition accepts `contextPrompt`, `languageHint` (when supported)
  /// and `maxOutputTokens`. Synthesis accepts `language`, `maxFrames`,
  /// `promptBatchSize`, `topK`, `topP`, `minP`, `temperature` and `seed`.
  /// Image generation accepts `negativePrompt`, `width`, `height`, `steps`,
  /// `guidanceScale`, `seed`, `count`, `sampler`, `scheduler` and `flowShift`.
  /// Unknown options and invalid values fail with `INVALID_ARGUMENT`.
  static genkit.ModelRef<Map<String, dynamic>> modelRef(String name) =>
      genkit.modelRef<Map<String, dynamic>>('llamadart-media/$name');

  /// Registers model actions without inspecting or loading engines.
  @override
  Future<List<genkit.Action>> init() async => _actions ??= [
    for (final definition in _models)
      genkit.Model<Map<String, dynamic>>(
        name: 'llamadart-media/${definition.name}',
        metadata: {
          'model': {
            'label': definition.name,
            'stage': 'experimental',
            'customOptions': mediaConfigSchema(definition),
            'supports': {
              'multiturn': false,
              'systemRole': false,
              'tools': false,
              'toolChoice': false,
              'constrained': false,
              'media': definition is! LlamaDartImageModel,
            },
          },
        },
        fn: (request, context) => _queue.run(() async {
          final elapsed = Stopwatch()..start();
          try {
            context.cancel?.throwIfCancelled();
            if (!const bool.fromEnvironment('dart.library.io')) {
              throw genkit.GenkitException(
                'Dedicated media models currently require a native runtime.',
                status: genkit.StatusCode.unimplemented,
              );
            }
            _checkRequest(request);
            final config = await validateMediaConfig(
              definition,
              request.config,
            );
            final parts = await _run(definition, request, config, context);
            context.cancel?.throwIfCancelled();
            if (context.streamingRequested) {
              context.sendChunk(
                genkit.ModelResponseChunk(
                  role: genkit.Role.model,
                  content: parts,
                  aggregated: false,
                ),
              );
            }
            final response = genkit.ModelResponse(
              message: genkit.Message(role: genkit.Role.model, content: parts),
              finishReason: genkit.FinishReason.stop,
              latencyMs: elapsed.elapsedMicroseconds / 1000,
            );
            final input = request.messages.single.content;
            recordContentUsage(
              response,
              inputCharacters: definition is LlamaDartSpeechToTextModel
                  ? 0
                  : _text(input).length,
              inputAudioFiles: input.where((part) => part.isMedia).length,
            );
            return response;
          } catch (error) {
            context.cancel?.throwIfCancelled();
            if (error is genkit.GenkitException) rethrow;
            throw genkit.GenkitException(
              'Media inference failed. Check the loaded model, native runtime, input format and resource limits.',
              status: error is llama.LlamaUnsupportedException
                  ? genkit.StatusCode.unimplemented
                  : error is llama.LlamaArgumentException ||
                        error is llama.LlamaAudioFormatException ||
                        error is llama.LlamaTextToSpeechException ||
                        error is FormatException
                  ? genkit.StatusCode.invalidArgument
                  : genkit.StatusCode.internal,
            );
          }
        }),
      ),
  ];

  /// Lists the same action contracts as [init], without probing model support.
  ///
  /// Live capabilities are checked before every operation. Listed media support
  /// describes accepted input shapes, not readiness of the borrowed engine.
  @override
  Future<List<genkit.ActionMetadata>> list() async => [
    for (final action in await init())
      genkit.ActionMetadata(
        name: action.name,
        actionType: genkit.ActionType.model,
        description: action.name,
        metadata: action.metadata,
      ),
  ];

  /// Drains accepted requests, then disposes every explicitly owned engine.
  ///
  /// Disposal is terminal and idempotent. Borrowed engines and the HTTP resolver
  /// remain caller-owned. Cancellation belongs to each request's Genkit token;
  /// disposal does not interrupt accepted work. Multiple disposal failures are
  /// retained in a `ParallelWaitError` after all owned engines are attempted.
  Future<void> dispose() => _queue.dispose(() async {
    await [
      for (final model in _models)
        if (model.ownsEngine) _disposeEngine(model),
    ].wait;
  });

  Future<List<genkit.Part>> _run(
    LlamaDartMediaModel model,
    genkit.ModelRequest request,
    Map<String, dynamic> config,
    _Context context,
  ) async {
    switch (model) {
      case LlamaDartSpeechToTextModel():
        final capabilities = await model.engine.capabilities;
        _require(capabilities.isSupported, 'speech recognition');
        _require(capabilities.supportsCancellation, 'speech cancellation');
        _require(
          capabilities.inputKinds.contains(
            llama.SpeechAudioInputKind.encodedBytes,
          ),
          'encoded audio',
        );
        if (config['languageHint'] != null) {
          _require(capabilities.supportsLanguageHints, 'language hints');
        }
        final parts = request.messages.single.content;
        if (parts.length != 1 || !parts.single.isMedia) {
          throw _invalid(
            'Transcription requires exactly one audio media part.',
          );
        }
        final audio = await _audio(
          parts.single.mediaPart!.media,
          model,
          context,
        );
        context.cancel?.throwIfCancelled();
        final task = await model.engine.transcribe(
          llama.SpeechToTextRequest(
            audio: audio,
            contextPrompt: config['contextPrompt'] as String?,
            languageHint: config['languageHint'] as String?,
            maxOutputTokens: config['maxOutputTokens'] as int? ?? 1024,
          ),
        );
        final result = await _finish(
          task.result,
          task.events,
          task.cancel,
          context,
        );
        if (utf8.encode(result.text).length > model.maxOutputBytes) {
          throw _invalid('Transcript exceeds the output byte limit.');
        }
        return [genkit.TextPart(text: result.text)];
      case LlamaDartTextToSpeechModel():
        final capabilities = await model.engine.capabilities;
        _require(capabilities.isSupported, 'speech synthesis');
        _require(capabilities.supportsCancellation, 'speech cancellation');
        if (config['language'] != null) {
          _require(capabilities.supportsLanguage, 'language selection');
        }
        final parts = request.messages.single.content;
        final media = parts.where((part) => part.isMedia).toList();
        if (media.length > 1 ||
            parts.any((part) => !part.isText && !part.isMedia)) {
          throw _invalid(
            'Synthesis accepts text and at most one reference audio part.',
          );
        }
        final text = _text(parts);
        llama.SpeechAudioBytesInput? reference;
        if (media.isNotEmpty) {
          _require(
            capabilities.supportsSpeakerReference &&
                capabilities.speakerReferenceInputKinds.contains(
                  llama.SpeechAudioInputKind.encodedBytes,
                ),
            'encoded speaker reference audio',
          );
          reference = await _audio(
            media.single.mediaPart!.media,
            model,
            context,
          );
        }
        context.cancel?.throwIfCancelled();
        final task = await model.engine.synthesize(
          llama.TextToSpeechRequest(
            text: text,
            language: config['language'] as String?,
            speakerReference: reference,
            maxFrames: config['maxFrames'] as int? ?? 512,
            promptBatchSize: config['promptBatchSize'] as int? ?? 512,
            topK: config['topK'] as int? ?? 40,
            topP: (config['topP'] as num?)?.toDouble() ?? 0.95,
            minP: (config['minP'] as num?)?.toDouble() ?? 0,
            temperature: (config['temperature'] as num?)?.toDouble() ?? 0.8,
            seed: config['seed'] as int? ?? 0xffffffff,
          ),
        );
        final result = await _finish(
          task.result,
          task.events,
          task.cancel,
          context,
        );
        if (result.truncated) {
          throw _invalid(
            'Speech synthesis reached maxFrames; increase the limit or shorten the text.',
          );
        }
        if (result.sampleRateHz <= 0 ||
            result.channelCount <= 0 ||
            result.samples.isEmpty ||
            result.samples.length % result.channelCount != 0 ||
            result.samples.any((sample) => !sample.isFinite)) {
          throw _invalid('Speech runtime returned invalid PCM audio.');
        }
        if (44 + result.samples.length * 2 > model.maxOutputBytes) {
          throw _invalid('Generated WAV exceeds the output byte limit.');
        }
        return [_media(result.toWavBytes(), 'audio/wav')];
      case LlamaDartImageModel():
        final capabilities = await model.engine.capabilities;
        _require(capabilities.isSupported, 'image generation');
        _require(capabilities.supportsCancellation, 'image cancellation');
        final parts = request.messages.single.content;
        if (parts.any((part) => !part.isText)) {
          throw _invalid('Image generation requires text parts only.');
        }
        final task = await model.engine.generate(
          llama.ImageGenerationRequest(
            prompt: _text(parts),
            negativePrompt: config['negativePrompt'] as String? ?? '',
            width: config['width'] as int?,
            height: config['height'] as int?,
            steps: config['steps'] as int?,
            guidanceScale: (config['guidanceScale'] as num?)?.toDouble(),
            seed: config['seed'] as int?,
            count: config['count'] as int? ?? 1,
            sampler: config['sampler'] == null
                ? null
                : llama.ImageGenerationSampler.values.byName(
                    config['sampler'] as String,
                  ),
            scheduler: config['scheduler'] == null
                ? null
                : llama.ImageGenerationScheduler.values.byName(
                    config['scheduler'] as String,
                  ),
            flowShift: (config['flowShift'] as num?)?.toDouble(),
          ),
        );
        final result = await _finish(
          task.result,
          task.events,
          task.cancel,
          context,
        );
        if (result.images.length != (config['count'] as int? ?? 1)) {
          throw _invalid('Image runtime returned an unexpected image count.');
        }
        var totalBytes = 0;
        final output = <genkit.Part>[];
        for (final image in result.images) {
          final bytes = image.toPng();
          totalBytes += bytes.length;
          if (totalBytes > model.maxOutputBytes) {
            throw _invalid(
              'Generated PNGs exceed the total output byte limit.',
            );
          }
          output.add(_media(bytes, 'image/png'));
        }
        return output;
    }
  }

  Future<llama.SpeechAudioBytesInput> _audio(
    genkit.Media media,
    LlamaDartMediaModel model,
    _Context context,
  ) async {
    if (media.url.startsWith('data:') &&
        media.url.length > model.maxInputBytes * 4 + 1024) {
      throw _invalid('Audio exceeds the encoded byte limit.');
    }
    final resolved = resolveLlamaMessages(
      [
        genkit.Message(
          role: genkit.Role.user,
          content: [genkit.MediaPart(media: media)],
        ),
      ],
      resolver: mediaResolver,
      cancel: context.cancel,
    );
    final messages = resolved is Future<List<llama.LlamaChatMessage>>
        ? await resolved
        : resolved;
    final part = messages.single.parts.single;
    if (part is! llama.LlamaAudioContent) {
      throw _invalid('An audio/* MIME type is required.');
    }
    final bytes =
        part.bytes ?? await readAudioFile(part.path!, model.maxInputBytes);
    context.cancel?.throwIfCancelled();
    if (bytes.isEmpty || bytes.length > model.maxInputBytes) {
      throw _invalid('Audio is empty or exceeds the encoded byte limit.');
    }
    return llama.SpeechAudioBytesInput(
      bytes,
      format: llama.SpeechAudioFormat(mimeType: media.contentType),
    );
  }
}

typedef _Context =
    genkit.ActionFnArg<genkit.ModelResponseChunk, genkit.ModelRequest, void>;

Future<T> _finish<T>(
  Future<T> result,
  Stream<Object> events,
  void Function() cancel,
  _Context context,
) async {
  var cancellationRequested = false;
  void cancelOnce() {
    if (!cancellationRequested) {
      cancellationRequested = true;
      cancel();
    }
  }

  final unregister = context.cancel?.onCancel(cancelOnce);
  final drained = events.map((event) {
    if (context.streamingRequested && !(context.cancel?.isCancelled ?? false)) {
      final progress = switch (event) {
        llama.TextToSpeechProgressEvent() => {
          'phase': event.phase.name,
          'framesGenerated': event.framesGenerated,
          'promptTokensRemaining': event.promptTokensRemaining,
        },
        llama.ImageGenerationProgressEvent() => {
          'phase': event.phase.name,
          'step': event.step,
          'steps': event.steps,
          'imageIndex': event.imageIndex,
          'imageCount': event.imageCount,
        },
        _ => null,
      };
      if (progress != null) {
        context.sendChunk(
          genkit.ModelResponseChunk(
            content: [],
            custom: {'llamadartProgress': progress},
          ),
        );
      }
    }
  }).drain<void>();
  try {
    if (context.cancel?.isCancelled ?? false) cancelOnce();
    return await result;
  } finally {
    try {
      await drained;
    } finally {
      unregister?.call();
    }
  }
}

void _checkRequest(genkit.ModelRequest request) {
  if (request.messages.length != 1 ||
      request.messages.single.role != genkit.Role.user ||
      (request.tools?.isNotEmpty ?? false) ||
      (request.docs?.isNotEmpty ?? false) ||
      request.toolChoice != null ||
      request.output?.schema != null ||
      request.output?.constrained == true ||
      request.output?.format == 'json') {
    throw _invalid(
      'Batch media models accept one user message without tools, docs or constrained JSON output.',
    );
  }
}

String _text(List<genkit.Part> parts) {
  final text = parts
      .where((part) => part.isText)
      .map((part) => part.textPart!.text)
      .join('\n');
  if (text.trim().isEmpty || text.length > 16384) {
    throw _invalid(
      'A nonempty text prompt of at most 16384 characters is required.',
    );
  }
  return text;
}

Object _engine(LlamaDartMediaModel model) => switch (model) {
  LlamaDartSpeechToTextModel() => model.engine,
  LlamaDartTextToSpeechModel() => model.engine,
  LlamaDartImageModel() => model.engine,
};

Future<void> _disposeEngine(LlamaDartMediaModel model) async => switch (model) {
  LlamaDartSpeechToTextModel() => model.engine.dispose(),
  LlamaDartTextToSpeechModel() => model.engine.dispose(),
  LlamaDartImageModel() => model.engine.dispose(),
};

genkit.MediaPart _media(Uint8List bytes, String type) => genkit.MediaPart(
  media: genkit.Media(
    url: 'data:$type;base64,${base64Encode(bytes)}',
    contentType: type,
  ),
);

void _require(bool supported, String feature) {
  if (!supported) {
    throw genkit.GenkitException(
      'The loaded native media model does not support $feature. Check the model, projector and runtime version.',
      status: genkit.StatusCode.unimplemented,
    );
  }
}

genkit.GenkitException _invalid(String message) =>
    genkit.GenkitException(message, status: genkit.StatusCode.invalidArgument);
