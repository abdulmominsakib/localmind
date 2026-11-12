@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_backend.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_platform.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/worker.dart';
import 'package:test/test.dart';

import '../../../support/suite_system_temp.dart';

void main() {
  useSuiteSystemTemp();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('llamadart_engine_create_');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  // The real service behind the real backend and engine, in this isolate,
  // with a runtime client whose engine creation returns no engine.
  Future<({LlamaEngine engine, List<_NoEngineClient> clients})> load(
    ModelParams params, {
    Set<String> failingBackends = const {'cpu', 'gpu'},
  }) async {
    final clients = <_NoEngineClient>[];
    final handshake = ReceivePort();
    runLiteRtLmWorkerForTesting(
      handshake.sendPort,
      LiteRtLmService(
        clientFactory: () {
          final client = _NoEngineClient(failingBackends);
          clients.add(client);
          return client;
        },
        readBundleCapabilities: (_) =>
            (vision: false, audio: false, speculativeDecoding: false),
      ),
      exitOnDispose: false,
    );
    final engine = LlamaEngine(
      LiteRtLmBackend(initialSendPort: await handshake.first as SendPort),
    );
    final modelFile = File('${tempDir.path}/Qwen3-0.6B.litertlm');
    await modelFile.writeAsString('fake model');
    await engine.loadModel(modelFile.path, modelParams: params);
    return (engine: engine, clients: clients);
  }

  const hello = [
    LlamaChatMessage.fromText(role: LlamaChatRole.user, text: 'Hello'),
  ];

  test('a GPU engine the runtime cannot create fails the first generation '
      'with LlamaUnsupportedException when ComputeDevice.gpu was '
      'requested', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    final loaded = await load(const ModelParams(device: ComputeDevice.gpu));
    try {
      expect(loaded.clients, isEmpty, reason: 'engine creation is deferred');
      await expectLater(
        loaded.engine.create(hello).drain<void>(),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('ComputeDevice.gpu'),
              contains('could not create a gpu engine'),
              contains('engine creation failed for backend "gpu"'),
              contains(_nativeError),
              contains('ComputeDevice.cpu'),
            ),
          ),
        ),
      );
      expect(loaded.clients.single.backend, 'gpu');
      expect(loaded.clients.single.conversations, 0);
    } finally {
      await loaded.engine.dispose();
    }
  });

  test('a GPU engine the runtime cannot create under ComputeDevice.auto '
      'is retried on the CPU, and each first use fails with the GPU error '
      'when the CPU fails too', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    // Android resolves auto to the GPU; the GPU preference makes every host
    // resolve it the same way.
    final loaded = await load(
      const ModelParams(preferredBackend: GpuBackend.vulkan),
    );
    try {
      expect(loaded.clients, isEmpty, reason: 'engine creation is deferred');
      final engineCreateFailure = throwsA(
        isA<LlamaModelException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('engine creation failed for backend "gpu"'),
            contains(_nativeError),
            contains('try backend "cpu"'),
          ),
        ),
      );
      final engine = loaded.engine;
      for (final (entryPoint, firstUse) in <(String, Future<void> Function())>[
        ('create', () => engine.create(hello).drain<void>()),
        ('generate', () => engine.generate('Hello').drain<void>()),
        ('complete', () => engine.complete(hello)),
        (
          'ChatSession.create',
          () => ChatSession(
            engine,
          ).create(const [LlamaTextContent('Hello')]).drain<void>(),
        ),
        ('tokenize', () => engine.tokenize('Hello')),
        ('detokenize', () => engine.detokenize(const [1, 2])),
        ('getTokenCount', () => engine.getTokenCount('Hello')),
        ('chatTemplate', () => engine.chatTemplate(hello)),
      ]) {
        await expectLater(firstUse(), engineCreateFailure, reason: entryPoint);
      }
      expect(loaded.clients.map((client) => client.backend), [
        for (var i = 0; i < 8; i++) ...['gpu', 'cpu'],
      ]);
      expect(loaded.clients.every((client) => client.conversations == 0), true);
      expect(await engine.getBackendName(), 'LiteRT-LM gpu');
    } finally {
      await loaded.engine.dispose();
    }
  });

  test('a GPU engine the runtime cannot create under ComputeDevice.auto '
      'runs on the CPU, which the backend name reports', () async {
    if (!liteRtLmNativeGpuSupportedOnCurrentPlatform()) {
      markTestSkipped('No LiteRT-LM GPU backend on this platform.');
      return;
    }
    final loaded = await load(
      const ModelParams(preferredBackend: GpuBackend.vulkan),
      failingBackends: const {'gpu'},
    );
    try {
      final engine = loaded.engine;
      expect(await engine.getBackendName(), 'LiteRT-LM gpu');
      expect(await engine.tokenize('Hello'), [1]);
      expect(loaded.clients.map((client) => client.backend), ['gpu', 'cpu']);
      expect(await engine.getBackendName(), 'LiteRT-LM cpu');
      expect(await engine.getTokenCount('Hello again'), 1);
      expect(loaded.clients, hasLength(2));
    } finally {
      await loaded.engine.dispose();
    }
  });
}

const _nativeError = 'LiteRT-LM reported INTERNAL (13): no GPU device.';

class _NoEngineClient extends LiteRtLmRuntimeClient {
  _NoEngineClient(this.failingBackends);

  final Set<String> failingBackends;
  String? backend;
  int conversations = 0;

  @override
  Future<void> initialize({
    required String modelPath,
    String backend = 'gpu',
    String? visionBackend,
    String? audioBackend,
    int maxTokens = 4096,
    int outputTokens = 256,
    int? prefillTokens,
    int? maxNumImages,
    String? cacheDir,
    bool speculativeDecoding = true,
    int minLogLevel = 3,
    LiteRtLmActivationDataType? activationDataType,
    int? prefillChunkSize,
    bool? parallelFileSectionLoading,
    String? dispatchLibDir,
    int? numberOfThreads,
  }) async {
    this.backend = backend;
    if (!failingBackends.contains(backend)) return;
    liteRtLmCheckEngineCreated(
      0,
      backend: backend,
      modelPath: modelPath,
      nativeError: _nativeError,
    );
  }

  @override
  void setMinLogLevel(int level) {}

  @override
  List<int> tokenize(String text, {bool addSpecial = true}) => const [1];

  @override
  void createConversation({
    String? systemMessage,
    String? promptTemplate,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraContext,
    double temperature = 0.8,
    int topK = 40,
    double topP = 0.95,
    int seed = 1,
    bool npuBackend = false,
    String? loraPath,
    bool jsonSchemaConstraints = false,
  }) {
    conversations += 1;
  }

  @override
  void cancel() {}

  @override
  void dispose() {}
}
