@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/isolate_shutdown_releases.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/decision/decision_question.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:llamadart/src/core/models/inference/generation_params.dart';
import 'package:llamadart/src/core/models/inference/model_params.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';
import '../../../support/recording_exit_teardown.dart';
import '../../../support/safetensors_writer.dart';
import '../../../support/synthetic_decision_head.dart';
import '../../../support/synthetic_embedding_gguf.dart';

const _params = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  gpuLayers: 0,
  contextSize: 64,
);
const _pooled = ModelParams(
  numberOfThreads: 2,
  numberOfThreadsBatch: 2,
  gpuLayers: 0,
  contextSize: 64,
  maxParallelSequences: 2,
);
const _greedy = GenerationParams(maxTokens: 4, temp: 0, topK: 1, seed: 1);
const _meanPooling = 1;

const _load = 'llama_dart_model_load_from_file';
const _create = 'llama_dart_init_from_model';
const _decode = 'llama_dart_decode';
const _encode = 'llama_dart_encode';
const _sample = 'llama_dart_sampler_sample';
const _synchronize = 'llama_dart_synchronize';
const _track = 'llama_dart_exit_track';
const _free = 'llama_dart_exit_free';

final _lfm2Model = Platform.environment['LLAMADART_LFM2_MODEL'];
final _metal =
    Platform.isMacOS && Platform.environment['GGML_METAL_DEVICES'] != '0';

// Runs the real llama.cpp runtime on the CPU. A service on the tracked calls
// has to make every call that exit teardown waits for through its
// ExitTeardownApi, so each test compares the whole recorded sequence: one
// upstream call in its place leaves a gap.
void main() {
  late Directory dir;
  late RecordingExitTeardown recorder;
  late LlamaCppService service;
  late int model;
  late int context;
  // The fake libmtmd whose media prompt the recorder's eval functions run.
  FakeMtmd? mtmd;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_exit_calls_');
    writeSyntheticLlamaGguf('${dir.path}/model.gguf');
    mtmd = null;
    recorder = RecordingExitTeardown(
      ExitTeardownApi.tryResolve(isWindows: Platform.isWindows)!,
      evalMedia: (context, nPast, nBatch, newNPast) =>
          mtmd!.evalMedia(context, nPast, nBatch, newNPast),
    );
    service = LlamaCppService(
      isMacosX64: false,
      objectCalls: LlamaCppObjectCalls.tracked(recorder.api),
    )..initializeBackend();
    model = service.loadModel('${dir.path}/model.gguf', _params);
    context = service.createContext(model, _params);
  });

  tearDown(() {
    service.dispose();
    final unfreed = recorder.unfreed;
    // An object freed upstream is still tracked: untrack it, or exit teardown
    // frees it again when the test process ends.
    for (final address in unfreed) {
      recorder.real.untrack(Pointer.fromAddress(address));
    }
    dir.deleteSync(recursive: true);
    expect(
      unfreed,
      isEmpty,
      reason: 'everything created through the exit API is freed through it',
    );
  });

  int loadModel(String name, File Function(String path) write) {
    write('${dir.path}/$name.gguf');
    return service.loadModel('${dir.path}/$name.gguf', _params);
  }

  test('creates and frees models and contexts through it', () {
    expect(recorder.calls, [_load, _create]);

    service.freeContext(context);
    service.freeModel(model);

    expect(recorder.freed, recorder.owned.reversed);
  });

  for (final (name, free) in <(String, void Function())>[
    ('dispose', () => service.dispose()),
    ('freeModel', () => service.freeModel(model)),
  ]) {
    test('$name frees a context, then the projector, then their model', () {
      final projectorPath = '${dir.path}/mmproj.gguf';
      File(projectorPath).writeAsStringSync('GGUF');
      final fake = FakeMtmd.install(service, tokens: const []);
      addTearDown(fake.dispose);
      service.createMultimodalContext(model, projectorPath);
      final [modelAddress, contextAddress, projectorAddress] = recorder.owned;

      free();

      // A projector points at its model, and the model is the last object
      // freed: an exit that catches the last free in flight then finds one
      // object left, not the many buffers of a projector.
      expect(recorder.freed, [contextAddress, projectorAddress, modelAddress]);
    });
  }

  test('generates through its synchronize, decode and sample', () async {
    recorder.clearCalls();

    final limit = await _generate(service, context, 'ab', _greedy);

    expect(limit, BackendGenerationLimit.maxTokens);
    expect(recorder.calls, [
      _synchronize,
      _decode,
      for (var token = 0; token < _greedy.maxTokens; token++) ...[
        _sample,
        _decode,
      ],
      // The sample that tells a length limit from an end of generation.
      _sample,
    ]);
  });

  test('drafts from n-grams through its sample, decode and sequence '
      'state', () async {
    recorder.clearCalls();

    await _generate(
      service,
      context,
      'ab',
      _greedy.copyWith(
        maxTokens: 24,
        penalty: 1,
        speculativeDecodingConfig: const SpeculativeDecodingConfig.ngramSimple(
          ngramSizeN: 1,
          ngramSizeM: 4,
          ngramMinHits: 1,
        ),
      ),
    );

    // After the prompt, each sampled token is decoded alone (d) or with a
    // draft, which is checkpointed, decoded and synchronized (YGHDY); a draft
    // leaves the next token already sampled.
    expect(recorder.shorthand, matches(RegExp(r'^YD(S(d|(YGHDY)+d?))*S?$')));
    expect(recorder.shorthand, contains('Sd'));
    expect(recorder.shorthand, contains('SYGHDY'));
  });

  test('drafts from a draft model it loaded and holds through it', () async {
    recorder.clearCalls();

    await _generate(
      service,
      context,
      'abababab',
      _greedy.copyWith(
        maxTokens: 12,
        penalty: 1,
        speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
          // ignore: deprecated_member_use_from_same_package
          draftModelPath: '${dir.path}/model.gguf',
          draftTokenMax: 4,
        ),
      ),
    );

    expect(recorder.calls.sublist(0, 2), [_synchronize, _load]);
    recorder.calls.removeAt(1);
    // With a draft context nothing is checkpointed: a draft is decoded and
    // synchronized (DY).
    expect(recorder.shorthand, matches(RegExp(r'^YD(S(d|(DY)+d?))*S?$')));
    expect(recorder.shorthand, contains('Sd'));
    expect(recorder.shorthand, contains('SDY'));
    expect(
      [
        for (final (:free, :stage)
            in IsolateShutdownReleases.current.debugHeldForTesting)
          if (stage == ShutdownStage.model) free,
      ],
      [recorder.real.freeAddress, recorder.real.freeAddress],
    );
  });

  test('embeds one text through its decode, or its encode for an '
      'encoder', () {
    recorder.clearCalls();
    expect(service.embed(context, 'exit teardown'), isNotEmpty);
    expect(recorder.calls, [_synchronize, _decode]);

    final encoder = service.createContext(
      loadModel('t5', writeSyntheticT5EncoderGguf),
      _params,
    );
    recorder.clearCalls();
    expect(service.embed(encoder, 'exit teardown'), isNotEmpty);
    expect(recorder.calls, [_synchronize, _encode]);
  });

  test('embeds a batch in one pass through its decode, or its encode for an '
      'encoder', () {
    final decoder = service.createContext(
      loadModel(
        'mean',
        (path) => writeSyntheticLlamaGguf(path, poolingType: _meanPooling),
      ),
      _pooled,
    );
    recorder.clearCalls();
    expect(service.embedBatch(decoder, ['exit', 'teardown']), hasLength(2));
    expect(recorder.calls, [_synchronize, _decode]);

    final encoder = service.createContext(
      loadModel(
        't5',
        (path) => writeSyntheticT5EncoderGguf(path, poolingType: _meanPooling),
      ),
      _pooled,
    );
    recorder.clearCalls();
    expect(service.embedBatch(encoder, ['exit', 'teardown']), hasLength(2));
    expect(recorder.calls, [_synchronize, _encode]);
  });

  test('saves and loads state through it', () {
    final path = '${dir.path}/state.bin';
    recorder.clearCalls();

    expect(service.stateSaveFile(context, path, [1, 2]), isTrue);
    expect(service.stateLoadFile(context, path, 8), [1, 2]);

    expect(recorder.calls, [
      _synchronize,
      'llama_dart_state_save_file',
      _synchronize,
      'llama_dart_state_load_file',
    ]);
  });

  test('loads a LoRA adapter through it', () {
    final path = '${dir.path}/adapter.gguf';
    File(path).writeAsStringSync('not an adapter');
    recorder.clearCalls();

    expect(
      () => service.handleLora(context, path, 1, 'set'),
      throwsA(isA<LlamaModelException>()),
    );

    expect(recorder.calls, ['llama_dart_adapter_lora_init']);
  });

  test('tracks, runs and frees a decision head through it', () {
    final encoder = loadModel(
      'encoder',
      (path) => writeSyntheticModernBertGguf(path, decisionTokens: true),
    );
    SyntheticDecisionHead(
      d: 16,
      layers: 1,
      seed: 1,
    ).write('${dir.path}/head.safetensors');
    File(
      '${dir.path}/config.json',
    ).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
    recorder.clearCalls();
    final ownedBefore = recorder.owned.length;

    final head = service
        .loadDecisionHead(
          encoder,
          '${dir.path}/head.safetensors',
          '${dir.path}/config.json',
        )
        .handle;
    // The encoder context, then the CPU backend, the weights buffer and the
    // scheduler.
    expect(recorder.calls, [_create, _track, _track, _track]);

    recorder.clearCalls();
    service.runDecision(head, [
      BackendDecisionSequence(
        tokens: Int32List.fromList([1, 5, 0, 6, 0, 2]),
        markers: Int32List.fromList([2, 4]),
        questionType: DecisionQuestionType.choice,
      ),
    ]);
    expect(recorder.calls, [
      _encode,
      'llama_dart_ggml_backend_sched_graph_compute',
    ]);

    recorder.freed.clear();
    recorder.clearCalls();
    service.freeDecisionHead(head);
    expect(recorder.calls, [_free, _free, _free, _free]);
    expect(recorder.freed, unorderedEquals(recorder.owned.skip(ownedBefore)));
  });

  test('frees the encoder context of a decision head it could not '
      'create', () {
    final encoder = loadModel(
      'encoder',
      (path) => writeSyntheticModernBertGguf(path, decisionTokens: true),
    );
    // The head's shapes are right, so the service creates the context, but
    // one tensor cannot be uploaded as F32.
    final tensors = SyntheticDecisionHead(d: 16, layers: 1, seed: 1).tensors;
    writeSafetensors('${dir.path}/head.safetensors', {
      for (final MapEntry(key: name, value: tensor) in tensors.entries)
        name: name == 'scorer.0.weight'
            ? TestTensor('I32', tensor.shape, Uint8List(4 * tensor.shape[0]))
            : TestTensor.f32(tensor.shape, tensor.values),
    });
    File(
      '${dir.path}/config.json',
    ).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
    recorder.clearCalls();
    recorder.freed.clear();
    final ownedBefore = recorder.owned.length;

    expect(
      () => service.loadDecisionHead(
        encoder,
        '${dir.path}/head.safetensors',
        '${dir.path}/config.json',
      ),
      throwsA(isA<LlamaModelException>()),
    );

    expect(recorder.calls.first, _create);
    expect(recorder.freed, unorderedEquals(recorder.owned.skip(ownedBefore)));
  });

  test(
    'tracks and frees the device backend of a decision head on a GPU',
    skip: _metal ? null : 'Needs a Mac with Metal devices enabled.',
    () {
      writeSyntheticModernBertGguf(
        '${dir.path}/encoder.gguf',
        decisionTokens: true,
      );
      final encoder = service.loadModel(
        '${dir.path}/encoder.gguf',
        const ModelParams(
          numberOfThreads: 2,
          numberOfThreadsBatch: 2,
          gpuLayers: 99,
          contextSize: 64,
        ),
      );
      SyntheticDecisionHead(
        d: 16,
        layers: 1,
        seed: 1,
      ).write('${dir.path}/head.safetensors');
      File(
        '${dir.path}/config.json',
      ).writeAsStringSync('{"max_len": 64, "head_layers": 1}');
      recorder.clearCalls();

      final head = service.loadDecisionHead(
        encoder,
        '${dir.path}/head.safetensors',
        '${dir.path}/config.json',
      );
      expect(head.deviceName, isNot('CPU'));
      // The encoder context, the CPU and device backends, the weights buffer
      // and the scheduler.
      expect(recorder.calls, [_create, _track, _track, _track, _track]);

      recorder.clearCalls();
      service.freeDecisionHead(head.handle);
      expect(recorder.calls, [_free, _free, _free, _free, _free]);
    },
  );

  test(
    'restores and replays a rejected draft through it on a model whose '
    'memory cannot drop a tail',
    skip: _lfm2Model == null
        ? 'Set LLAMADART_LFM2_MODEL to an LFM2 GGUF.'
        : null,
    () async {
      final hybrid = service.loadModel(_lfm2Model!, _params);
      final hybridContext = service.createContext(hybrid, _params);
      recorder.clearCalls();

      await _generate(
        service,
        hybridContext,
        'One two three. One two four. One two five. One two',
        _greedy.copyWith(
          maxTokens: 32,
          penalty: 1,
          speculativeDecodingConfig:
              const SpeculativeDecodingConfig.ngramSimple(
                ngramSizeN: 1,
                ngramSizeM: 4,
                ngramMinHits: 1,
              ),
        ),
      );

      // A rejected draft is rolled back by writing the checkpoint (X), then
      // the accepted tokens are decoded again and synchronized.
      expect(
        recorder.shorthand,
        matches(RegExp(r'^Y[dD]+(S(d|(YGHDY(X[dD]Y)?)+d?))*S?$')),
      );
      expect(recorder.shorthand, contains('X'));
    },
  );

  test('rejects a non-causal image above a micro-batch below the batch after '
      'the tokenize, before any evaluating call', () async {
    final projectorPath = '${dir.path}/mmproj.gguf';
    File(projectorPath).writeAsStringSync('GGUF');
    final small = service.createContext(
      model,
      const ModelParams(
        numberOfThreads: 2,
        numberOfThreadsBatch: 2,
        gpuLayers: 0,
        contextSize: 64,
        batchSize: 16,
        microBatchSize: 8,
      ),
    );
    final fake = mtmd = FakeMtmd.install(
      service,
      tokens: service.tokenize(model, 'abcdefgh', true),
      chunkEval: true,
      chunk: FakeMtmdChunk.nonCausalImage,
      decode: recorder.api.decode,
    );
    addTearDown(fake.dispose);
    service.createMultimodalContext(model, projectorPath);
    recorder.clearCalls();

    await expectLater(
      _generate(service, small, '<__media__>', _greedy, parts: fake.parts),
      throwsA(isA<LlamaInferenceException>()),
    );

    expect(recorder.calls, [_synchronize, 'llama_dart_mtmd_tokenize']);
    expect(fake.calls, isEmpty);
  });

  for (final chunkEval in [true, false]) {
    final evalCall = chunkEval
        ? 'mtmd_helper_eval_chunk_single'
        : 'mtmd_helper_eval_chunks';

    test('creates, evaluates and frees a projector through it '
        '(chunk-level eval: $chunkEval)', () async {
      final projectorPath = '${dir.path}/mmproj.gguf';
      File(projectorPath).writeAsStringSync('GGUF');
      final fake = mtmd = FakeMtmd.install(
        service,
        tokens: service.tokenize(model, 'ab', true),
        chunkEval: chunkEval,
        decode: recorder.api.decode,
      );
      addTearDown(fake.dispose);
      recorder.clearCalls();
      recorder.freed.clear();

      final projector = service.createMultimodalContext(model, projectorPath);
      final limit = await _generate(
        service,
        context,
        '<__media__>',
        _greedy,
        parts: fake.parts,
      );
      service.freeMultimodalContext(projector);

      expect(limit, BackendGenerationLimit.maxTokens);
      expect(recorder.calls, [
        'llama_dart_mtmd_init_from_file',
        _synchronize,
        'llama_dart_mtmd_tokenize',
        'llama_dart_$evalCall',
        // The fake media evaluation decodes its tokens.
        _decode,
        for (var token = 0; token < _greedy.maxTokens; token++) ...[
          _sample,
          _decode,
        ],
        _sample,
        _free,
      ]);
      expect(recorder.freed, [RecordingExitTeardown.projector.address]);
      expect(fake.calls, isEmpty);
    });

    test('creates, evaluates and frees a projector through libmtmd on the '
        'upstream calls (chunk-level eval: $chunkEval)', () async {
      final projectorPath = '${dir.path}/mmproj.gguf';
      File(projectorPath).writeAsStringSync('GGUF');
      final upstream = LlamaCppService(
        objectCalls: LlamaCppObjectCalls.upstream,
      )..initializeBackend();
      addTearDown(upstream.dispose);
      final fake = FakeMtmd.install(
        upstream,
        tokens: service.tokenize(model, 'ab', true),
        chunkEval: chunkEval,
      );
      addTearDown(fake.dispose);
      final upstreamModel = upstream.loadModel(
        '${dir.path}/model.gguf',
        _params,
      );
      final upstreamContext = upstream.createContext(upstreamModel, _params);

      final projector = upstream.createMultimodalContext(
        upstreamModel,
        projectorPath,
      );
      await _generate(
        upstream,
        upstreamContext,
        '<__media__>',
        _greedy,
        parts: fake.parts,
      );
      upstream.freeMultimodalContext(projector);

      expect(fake.calls, [
        'mtmd_init_from_file',
        'mtmd_tokenize',
        evalCall,
        'mtmd_free',
      ]);
    });
  }
}

/// Generates to the end and returns the limit that ended it, if one did.
Future<BackendGenerationLimit?> _generate(
  LlamaCppService service,
  int context,
  String prompt,
  GenerationParams params, {
  List<LlamaContentPart>? parts,
}) async {
  final cancel = calloc<Int8>();
  BackendGenerationLimit? limit;
  try {
    await service
        .generate(
          context,
          prompt,
          params,
          cancel.address,
          parts: parts,
          onLimit: (reached) => limit = reached,
        )
        .drain<void>();
    return limit;
  } finally {
    calloc.free(cancel);
  }
}
