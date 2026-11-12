@TestOn('vm && (mac-os || linux)')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime_client_contract.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver.dart';
import 'package:llamadart/src/core/speech/litert_lm_speech_to_text_driver_io.dart';
import 'package:test/test.dart';

import '../../../../tool/litert_lm_asr_smoke.dart' as smoke;

LiteRtLmRuntimeClientContract _v1SpeechClient(String? path) =>
    LiteRtLmV1RuntimeClient(DynamicLibrary.open(path!));

final _config = LiteRtLmAsrRuntimeConfig.source(
  model: ModelSource.path('/fixture/speech.litertlm'),
  tokenizer: ModelSource.path('/fixture/tokenizer.json'),
  modelPreset: LiteRtLmAsrModelPreset.moonshineTiny,
  numberOfThreads: 2,
  maxBufferedAudio: const Duration(seconds: 15),
  overlapRatio: 0.25,
);

void main() {
  late Directory directory;
  late DynamicLibrary library;
  late String path;
  late DynamicLibrary missing;
  late String missingPath;
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void fault(int value) =>
      library.lookupFunction<Void Function(Int), void Function(int)>(
        'fixture_asr_fault',
      )(value);
  LiteRtLmV1RuntimeClient client([DynamicLibrary? selected]) {
    final value = LiteRtLmV1RuntimeClient(selected ?? library);
    addTearDown(value.dispose);
    return value;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('litert_v1_asr_');
    for (final omit in [false, true]) {
      final output =
          '${directory.path}/${omit ? 'missing' : 'asr'}.${Platform.isMacOS ? 'dylib' : 'so'}';
      final compile = await Process.run('cc', [
        '-shared',
        '-fPIC',
        '-pthread',
        if (omit) '-DOMIT_ASR_CANCEL',
        'test/fixtures/litert_lm/c_api_v1_asr.c',
        '-o',
        output,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
      if (omit) {
        missingPath = output;
        missing = DynamicLibrary.open(output);
      } else {
        path = output;
        library = DynamicLibrary.open(output);
      }
    }
  });
  tearDownAll(() => directory.delete(recursive: true));
  setUp(() => fault(0));
  tearDown(() {
    fault(0);
    expect(count('asr_engines'), 0);
    expect(count('asr_sessions'), 0);
    expect(count('asr_strings'), 0);
    expect(count('asr_results'), 0);
    expect(
      count('live'),
      0,
      reason: 'ASR must never create a text core engine',
    );
  });
  test(
    'ELF global exports cannot bypass fixture string ownership accounting',
    () async {
      final executable = '${directory.path}/asr_elf_ownership_probe';
      final compile = await Process.run('cc', [
        '-std=c11',
        '-rdynamic',
        'test/fixtures/litert_lm/asr_elf_ownership_probe.c',
        '-ldl',
        '-o',
        executable,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
      final result = await Process.run(executable, [path]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains('strings=0 results=0 engines=0 sessions=0 collision_calls=0'),
      );
    },
    skip: !Platform.isLinux
        ? 'ELF symbol interposition is Linux-specific'
        : false,
  );
  test(
    'actual loaded v1 admits independent ASR without legacy core binding',
    () {
      expect(client().supportsAsrBridge, isTrue);
      expect(
        LiteRtLmRuntimeClient(libraryPath: path).supportsAsrBridge,
        isTrue,
      );
    },
  );
  for (final bad in [1, 2, 3]) {
    test('ASR ABI/layout skew $bad refuses before allocation', () {
      fault(bad);
      final active = client();
      expect(active.supportsAsrBridge, isFalse);
      expect(
        () => active.createAsrSession(_config),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    });
  }
  test('missing required ASR symbol refuses actual partial bridge', () {
    final active = client(missing);
    expect(active.supportsAsrBridge, isFalse);
    expect(
      () => active.createAsrSession(_config),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
  test('preset, paths and configuration reach independent bridge', () {
    final session = client().createAsrSession(_config);
    addTearDown(session.dispose);
    expect(count('asr_preset'), 3);
    expect(count('asr_backend'), 0);
    expect(count('asr_threads'), 2);
    expect(count('asr_buffers'), 15000);
    expect(
      library.lookupFunction<Float Function(), double Function()>(
        'fixture_asr_overlap',
      )(),
      0.25,
    );
    for (final entry in {
      'model': '/fixture/speech.litertlm',
      'tokenizer': '/fixture/tokenizer.json',
    }.entries) {
      expect(
        library
            .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
              'fixture_asr_${entry.key}',
            )()
            .toDartString(),
        entry.value,
      );
    }
    expect(
      count('asr_engines'),
      0,
      reason: 'Session retains native resources after engine deletion',
    );
  });
  test('partial PCM, copied text, finalization, reset and cancellation', () {
    final session = client().createAsrSession(_config);
    addTearDown(session.dispose);
    final pushed = session.pushAudio(Float32List.fromList([1, 2, 3, 4]));
    expect(pushed.acceptedSamples, 3);
    expect(pushed.wouldBlock, isTrue);
    final result = session.processNext();
    expect(result.confirmedText, 'part');
    expect(result.unconfirmedText, 'pending');
    expect(count('asr_strings'), 0);
    expect(count('asr_results'), 0);
    expect(session.processNext().state, LiteRtLmAsrProcessState.needsMoreAudio);
    expect(
      result.confirmedText,
      'part',
      reason: 'Native release poisons owned text',
    );
    session.finishAudio();
    final finished = session.processNext();
    expect(finished.confirmedText, 'final café');
    expect(finished.isFinal, isTrue);
    expect(session.processNext().state, LiteRtLmAsrProcessState.endOfStream);
    session.reset();
    expect(session.processNext().state, LiteRtLmAsrProcessState.needsMoreAudio);
    session.cancel();
    expect(session.processNext, throwsA(isA<LlamaSpeechException>()));
  });
  for (final bad in [4, 5, 6, 7, 8]) {
    test('creation failure $bad releases every partial native owner', () {
      fault(bad);
      expect(
        () => client().createAsrSession(_config),
        throwsA(
          bad == 7 || bad == 8
              ? isA<LlamaSpeechException>().having(
                  (error) => error.message,
                  'message',
                  contains('returned no owner on success'),
                )
              : isA<LlamaSpeechException>(),
        ),
      );
    });
  }
  for (final bad in [9, 10, 11, 12, 13, 14]) {
    test('session failure $bad releases owned result and error strings', () {
      final session = client().createAsrSession(_config);
      addTearDown(session.dispose);
      fault(bad);
      final call = switch (bad) {
        9 || 10 => () => session.pushAudio(Float32List(4)),
        11 => session.processNext,
        12 => session.cancel,
        13 => session.reset,
        _ => session.finishAudio,
      };
      expect(call, throwsA(isA<LlamaSpeechException>()));
      expect(count('asr_strings'), 0);
      expect(count('asr_results'), 0);
    });
  }
  test(
    'ASR session keeps independent library alive after v1 client disposal',
    () {
      final active = client();
      final session = active.createAsrSession(_config);
      addTearDown(session.dispose);
      active.dispose();
      expect(active.supportsAsrBridge, isFalse);
      expect(
        () => active.createAsrSession(_config),
        throwsA(isA<LlamaStateException>()),
      );
      expect(
        session.processNext().state,
        LiteRtLmAsrProcessState.needsMoreAudio,
      );
      session.dispose();
      session.dispose();
      expect(() => session.pushAudio(Float32List(1)), throwsStateError);
    },
  );
  test(
    'actual speech probe and isolate worker use selected v1 bridge',
    () async {
      final driver = createLiteRtLmSpeechToTextDriverWithRuntime(
        _v1SpeechClient,
      );
      expect(
        (await driver.probeSupport(libraryPath: path)).isSupported,
        isTrue,
      );
      final worker = await driver.start(_config, libraryPath: path);
      final updates = <String>[];
      final subscription = worker.updates.listen(
        (u) => updates.add(u.confirmedText),
      );
      try {
        expect(
          await worker.pushAudio(Float32List.fromList([1, 2, 3, 4, 5, 6, 7])),
          7,
        );
        expect(await worker.finish(), 'part part part final café');
        expect(updates.last, 'part part part final café');
      } finally {
        await worker.dispose();
        await subscription.cancel();
      }
    },
  );
  test('ASR smoke forwards its explicit library and thread count', () async {
    final model = File('${directory.path}/smoke.litertlm')
      ..writeAsStringSync('model-free ASR fixture');
    final tokenizer = File('${directory.path}/smoke-tokenizer.json')
      ..writeAsStringSync('{}');
    final wav = Uint8List(52);
    final header = ByteData.sublistView(wav);
    void tag(int offset, String value) =>
        wav.setRange(offset, offset + value.length, ascii.encode(value));
    tag(0, 'RIFF');
    header.setUint32(4, 44, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 16000, Endian.little);
    header.setUint32(28, 32000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    header.setUint32(40, 8, Endian.little);
    final audio = File('${directory.path}/smoke.wav')..writeAsBytesSync(wav);
    debugLiteRtLmSpeechToTextDriverOverride =
        createLiteRtLmSpeechToTextDriverWithRuntime(_v1SpeechClient);
    addTearDown(() => debugLiteRtLmSpeechToTextDriverOverride = null);
    final observations = <Map<String, Object?>>[];
    await smoke.runLiteRtLmAsrSmoke(
      [model.path, tokenizer.path, audio.path, 'moonshine-tiny', 'final café'],
      libraryPath: path,
      numberOfThreads: 2,
      onObservation: observations.add,
    );
    expect(observations.map((row) => row['phase']), [
      'stream',
      'task',
      'cancel',
    ]);
    expect(observations.first['transcript'], contains('final café'));
    observations.clear();
    await expectLater(
      smoke.runLiteRtLmAsrSmoke(
        [
          model.path,
          tokenizer.path,
          audio.path,
          'moonshine-tiny',
          'absent-oracle-phrase',
        ],
        libraryPath: path,
        numberOfThreads: 2,
        onObservation: observations.add,
      ),
      throwsStateError,
    );
    expect(observations.single['phase'], 'stream');
    expect(observations.single['transcript'], contains('final café'));

    expect(count('asr_threads'), 2);
    expect(count('asr_engines'), 0);
    expect(count('asr_sessions'), 0);
  });
  test(
    'public speech model dispatch reaches injected v1 worker and settles',
    () async {
      final model = File('${directory.path}/speech.litertlm')
        ..writeAsStringSync('model-free ASR fixture');
      final tokenizer = File('${directory.path}/tokenizer.json')
        ..writeAsStringSync('{}');
      debugLiteRtLmSpeechToTextDriverOverride =
          createLiteRtLmSpeechToTextDriverWithRuntime(_v1SpeechClient);
      addTearDown(() => debugLiteRtLmSpeechToTextDriverOverride = null);
      final recognizer = await SpeechToTextEngine.load(
        SpeechToTextModel(
          ModelSource.path(model.path),
          tokenizer: ModelSource.path(tokenizer.path),
          adapter: LiteRtLmAsrAdapter(
            LiteRtLmAsrModelPreset.moonshineTiny,
            libraryPath: path,
            numberOfThreads: 2,
          ),
        ),
      );
      addTearDown(recognizer.dispose);
      expect((await recognizer.capabilities).isSupported, isTrue);
      final request = SpeechToTextRequest(
        audio: SpeechAudioPcmInput(Float32List(4)),
      );
      expect(
        (await recognizer.transcribeOnce(request)).text,
        'part part final café',
      );
      final cancelled = await recognizer.transcribe(request);
      cancelled.cancel();
      expect(
        (await cancelled.done).state,
        SpeechToTextCompletionState.cancelled,
      );
    },
  );
  test(
    'partial bridge worker failure settles without update listener',
    () async {
      final driver = createLiteRtLmSpeechToTextDriverWithRuntime(
        _v1SpeechClient,
      );
      expect(
        (await driver.probeSupport(libraryPath: missingPath)).isSupported,
        isFalse,
      );
      await expectLater(
        driver
            .start(_config, libraryPath: missingPath)
            .timeout(const Duration(seconds: 3)),
        throwsA(isA<LlamaSpeechException>()),
      );
    },
  );
  test(
    'worker initialization error and retry release the selected runtime',
    () async {
      final driver = createLiteRtLmSpeechToTextDriverWithRuntime(
        _v1SpeechClient,
      );
      fault(6);
      await expectLater(
        driver.start(_config, libraryPath: path),
        throwsA(isA<LlamaSpeechException>()),
      );
      fault(0);
      final worker = await driver.start(_config, libraryPath: path);
      await worker.cancel();
      await worker.dispose();
      await worker.dispose();
    },
  );
}
