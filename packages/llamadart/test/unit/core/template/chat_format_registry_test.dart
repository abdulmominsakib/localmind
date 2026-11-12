@TestOn('vm')
library;

import 'dart:io';
import 'dart:mirrors';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/template/chat_format.dart';
import 'package:llamadart/src/core/template/chat_format_registry.dart';
import 'package:test/test.dart';

import '../../../support/chat_format_policy_scan.dart';
import '../../../support/raw_tool_schema_fixture.dart';

void main() {
  test('registers every ChatFormat exactly once', () {
    final registered = chatFormatRegistrations.map((r) => r.format).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    expect(registered, ChatFormat.values);
  });

  test('leaves only engine-selected formats without a detector', () {
    expect(
      chatFormatRegistrations
          .where((registration) => registration.detect == null)
          .map((registration) => registration.format)
          .toSet(),
      {
        ChatFormat.contentOnly,
        ChatFormat.generic,
        ChatFormat.llama3BuiltinTools,
        ChatFormat.pegSimple,
        ChatFormat.pegNative,
        ChatFormat.pegConstructed,
      },
    );
  });

  test('each handler reports the format it is registered for', () {
    for (final registration in chatFormatRegistrations) {
      final expected = registration.format == ChatFormat.llama3BuiltinTools
          ? ChatFormat.llama3
          : registration.format;
      expect(
        registration.createHandler().format,
        expected,
        reason: registration.format.name,
      );
    }
  });

  test('every concrete handler class in handlers/ is registered', () {
    final declared = <String>{
      for (final file in Directory(
        'lib/src/core/template/handlers',
      ).listSync().whereType<File>())
        for (final match in RegExp(
          r'^class ([A-Z]\w*Handler) extends',
          multiLine: true,
        ).allMatches(file.readAsStringSync()))
          match.group(1)!,
    };
    final registered = {
      for (final registration in chatFormatRegistrations)
        registration.createHandler().runtimeType.toString(),
    };
    expect(declared, isNotEmpty);
    expect(declared.difference(registered), isEmpty);
  });

  test('handlerFor caches the registered handler', () {
    for (final format in ChatFormat.values) {
      final handler = ChatTemplateEngine.handlerFor(format);
      expect(
        handler.runtimeType,
        chatFormatRegistration(format).createHandler().runtimeType,
        reason: format.name,
      );
      expect(ChatTemplateEngine.handlerFor(format), same(handler));
    }
  });

  test(
    'format tables live only in the registry or exact reviewed dispatch',
    () {
      final used = <(String, String)>{};
      for (final file in chatFormatPolicySources(Directory.current)) {
        final path = chatFormatPolicyPath(Directory.current, file);
        for (final table in chatFormatPolicyTables(file.readAsStringSync())) {
          final key = (path, table.code);
          expect(
            _policyExceptions.containsKey(key),
            isTrue,
            reason: '$path: $table',
          );
          expect(
            used.add(key),
            isTrue,
            reason: 'Duplicate exception use: $key',
          );
        }
      }
      expect(used, _policyExceptions.keys.toSet(), reason: 'Stale exceptions');
    },
  );

  test('the table scan finds each kind of format table', () {
    expect(_formatTables('const Set<ChatFormat> lazy = {};'), isNotEmpty);
    expect(_formatTables('const generic = {ChatFormat.gemma};'), isNotEmpty);
    expect(
      _formatTables(
        'const supported = {ChatFormat.generic, ChatFormat.hermes};',
      ),
      isNotEmpty,
    );
    expect(
      _formatTables(
        'final result = switch (format) { ChatFormat.hermes => true, _ => false };',
      ),
      isNotEmpty,
    );
    expect(
      _formatTables(
        'const byFormat = {ChatFormat.gemma: 1, ChatFormat.lfm2: 2};',
      ),
      isNotEmpty,
    );
    expect(
      _formatTables('switch (format) { case ChatFormat.hermes: return true; }'),
      isNotEmpty,
    );
    expect(
      _formatTables(
        'final chosen = pegOnly ? ChatFormat.hermes : ChatFormat.generic;',
      ),
      isEmpty,
    );
    expect(
      _formatTables(
        'f == ChatFormat.gemma.index || f == ChatFormat.lfm2.index || '
        'f == ChatFormat.kimiK2.index;',
      ),
      isNotEmpty,
    );
    expect(
      _formatTables(
        'final isLlama3 = f == ChatFormat.llama3.index || '
        'f == ChatFormat.llama3BuiltinTools.index;',
      ),
      isNotEmpty,
    );
  });

  for (final (name, source) in const [
    ('guarded case', 'switch (f) { case ChatFormat.gemma when ok: break; }'),
    (
      'or case',
      'switch (f) { case ChatFormat.gemma || ChatFormat.lfm2: break; }',
    ),
    (
      'guarded arm',
      'final x = switch (f) { ChatFormat.gemma when ok => 1, _ => 0 };',
    ),
    (
      'or arm',
      'final x = switch (f) { ChatFormat.gemma || ChatFormat.lfm2 => 1, _ => 0 };',
    ),
    ('commented key', 'const table = {/* policy */ ChatFormat.gemma: 1};'),
    ('index key', 'const table = {ChatFormat.gemma.index: 1};'),
    (
      'commented index key',
      'const table = {/* policy */ ChatFormat.gemma.index: 1};',
    ),
    (
      'two-format helper',
      'final x = f == ChatFormat.gemma || f == ChatFormat.lfm2;',
    ),
  ]) {
    test('new production files cannot hide a $name policy table', () {
      final root = Directory.systemTemp.createTempSync('format-policy-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/lib/new_consumer/policy.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void probe() { $source }');
      final sources = chatFormatPolicySources(root).toList();
      expect(
        sources.map((source) => chatFormatPolicyPath(root, source)),
        contains('lib/new_consumer/policy.dart'),
      );
      expect(
        chatFormatPolicyTables(sources.single.readAsStringSync()),
        isNotEmpty,
      );
    });
  }

  test('the scan ignores comments, strings, identity checks and dispatch', () {
    expect(
      chatFormatPolicyTables('ChatFormat get format => ChatFormat.gemma;'),
      isEmpty,
    );
    for (final source in const [
      '// const table = {ChatFormat.gemma: 1};',
      '/* case ChatFormat.gemma when ok: */',
      r"const text = 'case ChatFormat.gemma || ChatFormat.lfm2:';",
      r"const text = '{ChatFormat.gemma.index: 1}';",
      'final same = f == ChatFormat.gemma;',
      'final same = f == ChatFormat.gemma || f == ChatFormat.gemma;',
      'final chosen = ok ? ChatFormat.gemma : ChatFormat.generic;',
      'switch (event) { case Event.start: handle(ChatFormat.gemma); break; }',
    ]) {
      expect(_formatTables(source), isEmpty, reason: source);
    }
  });

  test('the registry is the only excluded production source', () {
    final root = Directory.systemTemp.createTempSync('format-inventory-');
    addTearDown(() => root.deleteSync(recursive: true));
    for (final path in const [
      'lib/src/core/template/chat_format_registry.dart',
      'lib/src/core/template/handlers/new_handler.dart',
      'lib/src/new_consumer.dart',
    ]) {
      File('${root.path}/$path').createSync(recursive: true);
    }
    expect(
      chatFormatPolicySources(
        root,
      ).map((file) => chatFormatPolicyPath(root, file)).toSet(),
      {
        'lib/src/core/template/handlers/new_handler.dart',
        'lib/src/new_consumer.dart',
      },
    );
  });

  test('policy exceptions reject edited and copied expressions', () {
    for (final entry in _policyExceptions.entries) {
      final (path, code) = entry.key;
      expect(entry.value, isNotEmpty);
      expect(chatFormatPolicyTables('final result = $code;').single.code, code);
      expect(
        _policyExceptions.containsKey(('lib/new_consumer.dart', code)),
        isFalse,
      );
      final edited = code.replaceFirst(
        RegExp(r'ChatFormat\.\w+'),
        'ChatFormat.apertus',
      );
      final table = chatFormatPolicyTables('final result = $edited;').single;
      expect(
        _policyExceptions.containsKey((path, table.code)),
        isFalse,
        reason: '$path must re-review changed format membership',
      );
    }
  });

  test('generic reads an incomplete call outside a forced-open thinking '
      'block only', () {
    final leavesIncomplete = chatFormatRegistration(
      ChatFormat.generic,
    ).traits.leavesIncompleteToolCall!;
    const call = '{"tool_calls": [{"name": "f"';
    const parsed = ChatParseResult();

    expect(leavesIncomplete(parsed, call, thinkingForcedOpen: false), isTrue);
    expect(leavesIncomplete(parsed, call, thinkingForcedOpen: true), isFalse);
    expect(
      leavesIncomplete(parsed, 'plan</think>$call', thinkingForcedOpen: true),
      isTrue,
    );
  });

  test('only Hermes renders tool-result content', () {
    expect(
      [
        for (final registration in chatFormatRegistrations)
          if (registration.traits.rendersToolResultContent) registration.format,
      ],
      [ChatFormat.hermes],
    );
  });

  test('an incomplete-call callback does not grant schema admission', () {
    final originalCheck = chatFormatRegistration(
      ChatFormat.hermes,
    ).traits.leavesIncompleteToolCall!;
    var checks = 0;
    bool check(
      ChatParseResult result,
      String output, {
      required bool thinkingForcedOpen,
    }) {
      checks++;
      return originalCheck(
        result,
        output,
        thinkingForcedOpen: thinkingForcedOpen,
      );
    }

    _withHermesTraits(
      ChatFormatTraits(
        qualifiesJsonSchemaTools: false,
        leavesIncompleteToolCall: check,
      ),
      () {
        expect(_renderSchemaTool, throwsA(isA<LlamaUnsupportedException>()));
        expect(checks, 0);
        expect(
          _parseIncompleteSchemaCall,
          throwsA(isA<LlamaInferenceException>()),
        );
        expect(checks, 1);
      },
    );
  });

  test('schema admission does not install an incomplete-call callback', () {
    _withHermesTraits(
      const ChatFormatTraits(qualifiesJsonSchemaTools: true),
      () {
        final rendered = _renderSchemaTool();
        expect(rendered.format, ChatFormat.hermes.index);
        expect(rendered.grammar, isNotEmpty);
        final parsed = _parseIncompleteSchemaCall();
        expect(parsed.toolCalls, isEmpty);
        expect(parsed.content, contains('<tool_call>'));
      },
    );
  });

  test('detection falls back to content-only', () {
    expect(detectChatFormat(null), ChatFormat.contentOnly);
    expect(detectChatFormat(''), ChatFormat.contentOnly);
    expect(detectChatFormat('{{ messages }}'), ChatFormat.contentOnly);
  });
}

LlamaChatTemplateResult _renderSchemaTool() => ChatTemplateEngine.render(
  templateSource: '<tool_call>',
  messages: [
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Inspect'),
  ],
  metadata: const {},
  tools: [rawSchemaTool()],
);

ChatParseResult _parseIncompleteSchemaCall() => ChatTemplateEngine.parse(
  ChatFormat.hermes.index,
  '<tool_call>{"name":"inspect"',
  tools: [rawSchemaTool()],
);

/// Exercise independent traits through production consumers without a runtime
/// registration API. Restore the private registry even when an assertion fails.
void _withHermesTraits(ChatFormatTraits traits, void Function() body) {
  final library = reflectClass(ChatFormatTraits).owner as LibraryMirror;
  final registrations =
      library
              .getField(
                MirrorSystem.getSymbol('_registrationsByFormat', library),
              )
              .reflectee
          as Map<ChatFormat, ChatFormatRegistration>;
  final original = registrations[ChatFormat.hermes]!;
  registrations[ChatFormat.hermes] = ChatFormatRegistration(
    original.format,
    original.createHandler,
    detect: original.detect,
    traits: traits,
  );
  try {
    body();
  } finally {
    registrations[ChatFormat.hermes] = original;
  }
}

// Keep the original small source controls usable as function-body fragments.
List<ChatFormatPolicyTable> _formatTables(String source) =>
    chatFormatPolicyTables('void probe() {\n$source;\n}');

// #1666 chooses exact, reviewable exceptions rather than changing production
// routing during release qualification. A changed or copied expression needs
// review again; the production test also rejects unused exceptions. Handler
// format getters and other single-format identity/dispatch need no exemption.
final Map<(String, String), String> _policyExceptions = {
  _exception(
    _engine,
    'resultFormat == ChatFormat.generic || resultFormat == ChatFormat.contentOnly',
  ): 'Only the two fallback routes generate generic tool grammar; handlers own their grammar.',
  _exception(
    _stream,
    'isFunctionaryV32 || templateResult.format == ChatFormat.minimaxM1.index || templateResult.format == ChatFormat.museGlimmer.index',
  ): 'These partial parsers preserve thought tags as content when tool parsing is disabled.',
  _exception(
    _stream,
    'templateResult.format == ChatFormat.llama3.index || templateResult.format == ChatFormat.llama3BuiltinTools.index',
  ): 'Both Llama3 wire formats use typed tool envelopes, with different opening gates.',
  _exception(
    _stream,
    'templateResult.format == ChatFormat.cohere2Moe.index || templateResult.format == ChatFormat.commandR7B.index',
  ): 'Text-only streams strip the shared Command R response markers.',
  _exception(
    _stream,
    '!parseToolCallsEnabled && !traits.hasRepeatedContentChannels && !traits.endsThoughtAtToolCallOpening && templateResult.format != ChatFormat.gemma4.index && templateResult.format != ChatFormat.kimiK3.index',
  ): 'Gemma4 and KimiK3 channel frames require their parser even with tools disabled.',
  _exception(
    _stream,
    'toolCallOpening == null && templateResult.format != ChatFormat.gemma4.index && templateResult.format != ChatFormat.minimaxM1.index && !traits.retainsTextAroundToolCalls && parsed.hasToolCalls && _isToolCallEnvelopeBuffer(fullOutput, startTag: startTag, endTag: endTag, thinkingForcedOpen: templateResult.thinkingForcedOpen, exactReplyStart: exactReplyStart, thinkingTagsAreContent: verbatimForcedThought)',
  ): 'These two parsers own envelope handling; the shared fallback must not reinterpret it.',
  _exception(
    _peg,
    'switch (format) { ChatFormat.pegSimple => ChatFormat.pegSimple, ChatFormat.pegNative => ChatFormat.pegNative, ChatFormat.pegConstructed => ChatFormat.pegConstructed, ChatFormat.ministral => hasPegParser ? ChatFormat.pegNative : null, ChatFormat.solarOpen => hasPegParser ? ChatFormat.pegNative : null, ChatFormat.qwen3CoderXml => hasPegParser ? ChatFormat.pegConstructed : null, _ => null }',
  ): 'Selects serialized PEG parser variants, including artifact-dependent handler dispatch.',
  _exception(
    _peg,
    "switch (format) { ChatFormat.pegSimple => 'peg-simple', ChatFormat.pegNative => 'peg-native', ChatFormat.pegConstructed => 'peg-constructed', _ => format.name }",
  ): 'Preserves upstream diagnostic wire spellings, including historical peg-constructed.',
  _exception(
    _peg,
    'switch (format) { ChatFormat.pegNative => _PegNativeMapper(message, accumulateContent: accumulateContent), ChatFormat.pegConstructed => _PegConstructedMapper(message), _ => _PegBaseMapper(message) }',
  ): 'Dispatches serialized PEG ASTs to their concrete mapper implementations.',
};

const _engine = 'lib/src/core/template/chat_template_engine.dart';
const _stream = 'lib/src/core/engine/chat_completion_stream_parser.dart';
const _peg = 'lib/src/core/template/peg_chat_parser.dart';

(String, String) _exception(String path, String expression) =>
    (path, chatFormatPolicyExpression(expression));
