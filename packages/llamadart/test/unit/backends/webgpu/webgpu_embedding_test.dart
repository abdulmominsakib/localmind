@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/webgpu/webgpu_backend.dart';
import 'package:test/test.dart';

import '../../../support/fake_webgpu_feature_bridge.dart';

@JS('Promise.reject')
external JSPromise<JSAny?> _reject(JSAny? reason);

void main() {
  late FakeFeatureBridge fake;
  late WebGpuLlamaBackend backend;
  late JSObject caps;
  late List<JSArray> batches;
  bool? normalize;
  int probes = 0;
  LlamaEmbeddingInput input(List<LlamaContentPart> parts) =>
      LlamaEmbeddingInput(parts);
  LlamaEmbeddingInput image() => input([
    LlamaImageContent(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAADCAIAAAA2iEnWAAAAEElEQVR4nGP4z8AARAwoFABE0AX7pM/egAAAAABJRU5ErkJggg==',
      ),
      width: 2,
      height: 3,
    ),
  ]);
  Future<List<List<double>>> run(List<LlamaEmbeddingInput> inputs) =>
      backend.embedContentWithFallback(1, inputs, normalize: false);
  JSObject error(String code) => JSObject()
    ..setProperty('code'.toJS, code.toJS)
    ..setProperty(
      'message'.toJS,
      'secret /private/path https://secret payload'.toJS,
    );

  setUp(() async {
    fake = FakeFeatureBridge();
    batches = [];
    probes = 0;
    normalize = null;
    caps = JSObject()
      ..setProperty('apiVersion'.toJS, 1.toJS)
      ..setProperty('text'.toJS, true.toJS)
      ..setProperty('image'.toJS, true.toJS)
      ..setProperty('audio'.toJS, true.toJS);
    fake.object.setProperty(
      'getEmbeddingCapabilities'.toJS,
      (() {
        probes++;
        return Future<JSObject>.value(caps).toJS;
      }).toJS,
    );
    fake.object.setProperty(
      'embedBatch'.toJS,
      ((JSArray inputs, JSObject options) {
        batches.add(inputs);
        normalize = (options.getProperty<JSBoolean>('normalize'.toJS)).toDart;
        return Future<JSAny>.value(
          [
            for (int i = 0; i < inputs.length; i++) [i.toDouble(), 0.8],
          ].jsify()!,
        ).toJS;
      }).toJS,
    );
    backend = WebGpuLlamaBackend(bridgeFactory: ([config]) => fake.bridge);
    await backend.modelLoadFromUrl(
      'https://example.com/model.gguf',
      const ModelParams(gpuLayers: 0),
    );
  });
  tearDown(() => backend.dispose());

  test(
    'runtime probe enables image and audio independently of generation',
    () async {
      final result = await backend.probeEmbeddingCapabilities(1);
      expect(result.text, isTrue);
      expect(result.image, isTrue);
      expect(result.audio, isTrue);
      expect(result.mediaUnsupportedReason, isNull);
      expect(probes, 1);
      caps.setProperty('image'.toJS, false.toJS);
      expect((await backend.probeEmbeddingCapabilities(1)).image, isFalse);
      expect((await backend.probeEmbeddingCapabilities(1)).audio, isTrue);
    },
  );

  test('unloaded and unknown contexts do no probe IO', () async {
    expect((await backend.probeEmbeddingCapabilities(99)).text, isFalse);
    await backend.dispose();
    expect((await backend.probeEmbeddingCapabilities(1)).image, isFalse);
    expect(probes, 0);
  });

  for (final field in [
    'apiVersion',
    'text',
    'image',
    'audio',
    'missing',
    'rejected',
    'null',
  ]) {
    test(
      'version skew $field leaves text available and media disabled',
      () async {
        if (field == 'missing') {
          fake.object.delete('getEmbeddingCapabilities'.toJS);
        } else if (field == 'rejected' || field == 'null') {
          fake.object.setProperty(
            'getEmbeddingCapabilities'.toJS,
            (() => field == 'null'
                    ? Future<JSAny?>.value().toJS
                    : _reject(error('EMBEDDING_CAPABILITY_UNAVAILABLE')))
                .toJS,
          );
        } else {
          caps.setProperty(field.toJS, 2.toJS);
        }
        final result = await backend.probeEmbeddingCapabilities(1);
        expect(result.text, isTrue);
        expect(result.image, isFalse);
        expect(result.audio, isFalse);
        expect(result.mediaUnsupportedReason, contains('v0.1.64+'));
        await expectLater(
          run([image()]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(
          await run([
            input([const LlamaTextContent('a'), const LlamaTextContent('b')]),
          ]),
          [
            [0, 0.8],
          ],
        );
        expect(batches.single.dartify(), ['ab']);
      },
    );
  }

  test(
    'mixed batch preserves order, encoded buffers and normalization',
    () async {
      final samples = Float32List.fromList([0, 0.25]);
      final result = await run([
        input([
          const LlamaTextContent(' a'),
          const LlamaTextContent('\n雪'),
          image().parts.single,
          LlamaAudioContent(samples: samples),
          LlamaAudioContent(bytes: Uint8List.fromList([4, 5])),
          const LlamaTextContent(' z '),
        ]),
        input([const LlamaTextContent('text')]),
      ]);
      expect(result, [
        [0, 0.8],
        [1, 0.8],
      ]);
      expect(normalize, isFalse);
      final mapped = batches.single.dartify()! as List;
      final parts = mapped.first as List;
      expect(parts[0], {'type': 'text', 'text': ' a\n雪'});
      expect(
        (parts[1] as Map)['bytes'],
        (image().parts.single as LlamaImageContent).bytes,
      );
      expect((parts[1] as Map)['type'], 'image');
      // Encoded bytes must never be inferred as raw RGB from dimensions.
      expect((parts[1] as Map).containsKey('width'), isFalse);
      expect((parts[1] as Map).containsKey('height'), isFalse);
      expect((parts[2] as Map)['samples'], [0, 0.25]);
      expect((parts[2] as Map)['type'], 'audio');
      expect((parts[3] as Map)['bytes'], [4, 5]);
      expect((parts[3] as Map)['type'], 'audio');
      expect(parts[4], {'type': 'text', 'text': ' z '});
      expect(mapped[1], 'text');
      expect(samples, [0, 0.25]);
    },
  );

  test(
    'encoded bytes are not inferred as raw RGB on a dimension-length collision',
    () async {
      final bytes = Uint8List.fromList(List.generate(18, (i) => i));
      await run([
        input([LlamaImageContent(bytes: bytes, width: 2, height: 3)]),
      ]);
      final part = (batches.single.dartify()! as List).single as List;
      expect((part.single as Map)['bytes'], bytes);
      expect((part.single as Map).containsKey('width'), isFalse);
      expect((part.single as Map).containsKey('height'), isFalse);
    },
  );

  for (final shape in [
    'primitive',
    'missing-version',
    'string-version',
    'fractional-version',
    'missing-text',
    'missing-image',
    'missing-audio',
  ]) {
    test('malformed capability shape $shape fails closed', () async {
      switch (shape) {
        case 'primitive':
          fake.object.setProperty(
            'getEmbeddingCapabilities'.toJS,
            (() => Future<JSAny?>.value(true.toJS).toJS).toJS,
          );
        case 'string-version':
          caps.setProperty('apiVersion'.toJS, '1'.toJS);
        case 'fractional-version':
          caps.setProperty('apiVersion'.toJS, 1.5.toJS);
        default:
          caps.delete(
            (shape == 'missing-version' ? 'apiVersion' : shape.substring(8))
                .toJS,
          );
      }
      final result = await backend.probeEmbeddingCapabilities(1);
      expect(result.text, isTrue);
      expect(result.image, isFalse);
      expect(result.audio, isFalse);
      expect(result.mediaUnsupportedReason, contains('v0.1.64+'));
    });
  }

  test('loading context does no embedding probe IO', () async {
    await backend.dispose();
    final gate = Completer<JSAny?>();
    final entered = Completer<void>();
    fake.object.setProperty(
      'loadModelFromUrl'.toJS,
      ((String _, JSObject _) {
        entered.complete();
        return gate.future.toJS;
      }).toJS,
    );
    final loading = backend.modelLoadFromUrl(
      'https://example.com/model.gguf',
      const ModelParams(gpuLayers: 0),
    );
    await entered.future;
    expect((await backend.probeEmbeddingCapabilities(1)).text, isFalse);
    expect(probes, 0);
    gate.complete();
    await loading;
  });

  test('old text content keeps sequential batch fallback', () async {
    fake.object.delete('getEmbeddingCapabilities'.toJS);
    fake.object.delete('embedBatch'.toJS);
    fake.object.setProperty(
      'embed'.toJS,
      ((JSString text, JSObject _) => Future<JSAny?>.value(
        [text.toDart.length].jsify(),
      ).toJS).toJS,
    );
    expect(
      await backend.embedContentBatch(1, [
        input([const LlamaTextContent('a'), const LlamaTextContent('b')]),
        input([const LlamaTextContent('c')]),
      ]),
      [
        [2],
        [1],
      ],
    );
  });

  test('direct SPI empty batch bypasses bridge and capability IO', () async {
    expect(await backend.embedContentBatch(1, []), isEmpty);
    expect(probes, 0);
    expect(batches, isEmpty);
  });

  test('direct SPI enforces whole batch modality preflight', () async {
    caps.setProperty('audio'.toJS, false.toJS);
    await expectLater(
      backend.embedContentBatch(1, [
        image(),
        input([
          LlamaAudioContent(samples: Float32List.fromList([0])),
        ]),
      ]),
      throwsA(isA<LlamaUnsupportedException>()),
    );
    expect(batches, isEmpty);
  });

  test(
    'in-flight disposal disables the capability probe immediately',
    () async {
      final gate = Completer<void>();
      fake.object.setProperty('dispose'.toJS, (() => gate.future.toJS).toJS);
      final disposal = backend.dispose();
      final result = await backend.probeEmbeddingCapabilities(1);
      expect(result.text, isFalse);
      expect(result.image, isFalse);
      expect(probes, 0);
      gate.complete();
      await disposal;
    },
  );

  test('active cancellation settles the future before reuse', () async {
    final gate = Completer<JSAny?>();
    final entered = Completer<void>();
    var cancelled = false;
    fake.object.setProperty(
      'embedBatch'.toJS,
      ((JSArray _, JSObject _) {
        entered.complete();
        return gate.future.toJS;
      }).toJS,
    );
    fake.object.setProperty(
      'cancel'.toJS,
      (() {
        cancelled = true;
      }).toJS,
    );
    final pending = run([image()]);
    final assertion = expectLater(
      pending,
      throwsA(isA<LlamaInferenceException>()),
    );
    await entered.future;
    backend.cancelGeneration();
    expect(cancelled, isTrue);
    gate.completeError(StateError('secret cancellation failure'));
    await assertion;
    fake.object.setProperty(
      'embedBatch'.toJS,
      ((JSArray _, JSObject _) => Future<JSAny>.value(
        [
          [1.0],
        ].jsify()!,
      ).toJS).toJS,
    );
    expect(await run([image()]), [
      [1.0],
    ]);
  });

  for (final route in ['media', 'text', 'sequential text fallback']) {
    test('content cancellation rejects late success through $route', () async {
      final gate = Completer<JSAny?>();
      final entered = Completer<void>();
      final sequential = route == 'sequential text fallback';
      if (sequential) {
        fake.object.setProperty('embedBatch'.toJS, null);
        fake.object.setProperty(
          'embed'.toJS,
          ((JSString _, JSObject _) {
            entered.complete();
            return gate.future.toJS;
          }).toJS,
        );
      } else {
        fake.object.setProperty(
          'embedBatch'.toJS,
          ((JSArray _, JSObject _) {
            entered.complete();
            return gate.future.toJS;
          }).toJS,
        );
      }
      final request = route == 'media'
          ? image()
          : input([const LlamaTextContent('text')]);
      final pending = run([request]);
      final assertion = expectLater(
        pending,
        throwsA(
          isA<LlamaInferenceException>().having(
            (error) => error.message.toLowerCase(),
            'message',
            contains('cancel'),
          ),
        ),
      );
      await entered.future;
      backend.cancelGeneration();
      // Published bridge cancel() is best effort. A completed native operation
      // can still resolve normally; the content adapter owns its cancellation.
      gate.complete(
        (sequential
                ? [0.6, 0.8]
                : [
                    [0.6, 0.8],
                  ])
            .jsify(),
      );
      await assertion;
      fake.object.setProperty(
        'embedBatch'.toJS,
        ((JSArray _, JSObject _) => Future<JSAny>.value(
          [
            [0.6, 0.8],
          ].jsify()!,
        ).toJS).toJS,
      );
      expect(await run([request]), [
        [0.6, 0.8],
      ]);
    });
  }

  test('dispose awaits bridge settlement of active embedding', () async {
    final gate = Completer<JSAny?>();
    final entered = Completer<void>();
    fake.object.setProperty(
      'embedBatch'.toJS,
      ((JSArray _, JSObject _) {
        entered.complete();
        return gate.future.toJS;
      }).toJS,
    );
    fake.object.setProperty('dispose'.toJS, (() => gate.future.toJS).toJS);
    final pending = run([image()]);
    final assertion = expectLater(
      pending,
      throwsA(isA<LlamaInferenceException>()),
    );
    await entered.future;
    var disposed = false;
    final disposal = backend.dispose().then((_) {
      disposed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(disposed, isFalse);
    gate.complete(
      [
        [1.0],
      ].jsify(),
    );
    await assertion;
    await disposal;
    expect(disposed, isTrue);
  });

  for (final rejection in ['primitive', 'number-code']) {
    test(
      'unknown $rejection rejection is payload-free inference failure',
      () async {
        fake.object.setProperty(
          'embedBatch'.toJS,
          ((JSArray _, JSObject _) => _reject(
            rejection == 'primitive'
                ? 'secret'.toJS
                : (JSObject()..setProperty('code'.toJS, 1.toJS)),
          )).toJS,
        );
        await expectLater(
          run([image()]),
          throwsA(
            isA<LlamaInferenceException>().having(
              (e) => e.toString(),
              'redaction',
              isNot(contains('secret')),
            ),
          ),
        );
      },
    );
  }

  test('empty batch does no IO', () async {
    expect(await run([]), isEmpty);
    expect(probes, 0);
    expect(batches, isEmpty);
  });

  for (final kind in ['image', 'audio']) {
    test('whole batch rejects disabled $kind before compute', () async {
      caps.setProperty(kind.toJS, false.toJS);
      final rejected = switch (kind) {
        'image' => image(),
        _ => input([
          LlamaAudioContent(samples: Float32List.fromList([0])),
        ]),
      };
      await expectLater(
        run([image(), rejected]),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      expect(batches, isEmpty);
    });
  }

  test('unpooled text content keeps legacy string and batch routes', () async {
    caps.setProperty('text'.toJS, false.toJS);
    caps.setProperty('image'.toJS, false.toJS);
    caps.setProperty('audio'.toJS, false.toJS);
    expect((await backend.probeEmbeddingCapabilities(1)).text, isTrue);
    final text = input([
      const LlamaTextContent('a'),
      const LlamaTextContent('b'),
    ]);
    expect(
      await run([text]),
      await backend.embedBatch(1, ['ab'], normalize: false),
    );
    fake.object.delete('embedBatch'.toJS);
    fake.object.setProperty(
      'embed'.toJS,
      ((JSString text, JSObject _) => Future<JSAny?>.value(
        [text.toDart.length].jsify(),
      ).toJS).toJS,
    );
    expect(
      (await run([text])).single,
      await backend.embed(1, 'ab', normalize: false),
    );
  });

  test(
    'unpooled mixed content rejects media before computing any input',
    () async {
      caps.setProperty('text'.toJS, false.toJS);
      caps.setProperty('image'.toJS, false.toJS);
      caps.setProperty('audio'.toJS, false.toJS);
      await expectLater(
        run([
          input([const LlamaTextContent('text')]),
          input([const LlamaTextContent('before'), image().parts.single]),
        ]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.toString(),
            'modality',
            contains('image'),
          ),
        ),
      );
      expect(batches, isEmpty);
    },
  );

  for (final modality in ['image', 'audio']) {
    test('present API explains missing model projector $modality', () async {
      caps.setProperty(modality.toJS, false.toJS);
      final reason = (await backend.probeEmbeddingCapabilities(
        1,
      )).mediaUnsupportedReason!;
      expect(reason, contains(modality));
      expect(reason, contains('model/projector'));
      expect(reason, isNot(contains('v0.1.64')));
      await expectLater(
        backend.embedContentBatch(1, [
          input([
            modality == 'image'
                ? image().parts.single
                : LlamaAudioContent(samples: Float32List(1)),
          ]),
        ]),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.toString(),
            'reason',
            contains(reason),
          ),
        ),
      );
    });
  }

  for (final marker in [
    [const LlamaTextContent('<__media__>')],
    [const LlamaTextContent('<__me'), const LlamaTextContent('dia__>')],
  ]) {
    test(
      'reserved mixed media marker matches native unsupported contract ${marker.length}',
      () async {
        await expectLater(
          run([
            input([...marker, image().parts.single]),
          ]),
          throwsA(isA<LlamaUnsupportedException>()),
        );
        expect(batches, isEmpty);
      },
    );
  }

  for (final failure in ['AbortError', 'disposed', 'worker-crash']) {
    test('probe $failure remains payload-free inference failure', () async {
      final rejection = error('UNKNOWN')
        ..setProperty('name'.toJS, failure.toJS);
      fake.object.setProperty(
        'getEmbeddingCapabilities'.toJS,
        (() => _reject(rejection)).toJS,
      );
      await expectLater(
        run([image()]),
        throwsA(
          isA<LlamaInferenceException>()
              .having(
                (e) => e.toString(),
                'redaction',
                isNot(contains('secret')),
              )
              .having(
                (e) => e.toString(),
                'no upgrade advice',
                isNot(contains('v0.1.64')),
              ),
        ),
      );
      expect(batches, isEmpty);
    });
  }

  for (final (name, value) in <(String, JSAny?)>[
    ("null", null),
    ("object", JSObject()),
    ("number", 1.toJS),
  ]) {
    test('non-callable probe $name is an unavailable API', () async {
      fake.object.setProperty('getEmbeddingCapabilities'.toJS, value);
      expect(
        (await backend.probeEmbeddingCapabilities(1)).mediaUnsupportedReason,
        contains('v0.1.64+'),
      );
    });
  }

  for (final prefix in ['RuntimeError: Aborted(', 'Aborted(']) {
    test(
      'wasm abort $prefix retains stable aborted label without diagnostics',
      () async {
        final rejection = error('UNKNOWN')
          ..setProperty(
            'message'.toJS,
            '${prefix}undefined) secret /path https://secret'.toJS,
          );
        fake.object.setProperty(
          'embedBatch'.toJS,
          ((JSArray _, JSObject _) => _reject(rejection)).toJS,
        );
        await expectLater(
          run([image()]),
          throwsA(
            isA<LlamaInferenceException>()
                .having(
                  (e) => e.toString(),
                  'stable label',
                  contains('aborted'),
                )
                .having(
                  (e) => e.toString(),
                  'redaction',
                  isNot(contains('secret')),
                ),
          ),
        );
      },
    );
  }

  test('unknown worker probe method retains version fallback', () async {
    final rejection = JSObject()
      ..setProperty('message'.toJS, 'bridge[method] is not a function'.toJS);
    fake.object.setProperty(
      'getEmbeddingCapabilities'.toJS,
      (() => _reject(rejection)).toJS,
    );
    expect(
      (await backend.probeEmbeddingCapabilities(1)).mediaUnsupportedReason,
      contains('v0.1.64+'),
    );
  });

  for (final part in <LlamaContentPart>[
    const LlamaImageContent(path: '/secret'),
    const LlamaImageContent(url: 'https://secret'),
    LlamaImageContent(bytes: Uint8List.fromList([1]), path: '/secret'),
    const LlamaAudioContent(path: '/secret'),
  ]) {
    test(
      'rejects browser media source ${part.runtimeType} ${part.toJson().keys} without disclosure',
      () async {
        await expectLater(
          run([
            image(),
            input([part]),
          ]),
          throwsA(
            isA<LlamaUnsupportedException>().having(
              (e) => e.toString(),
              'redaction',
              isNot(contains('secret')),
            ),
          ),
        );
        expect(batches, isEmpty);
      },
    );
  }

  for (final code in [
    'INVALID_EMBEDDING_INPUT',
    'EMBEDDING_CAPABILITY_UNAVAILABLE',
    'MODEL_NOT_EMBEDDING',
    'EMBEDDING_PROJECTOR_MISSING',
    'EMBEDDING_MODALITY_UNSUPPORTED',
    'EMBEDDING_INPUT_TOO_LARGE',
    'EMBEDDING_FAILED',
    'aborted',
    'UNKNOWN',
    'secret/path',
  ]) {
    test('maps $code without bridge diagnostic payloads', () async {
      fake.object.setProperty(
        'embedBatch'.toJS,
        ((JSArray _, JSObject _) => _reject(error(code))).toJS,
      );
      final Type expected = code == 'INVALID_EMBEDDING_INPUT'
          ? LlamaArgumentException
          : [
              'EMBEDDING_CAPABILITY_UNAVAILABLE',
              'MODEL_NOT_EMBEDDING',
              'EMBEDDING_PROJECTOR_MISSING',
              'EMBEDDING_MODALITY_UNSUPPORTED',
            ].contains(code)
          ? LlamaUnsupportedException
          : LlamaInferenceException;
      await expectLater(
        run([image()]),
        throwsA(
          isA<LlamaException>()
              .having((e) => e.runtimeType, 'type', expected)
              .having(
                (e) => e.toString(),
                'stable code',
                code == 'UNKNOWN' || code == 'secret/path'
                    ? isNot(contains(code))
                    : contains(code),
              )
              .having(
                (e) => e.toString(),
                'redaction',
                isNot(contains('secret')),
              ),
        ),
      );
    });
  }

  for (final dispose in [false, true]) {
    for (final rejects in [false, true]) {
      test(
        '${dispose ? 'dispose' : 'cancel'} during probe prevents dispatch rejects=$rejects',
        () async {
          final gate = Completer<JSObject>();
          fake.object.setProperty(
            'getEmbeddingCapabilities'.toJS,
            (() => gate.future.toJS).toJS,
          );
          // Direct SPI call isolates the adapter's own probe race.
          final pending = backend.probeEmbeddingCapabilities(1);
          final assertion = expectLater(
            pending,
            throwsA(isA<LlamaInferenceException>()),
          );
          if (dispose) {
            await backend.dispose();
          } else {
            backend.cancelGeneration();
          }
          if (rejects) {
            gate.completeError(StateError('secret probe failure'));
          } else {
            gate.complete(caps);
          }
          await assertion;
          expect(batches, isEmpty);
        },
      );
    }
  }
}
