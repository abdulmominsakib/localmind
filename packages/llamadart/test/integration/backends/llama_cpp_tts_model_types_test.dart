@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:test/test.dart';

import '../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  device: ComputeDevice.cpu,
  gpuLayers: 0,
  contextSize: 64,
);
const _qwen3 = 1;
const _lfm3 = 2;
const _soprano = 3;
const _chatterbox = 4;
const _pocketTts = 5;
const _voiceCapability = 4;
const _languageCapability = 1;

void main() {
  late _Harness h;
  setUp(() => h = _Harness());
  tearDown(() => h.dispose());

  group('a runtime with the model-type opt-in', () {
    test('accepts the types this core drives and the runtime builds', () {
      h.runtimeTypes = 0x3e;
      h.reportedType = _soprano;

      final capabilities = h.capabilities();

      expect(capabilities.isSupported, isTrue);
      expect(capabilities.model, BackendTextToSpeechModel.soprano);
      expect(h.acceptedMasks.toSet(), {0x3e});
      expect(capabilities.supportsVoice, isFalse);
      expect(capabilities.voices, isEmpty);
      expect(h.legacyInfoCalls, 0);
    });

    test('lists predefined voices in order', () {
      h.reportedType = _lfm3;
      h.model = h.ttsModel;
      h.reportedCapabilities = _voiceCapability | _languageCapability;
      h.voices = ['female', 'male'];

      final capabilities = h.capabilities();

      expect(capabilities.isSupported, isTrue, reason: capabilities.reason);
      expect(capabilities.model, BackendTextToSpeechModel.lfm3Audio);
      expect(capabilities.supportsLanguage, isTrue);
      expect(capabilities.supportsVoice, isTrue);
      expect(capabilities.voices, ['female', 'male']);
      expect(() => capabilities.voices.add('x'), throwsUnsupportedError);
    });

    test('reports voice selection without listing on a runtime before the '
        'voice API', () {
      h.reportedType = _lfm3;
      h.model = h.ttsModel;
      h.reportedCapabilities = _voiceCapability;
      h.voices = null;

      final capabilities = h.capabilities();

      expect(capabilities.supportsVoice, isTrue);
      expect(capabilities.voices, isEmpty);
    });

    test('refuses LFM3-Audio on a model without a tts chat template', () {
      h.reportedType = _lfm3;

      final capabilities = h.capabilities();

      expect(capabilities.isSupported, isFalse);
      expect(capabilities.reason, contains('no `tts` chat template'));
    });

    test('names the generators a runtime cannot drive with the release '
        'that adds them', () {
      h.runtimeTypes = 0xe;
      h.reportedType = 0;
      h.infoStatus =
          llama_dart_tts_status.LLAMA_DART_TTS_STATUS_UNSUPPORTED.value;

      final capabilities = h.capabilities();

      expect(capabilities.isSupported, isFalse);
      expect(h.acceptedMasks.toSet(), {0xe});
      expect(
        capabilities.reason,
        contains(
          'cannot drive Chatterbox (llamadart-native v0.9.0), '
          'Pocket TTS (llamadart-native v0.9.0)',
        ),
      );
    });

    test('refuses Chatterbox Multilingual on a one-sequence context', () {
      h.reportedType = _chatterbox;
      h.reportedCapabilities = _languageCapability | _voiceCapability;
      h.voices = ['default'];

      final capabilities = h.capabilities();

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.reason,
        allOf(
          contains('maxParallelSequences of at least 2'),
          contains('this context has 1'),
        ),
      );
    });

    test('accepts Chatterbox Multilingual with its guidance sequence', () {
      h.reportedType = _chatterbox;
      h.reportedCapabilities = _languageCapability | _voiceCapability;
      h.voices = ['default'];
      h.sequences = 2;

      final capabilities = h.capabilities();

      expect(capabilities.isSupported, isTrue, reason: capabilities.reason);
      expect(capabilities.model, BackendTextToSpeechModel.chatterbox);
      expect(capabilities.supportsLanguage, isTrue);
      expect(capabilities.voices, ['default']);
    });

    test('accepts Chatterbox Turbo and Pocket TTS on one sequence', () {
      h.reportedType = _chatterbox;
      h.reportedCapabilities = _voiceCapability;
      expect(h.capabilities().isSupported, isTrue);

      h.reportedType = _pocketTts;
      final pocket = h.capabilities();
      expect(pocket.isSupported, isTrue);
      expect(pocket.model, BackendTextToSpeechModel.pocketTts);
    });

    test('tells which models it drives without a loaded model', () {
      h.runtimeTypes = 0x6;
      h.capabilities();

      String? reason(BackendTextToSpeechModel model) =>
          h.service.textToSpeechModelUnsupportedReason(model);
      expect(reason(BackendTextToSpeechModel.qwen3Tts), isNull);
      expect(reason(BackendTextToSpeechModel.lfm3Audio), isNull);
      expect(
        reason(BackendTextToSpeechModel.soprano),
        allOf(
          contains('cannot drive Soprano speech output'),
          contains('llamadart-native v0.8.0'),
        ),
      );
      expect(
        reason(BackendTextToSpeechModel.chatterbox),
        allOf(
          contains('cannot drive Chatterbox speech output'),
          contains('llamadart-native v0.9.0'),
        ),
      );
      expect(
        reason(BackendTextToSpeechModel.pocketTts),
        contains('llamadart-native v0.9.0'),
      );
    });

    test('passes the mask to init and the voice to start', () async {
      h.reportedType = _lfm3;
      h.model = h.ttsModel;

      await h.synthesize(voice: 'male');

      expect(h.initMasks, [0x3e]);
      expect(h.startedVoices, ['male']);
      expect(h.legacyInitCalls, 0);
      expect(h.legacyStartCalls, 0);
    });

    test('starts without a voice through the plain start', () async {
      await h.synthesize();

      expect(h.initMasks, [0x3e]);
      expect(h.legacyStartCalls, 1);
      expect(h.startedVoices, isEmpty);
    });
  });

  group('a runtime without the model-type opt-in', () {
    setUp(() => h.withoutOptIn = true);

    test('drives Qwen3-TTS through the legacy calls', () async {
      final capabilities = h.capabilities();
      expect(capabilities.isSupported, isTrue);
      expect(capabilities.model, BackendTextToSpeechModel.qwen3Tts);
      expect(capabilities.supportsVoice, isFalse);
      expect(h.legacyInfoCalls, 1);

      await h.synthesize();
      expect(h.legacyInitCalls, 1);
      expect(h.initMasks, isEmpty);
    });

    test('refuses other projectors naming the required runtime', () {
      h.reportedType = 0;
      h.infoStatus =
          llama_dart_tts_status.LLAMA_DART_TTS_STATUS_UNSUPPORTED.value;

      final capabilities = h.capabilities();

      expect(capabilities.isSupported, isFalse);
      expect(
        capabilities.reason,
        allOf(
          contains('Qwen3-TTS only'),
          contains('llama_dart_tts_init_ext'),
          contains('llamadart-native v0.8.0'),
          contains('Chatterbox and Pocket TTS: v0.9.0'),
        ),
      );
    });

    test('refuses other models without a loaded model', () {
      h.capabilities();

      expect(
        h.service.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.qwen3Tts,
        ),
        isNull,
      );
      expect(
        h.service.textToSpeechModelUnsupportedReason(
          BackendTextToSpeechModel.lfm3Audio,
        ),
        allOf(
          contains('LFM3-Audio speech output needs'),
          contains('llama_dart_tts_init_ext'),
          contains('llamadart-native v0.8.0'),
        ),
      );
    });

    test('refuses a voice before creating a task', () async {
      await expectLater(
        h.synthesize(voice: 'male'),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            contains('llama_dart_tts_start_with_voice'),
          ),
        ),
      );
      expect(h.legacyInitCalls, 0);
    });
  });
}

extension on BackendTextToSpeechCapabilities {
  String? get reason => unsupportedReason;
}

class _Harness {
  final directory = Directory.systemTemp.createTempSync('tts_model_types_');
  final service = LlamaCppService()..initializeBackend();
  final flag = calloc<Int8>();
  late final int plainModel;
  late final int ttsModel;
  late int model;
  final Map<int, int> contexts = {};
  late final InstanceMirror mirror;
  late final LibraryMirror library;
  late final Map projectors;
  late final Map modelProjectors;

  bool withoutOptIn = false;
  int runtimeTypes = 0x3f;
  int sequences = 1;
  int reportedType = _qwen3;
  int reportedCapabilities = 0;
  int infoStatus = 0;
  List<String>? voices = const [];
  int legacyInfoCalls = 0;
  int legacyInitCalls = 0;
  int legacyStartCalls = 0;
  final acceptedMasks = <int>[];
  final initMasks = <int>[];
  final startedVoices = <String>[];

  Symbol symbol(String name) => MirrorSystem.getSymbol(name, library);

  _Harness() {
    final plainPath = '${directory.path}/model.gguf';
    writeSyntheticLlamaGguf(plainPath);
    plainModel = service.loadModel(plainPath, _params);
    final ttsPath = '${directory.path}/tts-model.gguf';
    writeSyntheticLlamaGguf(
      ttsPath,
      stringMetadata: const {'tokenizer.chat_template.tts': '{{ text }}'},
    );
    ttsModel = service.loadModel(ttsPath, _params);
    model = plainModel;
    library = reflectClass(LlamaCppService).owner as LibraryMirror;
    mirror = reflect(service);
    projectors = mirror.getField(symbol('_mtmdContexts')).reflectee as Map;
    modelProjectors = mirror.getField(symbol('_modelToMtmd')).reflectee as Map;
  }

  int _context() => contexts.putIfAbsent(model, () {
    final context = service.createContext(
      model,
      _params.copyWith(maxParallelSequences: sequences),
    );
    projectors[900 + model] = Pointer<mtmd_context>.fromAddress(1);
    modelProjectors[model] = 900 + model;
    return context;
  });

  void _installApi() {
    mirror.setField(symbol('_ttsApi'), null);
    mirror.setField(symbol('_ttsApiLookupAttempted'), false);
    final original = mirror.invoke(symbol('_resolveTtsApi'), []);
    final fields = <Symbol, dynamic>{
      for (final field
          in original.type.declarations.values.whereType<VariableMirror>())
        if (!field.isStatic)
          field.simpleName: original.getField(field.simpleName).reflectee,
    };
    int fillInfo(Pointer<llama_dart_tts_info> info) {
      info.ref.model_type = reportedType;
      info.ref.capabilities = reportedCapabilities;
      info.ref.sample_rate = 24000;
      info.ref.channels = 1;
      return infoStatus;
    }

    fields[#getInfo] =
        (Pointer<mtmd_context> mtmd, Pointer<llama_dart_tts_info> info) {
          legacyInfoCalls++;
          return fillInfo(info);
        };
    fields[#init] =
        (Pointer<llama_context> c, Pointer<mtmd_context> m, Pointer<Int32> s) {
          legacyInitCalls++;
          return Pointer<llama_dart_tts>.fromAddress(123);
        };
    fields[#start] =
        (Pointer<llama_dart_tts> task, Pointer<llama_dart_tts_request> r) {
          legacyStartCalls++;
          return 0;
        };
    fields[#step] =
        (Pointer<llama_dart_tts> task, Pointer<llama_dart_tts_progress> p) {
          p.ref.state =
              llama_dart_tts_state.LLAMA_DART_TTS_STATE_COMPLETED.value;
          p.ref.frames_generated = 2;
          return 0;
        };
    fields[#getOutputInfo] =
        (Pointer<llama_dart_tts> task, Pointer<llama_dart_tts_output_info> i) {
          i.ref.sample_count = 1;
          i.ref.sample_rate = 24000;
          i.ref.channels = 1;
          return 0;
        };
    fields[#readPcm] =
        (
          Pointer<llama_dart_tts> task,
          int offset,
          Pointer<Float> pcm,
          int capacity,
          Pointer<Size> count,
        ) {
          pcm[0] = 0.25;
          count.value = 1;
          return 0;
        };
    fields[#reset] = (Pointer<llama_dart_tts> task) => 0;
    fields[#free] = (Pointer<llama_dart_tts> task) {};
    fields[#cancel] = (Pointer<llama_dart_tts> task) {};
    fields[#setCancelFlag] = null;
    if (withoutOptIn) {
      for (final name in [
        #supportedModelTypes,
        #getInfoExt,
        #initExt,
        #startWithVoice,
        #getVoiceCount,
        #getVoiceName,
      ]) {
        fields[name] = null;
      }
    } else {
      fields[#supportedModelTypes] = () => runtimeTypes;
      fields[#getInfoExt] =
          (
            Pointer<mtmd_context> mtmd,
            int mask,
            Pointer<llama_dart_tts_info> info,
          ) {
            acceptedMasks.add(mask);
            return fillInfo(info);
          };
      fields[#initExt] =
          (
            Pointer<llama_context> c,
            Pointer<mtmd_context> m,
            int mask,
            Pointer<Int32> s,
          ) {
            initMasks.add(mask);
            return Pointer<llama_dart_tts>.fromAddress(123);
          };
      fields[#startWithVoice] =
          (
            Pointer<llama_dart_tts> task,
            Pointer<llama_dart_tts_request> r,
            Pointer<Char> voice,
          ) {
            startedVoices.add(voice.cast<Utf8>().toDartString());
            return 0;
          };
      final listed = voices;
      fields[#getVoiceCount] = listed == null
          ? null
          : (Pointer<mtmd_context> m, int mask, Pointer<Int32> count) {
              acceptedMasks.add(mask);
              count.value = listed.length;
              return 0;
            };
      fields[#getVoiceName] = listed == null
          ? null
          : (
              Pointer<mtmd_context> m,
              int mask,
              int index,
              Pointer<Char> name,
              int capacity,
              Pointer<Size> length,
            ) {
              final bytes = listed[index].codeUnits;
              length.value = bytes.length;
              if (name == nullptr) return 0;
              if (capacity <= bytes.length) {
                return llama_dart_tts_status
                    .LLAMA_DART_TTS_STATUS_INVALID_ARGUMENT
                    .value;
              }
              final out = name.cast<Uint8>();
              for (var i = 0; i < bytes.length; i++) {
                out[i] = bytes[i];
              }
              out[bytes.length] = 0;
              return 0;
            };
    }
    mirror.setField(
      symbol('_ttsApi'),
      original.type.newInstance(Symbol.empty, [], fields).reflectee,
    );
  }

  BackendTextToSpeechCapabilities capabilities() {
    final context = _context();
    _installApi();
    return service.textToSpeechCapabilities(context, 900 + model);
  }

  Future<BackendTextToSpeechResult> synthesize({String? voice}) {
    final context = _context();
    _installApi();
    return service.synthesizeTextToSpeech(
      context,
      900 + model,
      BackendTextToSpeechRequest(text: 'hello', voice: voice),
      flag.address,
    );
  }

  void dispose() {
    for (final model in contexts.keys) {
      projectors.remove(900 + model);
      modelProjectors.remove(model);
    }
    service.dispose();
    calloc.free(flag);
    directory.deleteSync(recursive: true);
  }
}
