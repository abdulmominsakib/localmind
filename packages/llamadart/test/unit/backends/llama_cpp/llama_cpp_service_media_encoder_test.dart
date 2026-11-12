@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_backend.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/backends/llama_cpp/worker.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:llamadart/src/hook/native_release_pins.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(gpuLayers: 0, contextSize: 64);
const _greedy = GenerationParams(maxTokens: 1, temp: 0, topK: 1, seed: 1);

Uint8List _bytes(String head) =>
    Uint8List.fromList('$head${'\x00' * 16}'.codeUnits);

// What mtmd reads as audio, by the first bytes.
final Uint8List _wav = _bytes('RIFF\x24\x00\x00\x00WAVEfmt ');
final Uint8List _mp3 = _bytes('\xff\xfb\x90\x00');
final Uint8List _id3 = _bytes('ID3\x03\x00');
final Uint8List _flac = _bytes('fLaC\x00\x00\x00\x22');

// Image formats by their magic.
final Uint8List _png = _bytes('\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR');
final Uint8List _jpeg = _bytes('\xff\xd8\xff\xe0\x00\x10JFIF');
final Uint8List _gif = _bytes('GIF89a');
final Uint8List _bmp = _bytes('BM');

// Neither to mtmd, which tries them as images and fails.
final Uint8List _m4a = _bytes('\x00\x00\x00\x20ftypM4A ');
final Uint8List _ogg = _bytes('OggS');
final Uint8List _webp = _bytes('RIFF\x24\x00\x00\x00WEBPVP8 ');
final Uint8List _tiff = _bytes('II*\x00');
final Uint8List _random = _bytes('\x12\x34\x56\x78\x9a\xbc');
// Audio magic in fewer than the 12 bytes mtmd asks for.
final Uint8List _shortFlac = Uint8List.fromList('fLaC'.codeUnits);

Matcher _noEncoder(String kind) => throwsA(
  isA<LlamaUnsupportedException>().having(
    (e) => e.message,
    'message',
    '$kind input is not supported by the loaded multimodal projector: it has '
        'no ${kind.toLowerCase()} encoder. Load a projector that has one, or '
        'leave ${kind.toLowerCase()} input out of the request.',
  ),
);

Matcher _untyped(String text) => throwsA(
  isA<Exception>()
      .having((e) => e, 'type', isNot(isA<LlamaException>()))
      .having((e) => '$e', 'text', 'Exception: $text'),
);

// Runs the real llama.cpp runtime on the CPU with a fake projector whose
// encoders, bitmap loading and tokenize result each test sets.
void main() {
  late Directory dir;
  late LlamaCppService service;
  late FakeMtmd fake;
  late int context;

  void attach({required bool vision, required bool audio, Abi? abi}) {
    dir = Directory.systemTemp.createTempSync('llamadart_media_encoder_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final modelPath = writeSyntheticLlamaGguf('${dir.path}/model.gguf').path;
    service = LlamaCppService(
      objectCalls: LlamaCppObjectCalls.upstream,
      abi: abi,
    )..initializeBackend();
    final model = service.loadModel(modelPath, _params);
    fake = FakeMtmd.install(
      service,
      tokens: service.tokenize(model, 'ab', true),
      vision: vision,
      audio: audio,
    );
    addTearDown(fake.dispose);
    addTearDown(service.dispose);
    context = service.createContext(model, _params);
    final projectorPath = '${dir.path}/mmproj.gguf';
    File(projectorPath).writeAsStringSync('GGUF');
    service.createMultimodalContext(model, projectorPath);
    fake.calls.clear();
  }

  String file(String name, List<int> bytes) =>
      (File('${dir.path}/$name')..writeAsBytesSync(bytes)).path;

  Future<void> send(List<LlamaContentPart> parts) async {
    final cancel = calloc<Int8>();
    try {
      await service
          .generate(
            context,
            '<__media__>' * parts.length,
            _greedy,
            cancel.address,
            parts: parts,
          )
          .drain<void>();
    } finally {
      calloc.free(cancel);
    }
  }

  group('video input without native video support', () {
    Matcher rejection(Matcher platform, Matcher absent) => throwsA(
      isA<LlamaUnsupportedException>()
          .having((e) => e.message, 'platform', platform)
          .having((e) => e.message, 'absent', absent)
          .having((e) => e.message, 'frames', contains('image frames')),
    );

    for (final (abi, name) in [
      (Abi.androidArm, 'Android'),
      (Abi.androidArm64, 'Android'),
      (Abi.androidIA32, 'Android'),
      (Abi.androidX64, 'Android'),
      (Abi.androidRiscv64, 'Android'),
      (Abi.iosArm64, 'iOS'),
      (Abi.iosX64, 'iOS'),
    ]) {
      test(
        'names $name and its disabled LLAMA_SUBPROCESS build ($abi)',
        () async {
          attach(vision: true, audio: false, abi: abi);

          await expectLater(
            send([LlamaVideoContent(path: '/tmp/clip.mp4')]),
            rejection(
              allOf(
                contains('unavailable on $name'),
                contains('LLAMA_SUBPROCESS'),
              ),
              allOf(isNot(contains(llamaCppTag)), isNot(contains('projector'))),
            ),
          );
        },
      );
    }

    for (final abi in [Abi.macosArm64, Abi.linuxX64, Abi.windowsX64]) {
      test('blames the projector before the runtime on $abi', () async {
        attach(vision: true, audio: false, abi: abi);

        await expectLater(
          send([LlamaVideoContent(path: '/tmp/clip.mp4')]),
          rejection(
            allOf(
              contains('pinned $llamaCppTag macOS, Linux and Windows'),
              contains('no vision encoder; load a vision projector'),
              contains('LLAMA_SUBPROCESS/MTMD_VIDEO'),
              contains('FFmpeg/ffprobe'),
            ),
            allOf(isNot(contains('Android')), isNot(contains('iOS'))),
          ),
        );
      });
    }
  });

  group('a projector with a vision encoder only', () {
    setUp(() => attach(vision: true, audio: false));

    test('names the audio encoder when mtmd cannot load encoded audio, '
        'whatever the type of the part', () async {
      fake.encodedBitmapLoads = false;

      for (final audio in [_wav, _mp3, _id3, _flac]) {
        await expectLater(
          send([LlamaAudioContent(bytes: audio)]),
          _noEncoder('Audio'),
        );
      }
      await expectLater(
        send([LlamaAudioContent(path: file('clip.wav', _wav))]),
        _noEncoder('Audio'),
      );
      await expectLater(
        send([LlamaImageContent(bytes: _wav)]),
        _noEncoder('Audio'),
      );
      await expectLater(
        send([LlamaAudioContent(bytes: _wav), LlamaImageContent(bytes: _png)]),
        _noEncoder('Audio'),
      );
      expect(fake.calls, isNot(contains('mtmd_tokenize')));
    });

    test('names the audio encoder when mtmd refuses PCM samples', () async {
      fake.tokenizeResult = 2;

      await expectLater(
        send([LlamaAudioContent(samples: Float32List(1))]),
        _noEncoder('Audio'),
      );
      expect(fake.calls, contains('mtmd_tokenize'));
    });

    test('hands mtmd an image sent as an audio part, by bytes and by '
        'path', () async {
      await send([LlamaAudioContent(bytes: _png)]);
      await send([LlamaAudioContent(path: file('page.png', _png))]);

      expect(fake.calls.where((call) => call == 'mtmd_tokenize'), hasLength(2));
      expect(fake.evaluations, 2);
    });

    test('keeps the load error of a source mtmd does not read as '
        'audio', () async {
      fake.encodedBitmapLoads = false;

      for (final part in [
        LlamaAudioContent(bytes: _png),
        LlamaAudioContent(bytes: _m4a),
        LlamaAudioContent(bytes: _ogg),
        LlamaAudioContent(bytes: _webp),
        LlamaAudioContent(bytes: _random),
        LlamaAudioContent(bytes: _shortFlac),
        LlamaAudioContent(path: file('note.m4a', _m4a)),
        LlamaImageContent(bytes: _tiff),
        LlamaImageContent(path: '${dir.path}/missing.png'),
      ]) {
        await expectLater(
          send([part]),
          _untyped('Failed to load media part 0'),
        );
      }
    });

    test('keeps the tokenize error of an image request', () async {
      fake.tokenizeResult = 2;

      await expectLater(
        send([LlamaImageContent(bytes: _png)]),
        _untyped('mtmd_tokenize failed: 2'),
      );
    });
  });

  group('a projector with an audio encoder only', () {
    setUp(() => attach(vision: false, audio: true));

    test('names the image encoder when mtmd refuses an image, whatever the '
        'type of the part', () async {
      fake.tokenizeResult = 2;

      await expectLater(
        send([LlamaImageContent(bytes: _png)]),
        _noEncoder('Image'),
      );
      await expectLater(
        send([LlamaImageContent(path: file('page.png', _png))]),
        _noEncoder('Image'),
      );
      for (final image in [_png, _jpeg, _gif, _bmp]) {
        await expectLater(
          send([LlamaAudioContent(bytes: image)]),
          _noEncoder('Image'),
        );
      }
      await expectLater(
        send([LlamaAudioContent(bytes: _wav), LlamaImageContent(bytes: _png)]),
        _noEncoder('Image'),
      );
    });

    test('names the image encoder for an image part mtmd cannot '
        'decode', () async {
      fake.encodedBitmapLoads = false;

      await expectLater(
        send([LlamaImageContent(bytes: _tiff)]),
        _noEncoder('Image'),
      );
      await expectLater(
        send([LlamaImageContent(path: file('page.tiff', _tiff))]),
        _noEncoder('Image'),
      );
    });

    test('keeps the load error of an audio part mtmd does not read as audio '
        'and of a source it cannot read', () async {
      fake.encodedBitmapLoads = false;

      for (final part in [
        LlamaAudioContent(bytes: _m4a),
        LlamaAudioContent(path: file('note.m4a', _m4a)),
        LlamaAudioContent(path: file('note.wav', _m4a)),
        LlamaAudioContent(bytes: _ogg),
        LlamaAudioContent(bytes: _webp),
        LlamaAudioContent(bytes: _random),
        LlamaAudioContent(bytes: _shortFlac),
        LlamaAudioContent(bytes: Uint8List(0)),
        LlamaAudioContent(path: '${dir.path}/missing.wav'),
        LlamaImageContent(path: '${dir.path}/missing.png'),
      ]) {
        await expectLater(
          send([part]),
          _untyped('Failed to load media part 0'),
        );
      }
    });

    test('hands mtmd audio sent as an image part, by bytes and by '
        'path', () async {
      await send([LlamaImageContent(bytes: _wav)]);
      await send([LlamaImageContent(path: file('clip.wav', _wav))]);

      expect(fake.calls.where((call) => call == 'mtmd_tokenize'), hasLength(2));
      expect(fake.evaluations, 2);
    });

    test('keeps the errors of an audio request', () async {
      fake.tokenizeResult = 2;
      await expectLater(
        send([LlamaAudioContent(samples: Float32List(1))]),
        _untyped('mtmd_tokenize failed: 2'),
      );

      fake
        ..tokenizeResult = 0
        ..encodedBitmapLoads = false;
      await expectLater(
        send([LlamaAudioContent(bytes: _wav)]),
        _untyped('Failed to load media part 0'),
      );
    });
  });

  test('a runtime without mtmd fails a media request as unsupported, also '
      'through the worker, and serves it once mtmd is back', () async {
    attach(vision: true, audio: true);
    final unsupported = throwsA(
      isA<LlamaUnsupportedException>().having(
        (e) => e.message,
        'message',
        contains('`mtmd_input_chunks_init` cannot run'),
      ),
    );
    final parts = [LlamaImageContent(bytes: _png)];
    fake.setFallback(present: false);
    // The projector is freed through the fallback.
    addTearDown(() => fake.setFallback(present: true));

    await expectLater(send(parts), unsupported);

    final workerPort = ReceivePort();
    runLlamaWorkerForTesting(
      workerPort.sendPort,
      service,
      exitOnDispose: false,
    );
    final backend = NativeLlamaBackend(
      initialSendPort: await workerPort.first as SendPort,
    );
    Future<void> sendThroughWorker() => backend
        .generate(context, '<__media__>', _greedy, parts: parts)
        .drain<void>();
    try {
      await expectLater(sendThroughWorker(), unsupported);

      fake.setFallback(present: true);
      await sendThroughWorker();
      expect(fake.calls, contains('mtmd_tokenize'));
      expect(fake.evaluations, 1);
    } finally {
      fake.setFallback(present: true);
      await backend.dispose();
    }
  });

  test('a runtime without the mtmd encoder probe leaves the mtmd error as it '
      'is', () {
    attach(vision: false, audio: false);
    final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
    Object? missingEncoder() => reflect(service).invoke(
      MirrorSystem.getSymbol('_missingEncoderFor', owner),
      [
        FakeMtmd.projector,
        <LlamaContentPart>[
          LlamaImageContent(bytes: _png),
          LlamaAudioContent(samples: Float32List(1)),
        ],
      ],
    ).reflectee;

    expect(missingEncoder(), isA<LlamaUnsupportedException>());
    fake.setFallback(present: false);
    // The projector is freed through the fallback.
    addTearDown(() => fake.setFallback(present: true));
    expect(missingEncoder(), isNull);
  });
}
