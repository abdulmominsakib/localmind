@TestOn('vm')
library;

import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

void main() {
  group('startup diagnostics', () {
    test('an empty buffer leaves the message unchanged', () {
      expect(formatStartupDiagnostics(const <String>[]), isEmpty);
    });

    test('entries are joined into a labelled suffix', () {
      expect(
        formatStartupDiagnostics(const <String>['first failed', 'then this']),
        ', startupDiagnostics=[first failed; then this]',
      );
    });

    test('truncation keeps the root cause and final outcome', () {
      final entries = <String>[
        'root cause',
        'a' * 100,
        '${startupTeardownDiagnosticPrefix}noise',
        'final outcome',
      ];

      expect(
        formatStartupDiagnostics(entries, maxLength: 40),
        ', startupDiagnostics=[root cause; ...; final outcome]',
      );
      expect(
        formatStartupDiagnostics(entries, maxLength: 60),
        ', startupDiagnostics=['
        'root cause; ...; ${startupTeardownDiagnosticPrefix}noise; '
        'final outcome]',
      );
    });

    test('truncation is bounded for every content limit', () {
      final entries = <String>[
        '${startupTeardownDiagnosticPrefix}early noise',
        'root cause ${'a' * 40}',
        'middle probe',
        'final outcome',
        '${startupTeardownDiagnosticPrefix}late noise',
      ];
      final untruncated = entries.join('; ');

      for (var maxLength = 1; maxLength <= untruncated.length; maxLength++) {
        final formatted = formatStartupDiagnostics(
          entries,
          maxLength: maxLength,
        );
        final content = formatted.substring(
          ', startupDiagnostics=['.length,
          formatted.length - 1,
        );
        final reason = 'maxLength=$maxLength';
        expect(content.length, lessThanOrEqualTo(maxLength), reason: reason);
        if (maxLength == untruncated.length) {
          expect(content, untruncated);
        } else if (maxLength >= 7) {
          expect(content, contains('root'), reason: reason);
          expect(content, contains('...'), reason: reason);
        }
      }
    });

    test('an oversized entry keeps its head within half the limit', () {
      final formatted = formatStartupDiagnostics(<String>[
        'oldest:${'a' * 100}',
        'newest failure',
      ], maxLength: 40);

      expect(
        formatted,
        ', startupDiagnostics=[oldest:${'a' * 10}...; newest failure]',
      );
    });

    test('two oversized causal entries both keep their heads', () {
      final buffer = StartupDiagnosticBuffer()
        ..record('ROOT:${'r' * 5000}')
        ..record('noise', category: StartupDiagnosticCategory.teardown)
        ..record('FINAL:${'f' * 5000}');

      final formatted = formatStartupDiagnostics(buffer.entries);

      expect(formatted, startsWith(', startupDiagnostics=[ROOT:rrr'));
      expect(formatted, contains('rrr...; ...; FINAL:fff'));
      expect(formatted, endsWith('fff...]'));
      expect(formatted, hasLength(', startupDiagnostics=[]'.length + 4096));
    });

    test('cuts never split a surrogate pair', () {
      final buffer = StartupDiagnosticBuffer()
        ..record('${'a' * 2044}${'\u{1F600}' * 10}');

      expect(buffer.entries.single, '${'a' * 2044}...');
      expect(
        formatStartupDiagnostics(<String>[
          'a\u{1F600}${'b' * 20}',
          'c',
        ], maxLength: 10),
        ', startupDiagnostics=[a...; c]',
      );
    });

    test('a zero content limit omits the diagnostic suffix', () {
      expect(
        formatStartupDiagnostics(const <String>['failure'], maxLength: 0),
        isEmpty,
      );
    });

    test('diagnostics are single-line and redact credentialed URLs', () {
      expect(
        formatStartupDiagnostics(const <String>[
          'failed at HTTPS:\n//user\u0085:pass@example.com/lib.so'
              '?token=secret#part',
          'next\u0000line\u0085more\u2028last\u2029line',
        ]),
        ', startupDiagnostics=['
        '<redacted-startup-diagnostic>; next line more last line]',
      );
      expect(
        formatStartupDiagnostics(const <String>[
          'failed at https://user:pass@[2001:db8::1]/lib.so?token=secret',
        ]),
        ', startupDiagnostics=[failed at https://[2001:db8::1]/lib.so]',
      );
      expect(
        formatStartupDiagnostics(const <String>[
          'https://safe.example/a,HTTPS://user:pass@evil.example/b'
              '?token=secret',
        ]),
        ', startupDiagnostics=['
        'https://safe.example/a,https://evil.example/b]',
      );
      expect(
        formatStartupDiagnostics(const <String>['https://example.com\nfailed']),
        ', startupDiagnostics=[https://example.com failed]',
      );
      expect(
        formatStartupDiagnostics(const <String>[
          'https://example.com\nfailed@evil.example',
          'https://example.com/path?\ntoken=secret',
        ]),
        ', startupDiagnostics=['
        '<redacted-startup-diagnostic>; '
        '<redacted-startup-diagnostic>]',
      );
    });

    test('diagnostics redact bearer tokens outside URLs', () {
      expect(
        formatStartupDiagnostics(const <String>[
          'Authorization: Bearer eyJhbGciOi.secret rejected',
          'header BEARER abc-123',
          'bearer\ttok3n',
          'Bearer "x y" z',
          "Bearer 'x y' z",
          'Bearer',
        ]),
        ', startupDiagnostics=['
        'Authorization: Bearer <redacted-secret> rejected; '
        'header BEARER <redacted-secret>; '
        'bearer <redacted-secret>; '
        'Bearer <redacted-secret> z; '
        'Bearer <redacted-secret> z; '
        'Bearer]',
      );
      expect(
        formatStartupDiagnostics(const <String>['forbearer of news']),
        ', startupDiagnostics=[forbearer of news]',
      );
    });

    test('diagnostics redact key=value secrets outside URLs', () {
      expect(
        formatStartupDiagnostics(const <String>[
          'token=abc123 failed',
          'token=t key=k secret=s password=p api_key=a apikey=b',
          'KEY=k1,secret=s1;password=p1 api_key=a1 apikey=a2',
          'access_token=abc x-api-key=def client.secret=ghi',
          'Authorization=Bearer abc def',
          'token=Bearer abc def',
          '(token=paren)',
          'token=',
        ]),
        ', startupDiagnostics=['
        'token=<redacted-secret> failed; '
        'token=<redacted-secret> key=<redacted-secret> '
        'secret=<redacted-secret> password=<redacted-secret> '
        'api_key=<redacted-secret> apikey=<redacted-secret>; '
        'KEY=<redacted-secret> api_key=<redacted-secret> '
        'apikey=<redacted-secret>; '
        'access_token=<redacted-secret> x-api-key=<redacted-secret> '
        'client.secret=<redacted-secret>; '
        'Authorization=Bearer <redacted-secret> def; '
        'token=<redacted-secret> def; '
        '(token=<redacted-secret>; '
        'token=]',
      );
      expect(
        formatStartupDiagnostics(const <String>[
          'secret="s p a c e" tail',
          "secret='s p a c e' tail",
          'token="abc",secret="def"',
          'token=Bearer "a b" tail',
          'token="unterminated tail',
        ]),
        ', startupDiagnostics=['
        'secret=<redacted-secret> tail; '
        'secret=<redacted-secret> tail; '
        'token=<redacted-secret>,secret=<redacted-secret>; '
        'token=<redacted-secret> tail; '
        'token=<redacted-secret> tail]',
      );
    });

    test('diagnostics keep identifiers that only contain a secret keyword', () {
      const safe = <String>[
        'keyboard=us monkey=1 tokenizer=bpe passwordless=true secrets=0',
        'cacheKey=abc n_tokens=42 key: value token: 7 key = v',
        'https://example.com/key=in-path?x=1',
      ];
      expect(
        formatStartupDiagnostics(safe),
        ', startupDiagnostics=['
        'keyboard=us monkey=1 tokenizer=bpe passwordless=true secrets=0; '
        'cacheKey=abc n_tokens=42 key: value token: 7 key = v; '
        'https://example.com/key=in-path]',
      );
    });

    test('secret redaction leaves URL redaction unchanged', () {
      expect(
        formatStartupDiagnostics(const <String>[
          'token=https://user:pass@host/x?token=secret',
          'Bearer https://user:pass@host/y#f rest',
          'key=abchttps://user:pass@host/z key=def',
          'HTTPS://host/path,token=in-path',
          'https://user:pass@example.com/lib.so'
              '?X-Amz-Signature=secret&access_token=bearer-secret#secret',
          'token=https://[bad',
          'Bearer https://[bad rest',
          'http://[bad token=abc',
        ]),
        ', startupDiagnostics=['
        'token=https://host/x; '
        'Bearer https://host/y rest; '
        'key=<redacted-secret>https://host/z key=<redacted-secret>; '
        'https://host/path,token=in-path; '
        'https://example.com/lib.so; '
        'token=<redacted-url>; '
        'Bearer <redacted-url> rest; '
        '<redacted-url> token=<redacted-secret>]',
      );
      expect(
        formatStartupDiagnostics(const <String>[
          'token=abc https://example.com/path?\nkey=secret',
        ]),
        ', startupDiagnostics=[<redacted-startup-diagnostic>]',
      );
    });

    test('the buffer stores secret-redacted entries', () {
      final buffer = StartupDiagnosticBuffer()
        ..record('loader said Bearer abc')
        ..record(
          'loader said api_key=xyz',
          category: StartupDiagnosticCategory.teardown,
        );
      expect(buffer.entries, <String>[
        'loader said Bearer <redacted-secret>',
        '${startupTeardownDiagnosticPrefix}loader said api_key=<redacted-secret>',
      ]);
    });

    test('the model-load message carries the diagnostics', () {
      final message = describeModelLoadFailure(
        sizeBytes: 4700000000,
        backendDiagnostics: '{moduleDir=/x}',
        startupDiagnostics: const <String>['libggml.so failed to load'],
      );

      expect(
        message,
        'Failed to load model (size=4700000000 bytes, '
        'diagnostics={moduleDir=/x}), '
        'startupDiagnostics=[libggml.so failed to load]',
      );
    });

    test('the draft-model message carries the diagnostics', () {
      final message = describeDraftModelLoadFailure(
        label: 'speculative draft model',
        path: '/draft.gguf',
        sizeBytes: 120,
        backendDiagnostics: '{moduleDir=/x}',
        startupDiagnostics: const <String>['libggml.so failed to load'],
      );

      expect(
        message,
        'Failed to load speculative draft model (size=120 bytes, '
        'path=/draft.gguf, diagnostics={moduleDir=/x}), '
        'startupDiagnostics=[libggml.so failed to load]',
      );
    });

    test('both messages are unchanged when nothing was recorded', () {
      expect(
        describeModelLoadFailure(
          sizeBytes: 1,
          backendDiagnostics: '{}',
          startupDiagnostics: const <String>[],
        ),
        'Failed to load model (size=1 bytes, diagnostics={})',
      );
      expect(
        describeDraftModelLoadFailure(
          label: 'draft',
          path: '/d.gguf',
          sizeBytes: 1,
          backendDiagnostics: '{}',
          startupDiagnostics: const <String>[],
        ),
        'Failed to load draft (size=1 bytes, path=/d.gguf, diagnostics={})',
      );
    });
  });
}
