@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_decision.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';
import 'package:web/web.dart'
    show Blob, BlobPropertyBag, HTMLBaseElement, URL, document, window;

import '../../../support/fake_webgpu_decision_bridge.dart';

@JS('Error')
external JSObject _jsError(String message);

const _credentialFreeUrls = <(String, String)>[
  (
    'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/h.bin?v=1',
    'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/h.bin',
  ),
  (
    'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/h.bin?v=2',
    'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/h.bin',
  ),
  (
    'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/h.bin'
        '?revision=main',
    'https://huggingface.co/leehack/Qwen3-1.7B-head/resolve/main/h.bin',
  ),
  (
    'https://acct.blob.core.windows.net/heads/h.bin?sv=2022-11-02&ss=b'
        '&srt=o&sp=r&se=2030-01-01T00%3A00%3A00Z'
        '&sig=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789%3D',
    'https://acct.blob.core.windows.net/heads/h.bin',
  ),
  ('https://example.com/h.bin?download', 'https://example.com/h.bin'),
  (
    'https://example.com:8080/h.bin?port=8080',
    'https://example.com:8080/h.bin',
  ),
  ('http://127.0.0.1:9/h.bin?t=1', 'http://127.0.0.1:9/h.bin'),
  ('https://[::1]:8443/h.bin?x=1', 'https://[::1]:8443/h.bin'),
];

void main() {
  late FakeDecisionBridge fake;
  late WebGpuDecisionHeads heads;

  setUp(() {
    fake = FakeDecisionBridge();
    heads = WebGpuDecisionHeads();
  });

  BackendDecisionSequence sequence(
    List<int> tokens,
    List<int> markers, [
    DecisionQuestionType questionType = DecisionQuestionType.choice,
  ]) => BackendDecisionSequence(
    tokens: Int32List.fromList(tokens),
    markers: Int32List.fromList(markers),
    questionType: questionType,
  );

  Matcher throwsTyped<T extends LlamaException>(Object? message) =>
      throwsA(isA<T>().having((error) => error.message, 'message', message));

  String blobUrl(String text) => URL.createObjectURL(
    Blob(<JSAny>[text.toJS].toJS, BlobPropertyBag(type: 'application/json')),
  );

  String pageUrl(String path) =>
      Uri.parse(document.baseURI).resolve(path).toString();

  void useBaseHref(String href) {
    final base = document.createElement('base') as HTMLBaseElement..href = href;
    document.head!.append(base);
    addTearDown(() => base.remove());
  }

  group('capabilities', () {
    test('reports supported for decision API version 1', () async {
      final capabilities = await heads.capabilities(fake.bridge);

      expect(capabilities.isSupported, isTrue);
      expect(capabilities.unsupportedReason, isNull);
      expect(fake.calls, ['capabilities']);
    });

    test('names the required assets for bridges without the API', () async {
      final old = FakeDecisionBridge(withDecisionApi: false);
      final partials = [
        for (final method in [
          'getDecisionCapabilities',
          'loadDecisionHead',
          'runDecision',
          'freeDecisionHead',
        ])
          FakeDecisionBridge()..object.delete(method.toJS),
      ];

      for (final bridge in [old, ...partials]) {
        final capabilities = await heads.capabilities(bridge.bridge);

        expect(capabilities.isSupported, isFalse);
        expect(
          capabilities.unsupportedReason,
          'Web decision models need llama-web-bridge assets v0.1.47+ with '
          'the decision API (apiVersion 1); the loaded bridge does not expose '
          'it.',
        );
        expect(bridge.calls, isEmpty);
      }
    });

    test('reports another decision API version as unsupported', () async {
      fake.capabilitiesApiVersion = 2;
      final skewed = await heads.capabilities(fake.bridge);
      fake.capabilitiesResult = JSObject()
        ..setProperty('supported'.toJS, true.toJS);
      final unversioned = await heads.capabilities(fake.bridge);

      expect(skewed.isSupported, isFalse);
      expect(
        skewed.unsupportedReason,
        'The Web bridge implements decision API version 2; llamadart needs '
        'llama-web-bridge assets v0.1.47+ with the decision API (apiVersion 1).',
      );
      expect(unversioned.isSupported, isFalse);
      expect(unversioned.unsupportedReason, contains('version unknown'));
    });

    test('passes the bridge reason through', () async {
      fake
        ..supported = false
        ..reason = 'Decision heads need a ModernBERT encoder GGUF.';
      final withReason = await heads.capabilities(fake.bridge);
      fake.reason = '';
      final withoutReason = await heads.capabilities(fake.bridge);

      expect(withReason.isSupported, isFalse);
      expect(
        withReason.unsupportedReason,
        'Decision heads need a ModernBERT encoder GGUF.',
      );
      expect(
        withoutReason.unsupportedReason,
        'The loaded Web model does not support decision heads.',
      );
    });

    test('reports a response without supported as unsupported', () async {
      fake.capabilitiesResult = JSObject()
        ..setProperty('apiVersion'.toJS, 1.toJS);

      final capabilities = await heads.capabilities(fake.bridge);

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'The loaded Web model does not support decision heads.',
      );
    });

    test('throws LlamaStateException for state rejections', () async {
      for (final message in [
        'Bridge has been disposed.',
        'Decision capability probe was cancelled.',
        'No model loaded. Call loadModelFromUrl first.',
      ]) {
        fake.capabilitiesError = message;

        await expectLater(
          heads.capabilities(fake.bridge),
          throwsTyped<LlamaStateException>(message),
          reason: message,
        );
        await expectLater(
          heads.load(fake.bridge, 'laya-head.safetensors'),
          throwsTyped<LlamaStateException>(message),
          reason: message,
        );
      }
      expect(fake.calls.where((call) => call.startsWith('load')), isEmpty);
    });

    test('reports invalid responses and failed probes', () async {
      fake.capabilitiesResult = 'yes'.toJS;
      final invalid = await heads.capabilities(fake.bridge);
      fake
        ..capabilitiesResult = null
        ..capabilitiesError = 'WebGPU core is not initialized';
      final failed = await heads.capabilities(fake.bridge);

      expect(invalid.isSupported, isFalse);
      expect(
        invalid.unsupportedReason,
        'The Web decision capability response is invalid.',
      );
      expect(failed.isSupported, isFalse);
      expect(
        failed.unsupportedReason,
        'The Web decision capability probe failed: WebGPU core is not '
        'initialized',
      );
    });
  });

  group('load', () {
    test('returns the head under a backend handle', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');

      expect(head.handle, 1);
      expect(head.hiddenSize, 4);
      expect(head.clsToken, 1);
      expect(head.sepToken, 2);
      expect(head.maskToken, 3);
      expect(head.maskText, '[MASK]');
      expect(head.configJson, '{"max_len": 32, "head_max_len": 16}');
      expect(head.deviceName, 'WebGPU');
      expect(fake.calls, [
        'capabilities',
        'load ${pageUrl('laya-head.safetensors')}',
      ]);
      expect(fake.loadedConfigs, [null]);
      expect(fake.liveHandles, {7});
    });

    test('fetches configPath and passes its text to the bridge', () async {
      const config = '{"max_len": 64, "head_max_len": 24}';
      final url = blobUrl(config);
      addTearDown(() => URL.revokeObjectURL(url));

      final head = await heads.load(
        fake.bridge,
        'model.safetensors',
        configUrl: url,
      );

      expect(fake.loadedConfigs, [config]);
      expect(head.configJson, config);
    });

    test('rejects unsupported models before loading', () async {
      fake
        ..supported = false
        ..reason = 'The loaded model reports architecture "llama".';

      await expectLater(
        heads.load(fake.bridge, 'laya-head.safetensors'),
        throwsTyped<LlamaUnsupportedException>(
          'The loaded model reports architecture "llama".',
        ),
      );
      await expectLater(
        heads.load(
          FakeDecisionBridge(withDecisionApi: false).bridge,
          'laya-head.safetensors',
        ),
        throwsTyped<LlamaUnsupportedException>(
          contains('decision API (apiVersion 1)'),
        ),
      );
      expect(fake.calls, ['capabilities']);
    });

    test('fails with LlamaModelException for unreadable configs', () async {
      final revoked = blobUrl('{}');
      URL.revokeObjectURL(revoked);

      await expectLater(
        heads.load(
          fake.bridge,
          'laya-head.safetensors',
          configUrl: 'missing_decision_config.json?token=secret#frag',
        ),
        throwsA(
          isA<LlamaModelException>()
              .having(
                (error) => error.message,
                'message',
                'Cannot read the decision head config at '
                    '${pageUrl('missing_decision_config.json')}.',
              )
              .having(
                (error) => '${error.details}',
                'details',
                startsWith('HTTP 404'),
              ),
        ),
      );
      await expectLater(
        heads.load(fake.bridge, 'laya-head.safetensors', configUrl: revoked),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            startsWith('Cannot read the decision head config at blob:'),
          ),
        ),
      );
      expect(fake.calls.where((call) => call.startsWith('load')), isEmpty);
    });

    test('fails with LlamaModelException when a config body fails', () async {
      final fetch = globalContext.getProperty<JSAny?>('fetch'.toJS);
      addTearDown(() => globalContext.setProperty('fetch'.toJS, fetch));
      globalContext.setProperty(
        'fetch'.toJS,
        ((JSAny? url) => Future<JSAny?>.value(
          JSObject()
            ..setProperty('ok'.toJS, true.toJS)
            ..setProperty('status'.toJS, 200.toJS)
            ..setProperty(
              'text'.toJS,
              (() => rejectWithMessage('network error')).toJS,
            ),
        ).toJS).toJS,
      );

      await expectLater(
        heads.load(
          fake.bridge,
          'laya-head.safetensors',
          configUrl: 'https://example.com/rl_agent_config.json',
        ),
        throwsA(
          isA<LlamaModelException>()
              .having(
                (error) => error.message,
                'message',
                'Cannot read the decision head config at '
                    'https://example.com/rl_agent_config.json.',
              )
              .having((error) => error.details, 'details', 'network error'),
        ),
      );
      expect(fake.calls.where((call) => call.startsWith('load')), isEmpty);
    });

    test('resolves head and config URLs against the document base', () async {
      useBaseHref(pageUrl('decision-base/'));

      await heads.load(fake.bridge, 'models/laya-head.safetensors');
      await expectLater(
        heads.load(
          fake.bridge,
          'models/model.safetensors',
          configUrl: 'models/rl_agent_config.json',
        ),
        throwsTyped<LlamaModelException>(
          'Cannot read the decision head config at '
          '${pageUrl('models/rl_agent_config.json')}.',
        ),
      );
      final blob = blobUrl('{}');
      addTearDown(() => URL.revokeObjectURL(blob));
      await heads.load(fake.bridge, blob);

      expect(document.baseURI, endsWith('/decision-base/'));
      expect(fake.calls.where((call) => call.startsWith('load')), [
        'load ${pageUrl('models/laya-head.safetensors')}',
        'load $blob',
      ]);
    });

    test('keeps credentials and queries out of load errors', () async {
      const secretConfig =
          'https://alice:s3cret@example.com/rl_agent_config.json?sig=xyz#frag';
      const secretHead =
          'https://alice:s3cret@example.com/laya-head.safetensors?sig=xyz';
      Matcher redacted(String message) => throwsA(
        isA<LlamaModelException>()
            .having((error) => error.message, 'message', message)
            .having(
              (error) => '$error',
              'toString',
              allOf(
                isNot(contains('s3cret')),
                isNot(contains('alice')),
                isNot(contains('hunter2')),
                isNot(contains('bob')),
                isNot(contains('sig=')),
                isNot(contains('token=')),
                isNot(contains('frag')),
              ),
            ),
      );

      await expectLater(
        heads.load(
          fake.bridge,
          'laya-head.safetensors',
          configUrl: secretConfig,
        ),
        redacted(
          'Cannot read the decision head config at '
          'https://example.com/rl_agent_config.json.',
        ),
      );
      fake.loadError =
          "Failed to execute 'fetch' on 'Window': Request cannot be "
          'constructed from a URL that includes credentials: $secretHead';
      await expectLater(
        heads.load(fake.bridge, secretHead),
        redacted(
          "Failed to execute 'fetch' on 'Window': Request cannot be "
          'constructed from a URL that includes credentials: '
          'https://example.com/laya-head.safetensors',
        ),
      );
      fake.loadError =
          'Failed to fetch decision head from '
          'https://bob:hunter2@cdn.example.com/head?token=abc (timeout)';
      await expectLater(
        heads.load(fake.bridge, 'laya-head.safetensors'),
        redacted(
          'Failed to fetch decision head from https://cdn.example.com/head '
          '(timeout)',
        ),
      );
      fake.loadError =
          "Failed to execute 'fetch' on 'Window': Failed to parse URL from "
          'https://bob:hunter2@[cdn/head?token=abc';
      await expectLater(
        heads.load(fake.bridge, 'laya-head.safetensors'),
        redacted(
          "Failed to execute 'fetch' on 'Window': Failed to parse URL from "
          'https://[cdn/head',
        ),
      );
      fake.loadError =
          'Failed to fetch decision head /heads/laya-head.safetensors'
          '?token=abc#frag (404)';
      await expectLater(
        heads.load(fake.bridge, 'laya-head.safetensors'),
        redacted(
          'Failed to fetch decision head /heads/laya-head.safetensors (404)',
        ),
      );
    });

    test('keeps source URL secrets out of real Chrome fetch errors', () async {
      fake.bridge.setProperty(
        'loadDecisionHead'.toJS,
        ((JSAny? url, JSObject? options) => window.fetch(url!)).toJS,
      );
      const credentials = 'includes credentials';
      const unparsable = 'Failed to parse URL from';
      for (final (url, phrase, redacted, secrets) in const [
        (
          'https://u:SEK"RIT@example.com/h.bin',
          credentials,
          'https://example.com/h.bin',
          <String>['SEK', 'RIT'],
        ),
        (
          'https://u:SEKRIT/w@example.com/h.bin',
          unparsable,
          'https://example.com/h.bin',
          <String>['SEKRIT', '/w@'],
        ),
        (
          '//u:SEKRIT/w@example.com/h.bin',
          unparsable,
          '//example.com/h.bin',
          <String>['SEKRIT', '/w@'],
        ),
        (
          'https://u:SEK RIT/w@example.com/h.bin',
          unparsable,
          'https://example.com/h.bin',
          <String>['SEK', 'RIT', '/w@'],
        ),
        (
          'https://u:SEK RIT@example.com/h.bin?sig=Q9',
          credentials,
          'https://example.com/h.bin',
          <String>['SEK', 'RIT', 'Q9'],
        ),
        (
          'https://u:S1ab@S2cd#S3ef%40S4gh?S5ij\u00fcS6kl@example.com/h.bin',
          credentials,
          'credentials: https://',
          <String>['S1ab', 'S2cd', 's2cd', 'S3ef', 'S4gh', 'S5ij', 'S6kl'],
        ),
        (
          'https://u:P7@example.com/h.bin?token=abc@SEKsecret',
          credentials,
          'https://example.com/h.bin',
          <String>['P7', 'abc', 'SEKsecret', 'seksecret'],
        ),
        (
          'https://u:P7@example.com/h.bin#frag@SEKsecret',
          credentials,
          'https://example.com/h.bin',
          <String>['P7', 'frag', 'SEKsecret', 'seksecret'],
        ),
        (
          'https://u:P7@example.com/path@SEKpath/h.bin',
          credentials,
          'https://example.com/path@SEKpath/h.bin',
          <String>['P7', 'sekpath'],
        ),
      ]) {
        final leaksNoSecret = allOf(<Matcher>[
          contains(phrase),
          contains(redacted),
          isNot(contains('u:')),
          isNot(contains('\u00fc')),
          isNot(contains('%C3%BC')),
          isNot(contains('%40')),
          for (final secret in secrets) isNot(contains(secret)),
        ]);
        await expectLater(
          heads.load(fake.bridge, url),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => '$error',
              'toString',
              leaksNoSecret,
            ),
          ),
          reason: 'head $url',
        );
        await expectLater(
          heads.load(fake.bridge, 'laya-head.safetensors', configUrl: url),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => '$error',
              'toString',
              leaksNoSecret,
            ),
          ),
          reason: 'config $url',
        );
      }
    });

    test(
      'shows the host of source URLs with @ in the query, fragment or path',
      () async {
        fake.bridge.setProperty(
          'loadDecisionHead'.toJS,
          ((JSAny? url, JSObject? options) => window.fetch(url!)).toJS,
        );
        for (final (url, display) in const [
          (
            'http://127.0.0.1:9/h.bin?token=abc@SEKsecret',
            'http://127.0.0.1:9/h.bin',
          ),
          (
            'http://127.0.0.1:9/h.bin#frag@SEKsecret',
            'http://127.0.0.1:9/h.bin',
          ),
          (
            'http://127.0.0.1:9/path@SEKpath/h.bin',
            'http://127.0.0.1:9/path@SEKpath/h.bin',
          ),
        ]) {
          final leaksNoSecret = allOf(<Matcher>[
            isNot(contains('abc')),
            isNot(contains('frag')),
            isNot(contains('SEKsecret')),
            isNot(contains('seksecret')),
            isNot(contains('sekpath')),
          ]);
          await expectLater(
            heads.load(fake.bridge, url),
            throwsA(
              isA<LlamaModelException>()
                  .having((error) => error.details, 'details', display)
                  .having((error) => '$error', 'toString', leaksNoSecret),
            ),
            reason: 'head $url',
          );
          await expectLater(
            heads.load(fake.bridge, 'laya-head.safetensors', configUrl: url),
            throwsA(
              isA<LlamaModelException>()
                  .having(
                    (error) => error.message,
                    'message',
                    'Cannot read the decision head config at $display.',
                  )
                  .having((error) => '$error', 'toString', leaksNoSecret),
            ),
            reason: 'config $url',
          );
        }
      },
    );

    test(
      'classifies bridge errors before removing source URL secrets',
      () async {
        fake.loadError = 'No model loaded. Call loadModelFromUrl first.';
        await expectLater(
          heads.load(fake.bridge, 'https://u:model@example.com/h.bin?k=loaded'),
          throwsTyped<LlamaStateException>(
            'No  loaded. Call loadModelFromUrl first.',
          ),
        );
      },
    );

    test('keeps the host when path text matches a query part', () async {
      fake.loadError = 'Failed to fetch decision head: 404 Not Found';
      for (final (url, display) in const [
        (
          'https://example.com/heads/abcdefghijkl/h.bin?rev=abcdefghijkl',
          'https://example.com/heads/abcdefghijkl/h.bin',
        ),
        ('https://example.com/v=1/h.bin?v=1', 'https://example.com/v=1/h.bin'),
      ]) {
        await expectLater(
          heads.load(fake.bridge, url),
          throwsA(
            isA<LlamaModelException>().having(
              (error) => error.details,
              'details',
              display,
            ),
          ),
          reason: url,
        );
        expect(
          webGpuBridgeErrorText(
            _jsError('Failed to fetch $url'),
            sourceUrls: [url],
          ),
          'Failed to fetch $display',
          reason: url,
        );
      }
    });

    test('keeps messages and hosts of credential-free source URLs', () async {
      for (final (url, display) in <(String, String)>[
        ..._credentialFreeUrls,
        ('/heads/h.bin?token=t', pageUrl('/heads/h.bin')),
      ]) {
        for (final message in const [
          'Failed to fetch decision head: 404 Not Found',
          'Decision head "max_len" 512 exceeds 256 tokens.',
          'Decision head v2 has 1 output, not 2.',
        ]) {
          fake.loadError = message;
          await expectLater(
            heads.load(fake.bridge, url),
            throwsA(
              isA<LlamaModelException>()
                  .having((error) => error.message, 'message', message)
                  .having((error) => error.details, 'details', display),
            ),
            reason: '$url: $message',
          );
        }
      }
      fake.loadError = null;
      fake.bridge.setProperty(
        'loadDecisionHead'.toJS,
        ((JSAny? url, JSObject? options) => window.fetch(url!)).toJS,
      );
      for (final (url, display, details) in <(String, String, String)>[
        ('http://127.0.0.1:9/h.bin?t=1', 'http://127.0.0.1:9/h.bin', 'Failed'),
        ('https://[::1]:8443/h.bin?x=1', 'https://[::1]:8443/h.bin', 'Failed'),
        ('/heads/h.bin?token=t', pageUrl('/heads/h.bin'), 'HTTP 404'),
      ]) {
        if (!details.startsWith('HTTP')) {
          await expectLater(
            heads.load(fake.bridge, url),
            throwsA(
              isA<LlamaModelException>()
                  .having(
                    (error) => error.message,
                    'message',
                    'Failed to fetch',
                  )
                  .having((error) => error.details, 'details', display),
            ),
            reason: 'head $url',
          );
        }
        await expectLater(
          heads.load(fake.bridge, 'laya-head.safetensors', configUrl: url),
          throwsA(
            isA<LlamaModelException>()
                .having(
                  (error) => error.message,
                  'message',
                  'Cannot read the decision head config at $display.',
                )
                .having(
                  (error) => '${error.details}',
                  'details',
                  details.startsWith('HTTP')
                      ? startsWith(details)
                      : 'Failed to fetch',
                ),
          ),
          reason: 'config $url',
        );
      }
    });

    test('removes the secrets of source URLs wherever they occur', () {
      for (final (source, message, expected) in const [
        (
          'https://u:SEKRIT/w@example.com/m.gguf#F6fragment',
          'Bad password SEKRIT/w for u at F6fragment',
          'Bad password  for u at ',
        ),
        (
          'https://u:S1ab@S2cd#S3ef%40S4gh?S5ijüS6kl@example.com/m.gguf',
          'Bad password S1ab@S2cd#S3ef@S4gh?S5ijüS6kl (encoded '
              'S1ab%40S2cd%23S3ef%2540S4gh%3FS5ij%C3%BCS6kl)',
          'Bad password  (encoded )',
        ),
        (
          'https://u:example@example.com/h.bin',
          'Failed to fetch https://u:example@example.com/h.bin',
          'Failed to fetch https://',
        ),
        (
          'https://example.com/h.bin?token=t&v=1&sig=Q9signature',
          'Fetch /h.bin?token=t&v=1&sig=Q9signature: token=t, max_len 512, '
              'v=1 of 1, signature Q9signature',
          'Fetch /h.bin: , max_len 512,  of 1, signature ',
        ),
        (
          'https://example.com/m.gguf?sig=Q9signature&token=T8tokenvalue'
              '#F7fragment',
          'Signature Q9signature, token T8tokenvalue and fragment F7fragment '
              'expired',
          'Signature , token  and fragment  expired',
        ),
        (
          'https://example.com/h.bin?v=1',
          'Built with dev=10 and v=12.',
          'Built with dev=10 and v=12.',
        ),
        (
          'https://example.com/h.bin?download#k1',
          'GET h?download failed at node#k1, not #k1',
          'GET h failed at node, not #k1',
        ),
        (
          'https://u:SEK"RIT@example.com/m.gguf',
          r'{"password":"SEK\"RIT"}',
          '{"password":""}',
        ),
      ]) {
        expect(
          webGpuBridgeErrorText(_jsError(message), sourceUrls: [source]),
          expected,
          reason: message,
        );
      }
    });

    test('redacts relative and quote-delimited URLs in bridge errors', () {
      const cases = <String, String>{
        'Failed to fetch /relative/mmproj.gguf?token=S7':
            'Failed to fetch /relative/mmproj.gguf',
        'Failed to fetch mmproj.gguf#sig=S8 (404 Not Found)':
            'Failed to fetch mmproj.gguf (404 Not Found)',
        'Bad URL "https://cdn.example.com/p.gguf?token=S5"tail=S6 end':
            'Bad URL "https://cdn.example.com/p.gguf end',
        'Bad URL "https://u:S9@cdn.example.com/p.gguf?token=S10" end':
            'Bad URL "https://cdn.example.com/p.gguf" end',
        "Bad URL '/p.gguf?token=S11'.": "Bad URL '/p.gguf'.",
        'Is a model loaded? Load one first.':
            'Is a model loaded? Load one first.',
        'URL includes credentials: //u:S13@example.com/m.gguf?t=Q1':
            'URL includes credentials: //example.com/m.gguf',
        'Bad URL (u:S15@cdn.example.com:8080/m.gguf#k=Q3)':
            'Bad URL (cdn.example.com:8080/m.gguf)',
        'Bad URL ./m.gguf?t=Q4 and ../m.gguf#t=Q5':
            'Bad URL ./m.gguf and ../m.gguf',
        'Bad URL mmproj?token=S16': 'Bad URL mmproj',
        'Bad URL u@cdn.example.com/m.gguf?t=Q6':
            'Bad URL cdn.example.com/m.gguf',
        'Bad URL a@b.example.com?k=Q7': 'Bad URL b.example.com',
        'Bad URL <//u@example.com/m.gguf>': 'Bad URL <//example.com/m.gguf>',
        'Bad URL https://u:SEK"RIT@example.com/m.gguf':
            'Bad URL https://example.com/m.gguf',
        'Bad URL //u:SEKRIT/w@example.com/m.gguf?t=Q8':
            'Bad URL //example.com/m.gguf',
        'Bad URL x=https://u:p/w@example.com/m.gguf':
            'Bad URL x=https://example.com/m.gguf',
        'Bad URL https://example.com/h.bin?token=abc@SEKsecret':
            'Bad URL https://example.com/h.bin',
        'Bad URL https://example.com/h.bin#frag@SEKsecret':
            'Bad URL https://example.com/h.bin',
        'Bad URL https://u:p@[Q@example.com/m.gguf':
            'Bad URL https://example.com/m.gguf',
        'Bad URL https://example.com/path@SEKpath/h.bin':
            'Bad URL https://example.com/path@SEKpath/h.bin',
        'Bad URL https://u:p@example.com/h.bin?e=a@b.example':
            'Bad URL https://example.com/h.bin',
      };
      for (final MapEntry(key: message, value: expected) in cases.entries) {
        expect(
          webGpuBridgeErrorText(_jsError(message)),
          expected,
          reason: message,
        );
      }
    });

    test('leaves text that is not a URL unchanged in bridge errors', () {
      for (final message in const [
        "Expected '?' after the key.",
        'Only C# and F#? are supported.',
        'See issue#43 for details.',
        'Loaded what?! Twice?',
        'Contact admin@example.com or user:name at 10:30.',
        'Decision sequence 0 has 4 markers for its 3 tokens.',
      ]) {
        expect(webGpuBridgeErrorText(_jsError(message)), message);
      }
    });

    test('names the config in bridge config errors', () async {
      final config = blobUrl('{"max_len": "long"}');
      addTearDown(() => URL.revokeObjectURL(config));
      fake.loadError =
          'Failed to load decision head: The decision head at '
          '"model.safetensors" has no "laya.config" metadata. Pass configJson '
          "with the head's rl_agent_config.json.";

      await expectLater(
        heads.load(fake.bridge, 'model.safetensors'),
        throwsTyped<LlamaModelException>(
          'The decision head at "model.safetensors" has no "laya.config" '
          "metadata. Pass the head's rl_agent_config.json as its config.",
        ),
      );
      fake.loadError =
          'Failed to load decision head: The decision head config in '
          'configJson is invalid: Decision head "max_len" must be a positive '
          'integer, got "long".';
      await expectLater(
        heads.load(fake.bridge, 'model.safetensors', configUrl: config),
        throwsTyped<LlamaModelException>(
          'The decision head config in $config is invalid: Decision head '
          '"max_len" must be a positive integer, got "long".',
        ),
      );
    });

    test('maps bridge load failures to typed exceptions', () async {
      final cases = <(String, Matcher)>[
        (
          'Failed to load decision head: The decision head at '
              '"laya-head.safetensors" is 768 wide but the loaded encoder has '
              'hidden size 1024. Use the head trained for this encoder.',
          throwsA(
            isA<LlamaModelException>()
                .having(
                  (error) => error.message,
                  'message',
                  startsWith('The decision head at "laya-head.safetensors"'),
                )
                .having(
                  (error) => error.details,
                  'details',
                  'https://example.com/laya-head.safetensors',
                ),
          ),
        ),
        (
          'Failed to fetch decision head: 404 Not Found',
          throwsTyped<LlamaModelException>(
            'Failed to fetch decision head: 404 Not Found',
          ),
        ),
        (
          'Failed to load decision head: Failed to create the decision '
              'encoder context of 512 tokens.',
          throwsTyped<LlamaContextException>(
            'Failed to create the decision encoder context of 512 tokens.',
          ),
        ),
        (
          'No model loaded. Call loadModelFromUrl first.',
          throwsTyped<LlamaStateException>(
            'No model loaded. Call loadModelFromUrl first.',
          ),
        ),
        (
          'Bridge has been disposed.',
          throwsTyped<LlamaStateException>('Bridge has been disposed.'),
        ),
        (
          'Decision head load was cancelled.',
          throwsTyped<LlamaStateException>('Decision head load was cancelled.'),
        ),
      ];
      for (final (message, matcher) in cases) {
        fake.loadError = message;
        await expectLater(
          heads.load(
            fake.bridge,
            'https://user:pass@example.com/laya-head.safetensors?sig=abc',
          ),
          matcher,
          reason: message,
        );
      }
    });

    test('frees a head that reports another API version', () async {
      fake.headInfoOverrides = {'apiVersion': 2};

      await expectLater(
        heads.load(fake.bridge, 'laya-head.safetensors'),
        throwsTyped<LlamaUnsupportedException>(
          'The Web bridge implements decision API version 2; llamadart needs '
          'llama-web-bridge assets v0.1.47+ with the decision API (apiVersion 1).',
        ),
      );
      expect(fake.calls.last, 'free 7');
      expect(fake.liveHandles, isEmpty);
    });

    test('frees a head with a malformed description', () async {
      for (final field in [
        'maskText',
        'configJson',
        'deviceName',
        'sepToken',
      ]) {
        fake.headInfoOverrides = {field: null};

        await expectLater(
          heads.load(fake.bridge, 'laya-head.safetensors'),
          throwsTyped<LlamaDecisionException>(
            'The Web decision runtime returned a malformed head description.',
          ),
          reason: field,
        );
      }
      fake.headInfoOverrides = {'hiddenSize': 1.5};
      await expectLater(
        heads.load(fake.bridge, 'laya-head.safetensors'),
        throwsA(isA<LlamaDecisionException>()),
      );
      expect(fake.liveHandles, isEmpty);

      for (final handle in [0, -1]) {
        fake.headInfoOverrides = {'handle': handle};
        await expectLater(
          heads.load(fake.bridge, 'laya-head.safetensors'),
          throwsA(isA<LlamaDecisionException>()),
          reason: '$handle',
        );
      }
      expect(fake.calls.where((call) => call.startsWith('free')), [
        for (final handle in [7, 8, 9, 10, 11]) 'free $handle',
      ]);
    });
  });

  group('run', () {
    test('sends typed sequences to the bridge handle', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');

      final outputs = await heads.run(fake.bridge, head.handle, [
        sequence([1, 3, 20, 3, 21, 2], [1, 3], DecisionQuestionType.score),
        sequence([1, 3, 2], [1], DecisionQuestionType.noul),
      ]);

      expect(fake.calls.last, 'run 7 2');
      expect(fake.lastSequences.map((s) => s.typedArrays), [true, true]);
      expect(fake.lastSequences.first.tokens, [1, 3, 20, 3, 21, 2]);
      expect(fake.lastSequences.first.markers, [1, 3]);
      expect(fake.lastSequences.map((s) => s.questionType), [1, 2]);
      expect(outputs, hasLength(2));
      expect(outputs.first.logits, isA<Float32List>());
      expect(outputs.first.logits, [2.0, 1.0]);
      expect(outputs.last.logits, [1.0]);
      expect(outputs.first.actLogits, [1.5, -0.5]);
    });

    test('keeps heads scoped to the bridge that loaded them', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');
      final other = FakeDecisionBridge();

      await expectLater(
        heads.run(other.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaStateException>(
          'Decision head 1 is not loaded on this Web runtime; it was freed, '
          'its model was unloaded, or the bridge restarted. Load the decision '
          'head again.',
        ),
      );
      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsA(isA<LlamaStateException>()),
      );
      await expectLater(
        heads.run(null, 99, const []),
        throwsA(isA<LlamaStateException>()),
      );
      expect(other.calls, isEmpty);
      expect(fake.calls.where((call) => call.startsWith('run')), isEmpty);
    });

    test('forgets every head on clear', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');
      heads.clear();

      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsA(isA<LlamaStateException>()),
      );
      await heads.free(fake.bridge, head.handle);
      expect(fake.calls.where((call) => !call.startsWith('capab')), [
        'load ${pageUrl('laya-head.safetensors')}',
      ]);
    });

    test(
      'maps bridge validation failures to LlamaInferenceException',
      () async {
        final head = await heads.load(fake.bridge, 'laya-head.safetensors');
        fake.runError =
            'Decision run failed: Decision sequence 0 has 4 markers for its 3 '
            'tokens; a sequence holds at most one marker per token.';

        await expectLater(
          heads.run(fake.bridge, head.handle, [
            sequence([1, 3, 2], [0, 1, 2, 1]),
          ]),
          throwsTyped<LlamaInferenceException>(
            'Decision sequence 0 has 4 markers for its 3 tokens; a sequence '
            'holds at most one marker per token.',
          ),
        );
        fake.runError = null;
        final outputs = await heads.run(fake.bridge, head.handle, [
          sequence([1, 3, 2], [1]),
        ]);
        expect(outputs, hasLength(1));
      },
    );

    test('keeps a head when the bridge is busy', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');
      fake.runError =
          'Decision run failed: Decision heads cannot be loaded or run during '
          'active generation or text-to-speech synthesis';

      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaStateException>(
          'Decision heads cannot be loaded or run during active generation or '
          'text-to-speech synthesis',
        ),
      );
      fake.runError = null;
      final outputs = await heads.run(fake.bridge, head.handle, [
        sequence([1], [0]),
      ]);
      expect(outputs, hasLength(1));
    });

    test('drops a head the bridge lost', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');
      fake.runError =
          'Decision head 1 was lost when the bridge worker failed (boom). '
          'Load the decision head again.';

      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaStateException>(contains('was lost')),
      );
      fake.runError = null;
      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaStateException>(contains('on this Web runtime')),
      );
      expect(fake.calls.where((call) => call.startsWith('run')), hasLength(1));
    });

    test('rejects malformed outputs with LlamaDecisionException', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');
      final results = <JSAny? Function()>[
        () => JSObject(),
        () => <JSAny?>[null].toJS,
        () => <JSAny?>[
          JSObject()
            ..setProperty('logits'.toJS, Float32List(1).toJS)
            ..setProperty('actLogits'.toJS, <JSNumber>[1.toJS].toJS),
        ].toJS,
        () => <JSAny?>[
          JSObject()..setProperty('logits'.toJS, Float32List(1).toJS),
        ].toJS,
        () => <JSAny?>[
          JSObject()
            ..setProperty('logits'.toJS, <JSNumber>[1.toJS].toJS)
            ..setProperty('actLogits'.toJS, Float32List(2).toJS),
        ].toJS,
      ];
      for (final result in results) {
        fake.runResult = result;
        await expectLater(
          heads.run(fake.bridge, head.handle, [
            sequence([1], [0]),
          ]),
          throwsTyped<LlamaDecisionException>(
            'The Web decision runtime returned malformed outputs.',
          ),
        );
      }
    });
  });

  group('error classification', () {
    Future<Object?> loadError() async {
      try {
        await heads.load(fake.bridge, 'laya-head.safetensors');
      } catch (error) {
        return error;
      }
      return null;
    }

    test('maps each code on load, whatever the message says', () async {
      const message = 'Reworded bridge message.';
      final cases = <(String, Matcher)>[
        ('head-lost', isA<LlamaStateException>()),
        ('no-model', isA<LlamaStateException>()),
        ('disposed', isA<LlamaStateException>()),
        ('cancelled', isA<LlamaStateException>()),
        ('busy', isA<LlamaStateException>()),
        ('invalid-state', isA<LlamaStateException>()),
        ('context', isA<LlamaContextException>()),
        ('unsupported', isA<LlamaUnsupportedException>()),
        (
          'model',
          isA<LlamaModelException>().having(
            (error) => error.details,
            'details',
            pageUrl('laya-head.safetensors'),
          ),
        ),
        ('inference', isA<LlamaInferenceException>()),
        ('invalid-argument', isA<LlamaModelException>()),
        ('runtime', isA<LlamaModelException>()),
        ('future-code', isA<LlamaModelException>()),
      ];
      for (final (code, matcher) in cases) {
        fake
          ..errorCode = code.toJS
          ..loadError = message;
        final error = await loadError();
        expect(error, matcher, reason: code);
        expect((error! as LlamaException).message, message, reason: code);
      }
    });

    test('maps each code on every other decision call', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');
      fake.errorCode = 'inference'.toJS;
      fake.runError = 'x';
      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaInferenceException>('x'),
      );
      fake.runError = 'y';
      fake.errorCode = 'runtime'.toJS;
      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaInferenceException>('y'),
      );
      fake.errorCode = 'unsupported'.toJS;
      fake.capabilitiesError = 'z';
      final capabilities = await heads.capabilities(fake.bridge);
      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.unsupportedReason,
        'The Web decision capability probe failed: z',
      );
      fake.errorCode = 'busy'.toJS;
      await expectLater(
        heads.capabilities(fake.bridge),
        throwsTyped<LlamaStateException>('z'),
      );
      fake.freeError = 'w';
      fake.errorCode = 'runtime'.toJS;
      await expectLater(
        heads.free(fake.bridge, head.handle),
        throwsTyped<LlamaStateException>('w'),
      );
    });

    test('a code wins over a conflicting message', () async {
      fake
        ..errorCode = 'inference'.toJS
        ..loadError = 'No model loaded. Call loadModelFromUrl first.';
      expect(await loadError(), isA<LlamaInferenceException>());
      fake
        ..errorCode = 'runtime'.toJS
        ..loadError = 'Bridge has been disposed.';
      expect(await loadError(), isA<LlamaModelException>());
    });

    test('classifies by message when the bridge sends no code', () async {
      final cases = <(String, Matcher)>[
        (
          'Decision head 1 is not loaded; Load the decision head again.',
          isA<LlamaStateException>(),
        ),
        (
          'No model loaded. Call loadModelFromUrl first.',
          isA<LlamaStateException>(),
        ),
        ('Bridge has been disposed.', isA<LlamaStateException>()),
        ('Decision head load was cancelled.', isA<LlamaStateException>()),
        (
          'Decision heads cannot be loaded or run during active generation.',
          isA<LlamaStateException>(),
        ),
        (
          'Failed to load decision head: Failed to create the decision '
              'encoder context of 512 tokens.',
          isA<LlamaContextException>(),
        ),
        ('Something else failed.', isA<LlamaModelException>()),
      ];
      for (final (message, matcher) in cases) {
        fake.loadError = message;
        expect(await loadError(), matcher, reason: message);
      }
    });

    test('ignores the numeric code of a cancellation DOMException', () async {
      fake
        ..errorAsAbort = true
        ..loadError = 'Decision head load was cancelled.';
      expect(await loadError(), isA<LlamaStateException>());

      fake.loadError = 'Reworded.';
      expect(await loadError(), isA<LlamaModelException>());

      fake
        ..errorCode = 'cancelled'.toJS
        ..loadError = 'Reworded.';
      expect(await loadError(), isA<LlamaStateException>());
    });

    test('drops the head on head-lost, not on the message alone', () async {
      var head = await heads.load(fake.bridge, 'a.safetensors');
      fake
        ..errorCode = 'head-lost'.toJS
        ..runError = 'Reworded.';
      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaStateException>('Reworded.'),
      );
      fake
        ..errorCode = null
        ..runError = null;
      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaStateException>(contains('on this Web runtime')),
      );

      head = await heads.load(fake.bridge, 'b.safetensors');
      fake
        ..errorCode = 'busy'.toJS
        ..runError = 'Load the decision head again.';
      await expectLater(
        heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        throwsTyped<LlamaStateException>(contains('Load the decision')),
      );
      fake
        ..errorCode = null
        ..runError = null;
      expect(
        await heads.run(fake.bridge, head.handle, [
          sequence([1], [0]),
        ]),
        hasLength(1),
      );
    });

    test('keeps redaction when classifying by code', () async {
      fake
        ..errorCode = 'model'.toJS
        ..loadError = 'Cannot read https://u:secret@example.com/h.bin?sig=abc';
      final error = await loadError() as LlamaModelException;
      expect(error.message, isNot(contains('secret')));
      expect(error.message, isNot(contains('sig=abc')));
    });
  });

  group('free', () {
    test('frees once and never reuses handles', () async {
      final first = await heads.load(fake.bridge, 'a.safetensors');
      await heads.free(fake.bridge, first.handle);
      await heads.free(fake.bridge, first.handle);
      await heads.free(fake.bridge, 42);
      final second = await heads.load(fake.bridge, 'b.safetensors');

      expect(second.handle, 2);
      expect(fake.calls.where((call) => call.startsWith('free')), ['free 7']);
      expect(fake.liveHandles, {8});
    });

    test('ignores heads of another bridge and maps failures', () async {
      final head = await heads.load(fake.bridge, 'laya-head.safetensors');
      final other = FakeDecisionBridge();
      final otherHead = await heads.load(other.bridge, 'laya-head.safetensors');
      expect(other.liveHandles, {7});

      await heads.free(other.bridge, head.handle);
      await heads.free(null, otherHead.handle);

      expect(other.calls.where((call) => call.startsWith('free')), isEmpty);
      expect(other.liveHandles, {7});
      expect(fake.calls.where((call) => call.startsWith('free')), isEmpty);
      expect(fake.liveHandles, {7});

      for (final message in [
        'Bridge has been disposed.',
        'Decision head handle must be a positive integer, got 0.',
      ]) {
        final loaded = await heads.load(fake.bridge, 'laya-head.safetensors');
        fake.freeError = message;
        await expectLater(
          heads.free(fake.bridge, loaded.handle),
          throwsTyped<LlamaStateException>(message),
          reason: message,
        );
      }
    });
  });
}
