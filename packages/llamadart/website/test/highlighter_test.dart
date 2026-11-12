import 'dart:io';

import 'package:llamadart_website/src/highlight/highlighter.dart';
import 'package:test/test.dart';

Future<List<String>> kinds(String source, String language, String kind) async =>
    [
      for (final token in await highlight(source, language))
        if (token.kind == kind) token.text,
    ];

void main() {
  test('every fenced block in every docs version round-trips', () async {
    final fence = RegExp(r'^```(\w*)[^\n]*\n([\s\S]*?)^```', multiLine: true);
    var blocks = 0;
    for (final dir in [Directory('docs'), Directory('versioned_docs')]) {
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.md')) continue;
        for (final match in fence.allMatches(file.readAsStringSync())) {
          final source = match[2]!;
          final tokens = await highlight(source, match[1]);
          expect(tokens.map((t) => t.text).join(), source, reason: file.path);
          blocks++;
        }
      }
    }
    expect(blocks, greaterThan(1000));
  });

  test(
    'bash: comments only after whitespace, commands, flags, variables',
    () async {
      const source =
          'dart run tool/x.dart --flag # note\necho "a#b" \$HOME | grep x';
      expect(await kinds(source, 'bash', 'comment'), ['# note']);
      expect(await kinds(source, 'bash', 'function'), ['dart', 'echo', 'grep']);
      expect(await kinds(source, 'bash', 'attribute'), ['--flag']);
      expect(await kinds(source, 'bash', 'variable'), [r'$HOME']);
      expect(await kinds(source, 'sh', 'string'), ['"a#b"']);
    },
  );

  test('yaml: keys, comments and scalars', () async {
    const source =
        'hooks:\n  user_defines:\n    - tag: "v0.5.0" # pin\n    on: true\n';
    expect(await kinds(source, 'yaml', 'key'), [
      'hooks',
      'user_defines',
      'tag',
      'on',
    ]);
    expect(await kinds(source, 'yml', 'comment'), ['# pin']);
    expect(await kinds(source, 'yaml', 'literal'), ['true']);
  });

  test('dart uses the TextMate grammar', () async {
    const source = "// hi\nfinal x = 'a';";
    expect(await kinds(source, 'dart', 'comment'), ['// hi']);
    expect(await kinds(source, 'dart', 'keyword'), ['final']);
    expect(await kinds(source, 'dart', 'string'), ["'a'"]);
  });

  test('unknown and missing languages render as one plain token', () async {
    for (final language in [null, 'text', 'mermaid-like']) {
      final tokens = await highlight('a <b> c', language);
      expect(tokens.single.kind, isNull);
    }
  });
}
