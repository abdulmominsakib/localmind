// Generates `lib/src/backends/litert_lm/litert_lm_chat_templates.dart` from the
// canonical jinja sources committed under `tool/litert_lm_templates/`.
//
// LiteRT-LM `.litertlm` bundles can't expose their chat template through the
// native FFI, so the backend supplies one itself keyed by model family. The
// jinja sources here are copied verbatim from the templates llama.cpp ships
// (so they stay in lockstep with the llama.cpp backend's rendering/parsing),
// and this tool embeds them as Dart consts.
//
// To add a model family:
//   1. Copy its canonical jinja into `tool/litert_lm_templates/<id>.jinja`.
//   2. Add an `_Entry` to `_manifest` below (id, family substrings, bos/eos).
//   3. Run: dart run tool/gen_litert_lm_templates.dart
//
// See `doc/litert_lm_templates.md`.

import 'dart:io';

class _Entry {
  const _Entry({
    required this.id,
    required this.jinja,
    required this.familyMatches,
    this.bosToken = '<bos>',
    this.eosToken = '<turn|>',
    this.thinkingStartTag = '<|channel>thought\n',
    this.thinkingEndTag = '<channel|>',
    this.stripLeadingBosToken = false,
  });

  final String id;
  final String jinja;
  final List<String> familyMatches;
  final String bosToken;
  final String eosToken;
  final String thinkingStartTag;
  final String thinkingEndTag;

  /// Drops a standalone `{{- bos_token -}}` line: the native LiteRT-LM runtime
  /// adds the start token, so emitting one in the template would double it.
  final bool stripLeadingBosToken;
}

// Order matters: the registry matches top-to-bottom and the first hit wins, so
// more specific families must precede broader ones (gemma-4 and gemma-3n before
// gemma-3). See `doc/litert_lm_templates.md`.
const List<_Entry> _manifest = [
  _Entry(
    id: 'gemma4',
    jinja: 'gemma4.jinja',
    familyMatches: ['gemma-4', 'gemma4'],
    bosToken: '<bos>',
    eosToken: '<turn|>',
    stripLeadingBosToken: true,
  ),
  _Entry(
    id: 'gemma3n',
    jinja: 'gemma3n.jinja',
    familyMatches: ['gemma-3n', 'gemma3n'],
    bosToken: '<bos>',
    eosToken: '<end_of_turn>',
    stripLeadingBosToken: true,
  ),
  _Entry(
    id: 'gemma',
    jinja: 'gemma.jinja',
    familyMatches: ['gemma-3', 'gemma3', 'gemma-2', 'gemma2'],
    bosToken: '<bos>',
    eosToken: '<end_of_turn>',
    stripLeadingBosToken: true,
  ),
  _Entry(
    id: 'qwen3',
    jinja: 'qwen3.jinja',
    familyMatches: ['qwen3', 'qwen-3'],
    bosToken: '',
    eosToken: '<|im_end|>',
    thinkingStartTag: '<think>',
    thinkingEndTag: '</think>',
  ),
  _Entry(
    id: 'qwen25',
    jinja: 'qwen25.jinja',
    // Version-specific only: a bare `qwen` would greedily mis-route
    // qwen-derived models that need a different handler (e.g.
    // DeepSeek-R1-Distill-Qwen) to the Qwen 2.5 template.
    familyMatches: ['qwen2.5', 'qwen-2.5', 'qwen2'],
    bosToken: '',
    eosToken: '<|im_end|>',
    thinkingStartTag: '<think>',
    thinkingEndTag: '</think>',
  ),
];

void main() {
  final scriptDir = File.fromUri(Platform.script).parent;
  final repoRoot = scriptDir.parent;
  final sourceDir = Directory('${scriptDir.path}/litert_lm_templates');
  final outputFile = File(
    '${repoRoot.path}/lib/src/backends/litert_lm/litert_lm_chat_templates.dart',
  );

  final buffer = StringBuffer()
    ..writeln('// coverage:ignore-file')
    ..writeln('// GENERATED FILE — DO NOT EDIT BY HAND.')
    ..writeln('//')
    ..writeln('// Regenerate with: dart run tool/gen_litert_lm_templates.dart')
    ..writeln('// Source jinja lives under tool/litert_lm_templates/.')
    ..writeln()
    ..writeln("import 'litert_lm_chat_template.dart';")
    ..writeln();

  final entries = <String>[];
  for (final entry in _manifest) {
    final source = File('${sourceDir.path}/${entry.jinja}');
    if (!source.existsSync()) {
      stderr.writeln('Missing jinja source: ${source.path}');
      exitCode = 66;
      return;
    }
    var template = source.readAsStringSync();
    if (entry.stripLeadingBosToken) {
      template = _stripBosToken(template);
    }
    if (template.contains("'''")) {
      stderr.writeln(
        "Template '${entry.id}' contains a triple-quote and cannot be "
        'embedded as a raw string. Add escaping support to the generator.',
      );
      exitCode = 65;
      return;
    }

    final constName = '_${entry.id}ChatTemplate';
    buffer
      ..writeln('/// Canonical chat template for the ${entry.id} family.')
      ..writeln("const String $constName = r'''")
      ..write(template)
      ..writeln("''';")
      ..writeln();

    entries.add(
      '  LiteRtLmChatTemplate(\n'
      "    id: '${entry.id}',\n"
      '    template: $constName,\n'
      '    familyMatches: ${_dartStringList(entry.familyMatches)},\n'
      "    bosToken: '${entry.bosToken}',\n"
      "    eosToken: '${entry.eosToken}',\n"
      "    thinkingStartTag: ${_dartStringLiteral(entry.thinkingStartTag)},\n"
      "    thinkingEndTag: ${_dartStringLiteral(entry.thinkingEndTag)},\n"
      '  ),',
    );
  }

  buffer
    ..writeln('/// Built-in LiteRT-LM chat templates, matched in order.')
    ..writeln('///')
    ..writeln(
      '/// The first entry whose [LiteRtLmChatTemplate.matches] returns',
    )
    ..writeln(
      '/// true for the bundle filename wins, so more specific families',
    )
    ..writeln('/// must precede broader ones.')
    ..writeln('const List<LiteRtLmChatTemplate> kLiteRtLmChatTemplates = [')
    ..writeln(entries.join('\n'))
    ..writeln('];');

  outputFile.writeAsStringSync(buffer.toString());
  stdout.writeln('Wrote ${outputFile.path} (${_manifest.length} templates).');
}

/// Removes the first `bos_token` output expression in any whitespace-control
/// form (`{{ bos_token }}`, `{{- bos_token -}}`, …). If the expression was on
/// its own line, the now-empty line is dropped; an inline remainder is kept.
String _stripBosToken(String template) {
  final bos = RegExp(r'\{\{-?\s*bos_token\s*-?\}\}');
  final lines = template.split('\n');
  final out = <String>[];
  var stripped = false;
  for (final line in lines) {
    if (!stripped && bos.hasMatch(line)) {
      stripped = true;
      final remainder = line.replaceFirst(bos, '');
      if (remainder.trim().isEmpty) {
        continue;
      }
      out.add(remainder);
      continue;
    }
    out.add(line);
  }
  return out.join('\n');
}

String _dartStringList(List<String> values) {
  final items = values.map((v) => "'$v'").join(', ');
  return '[$items]';
}

String _dartStringLiteral(String value) {
  final escaped = value
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll("'", r"\'");
  return "'$escaped'";
}
