@TestOn('vm')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../support/decision_fixture.dart';

const _modelPathKey = 'LLAMADART_DECISION_MODEL_PATH';
const _headPathKey = 'LLAMADART_DECISION_HEAD_PATH';
const _configPathKey = 'LLAMADART_DECISION_CONFIG_PATH';
const _backendKey = 'LLAMADART_DECISION_BACKEND';
const _logitToleranceKey = 'LLAMADART_DECISION_LOGIT_TOLERANCE';
const _probToleranceKey = 'LLAMADART_DECISION_PROB_TOLERANCE';
const _actLogitToleranceKey = 'LLAMADART_DECISION_ACT_LOGIT_TOLERANCE';
const _gpuBackendNames = {'Metal', 'CUDA', 'HIP', 'Vulkan', 'OpenCL'};

void main() {
  test('matches the Laya 0.3.5 reference on every fixture row', () async {
    final modelPath = _requiredFile(_modelPathKey);
    final headPath = _requiredFile(_headPathKey);
    if (modelPath == null || headPath == null) {
      return;
    }
    final configPath = _optionalFile(_configPathKey);
    final backend = _backend();
    final parity = DecisionParity(
      logitTolerance: _tolerance(_logitToleranceKey, 0.25),
      probTolerance: _tolerance(_probToleranceKey, 0.05),
      actLogitTolerance: _tolerance(_actLogitToleranceKey, 0.05),
    );
    final failures = parity.failures;
    final fixture = DecisionFixture.load();

    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        modelPath,
        modelParams: ModelParams(
          contextSize: 512,
          preferredBackend: backend,
          gpuLayers: backend == GpuBackend.cpu ? 0 : ModelParams.maxGpuLayers,
        ),
      );
      final run = await runDecisionFixture(
        engine,
        fixture,
        parity,
        headPath: headPath,
        configPath: configPath,
      );
      final engineBackend = run.capabilities.backendName;
      final headDevice = run.headDeviceName;
      if (backend != GpuBackend.cpu &&
          backend != GpuBackend.auto &&
          !(engineBackend ?? '').toLowerCase().contains(backend.name)) {
        failures.add(
          'requested ${backend.name}, but the model runs on $engineBackend',
        );
      }
      if (backend == GpuBackend.cpu && headDevice != 'CPU') {
        failures.add('head device $headDevice for a CPU model');
      }
      if (_gpuBackendNames.contains(engineBackend) && headDevice == 'CPU') {
        failures.add('head device CPU for a $engineBackend model');
      }
      print(
        'RESULT decision_engine backend=${backend.name} '
        '${run.describe(parity)}',
      );
      expect(failures, isEmpty, reason: failures.join('\n'));
    } finally {
      await engine.dispose();
    }
  });

  test('load with ComputeDevice.cpu owns an engine with the head on the '
      'CPU', () async {
    final modelPath = _requiredFile(_modelPathKey);
    final headPath = _requiredFile(_headPathKey);
    if (modelPath == null || headPath == null) {
      return;
    }
    final fixture = DecisionFixture.load();
    final row = fixture.rows.first;
    final configPath = _optionalFile(_configPathKey);
    DecisionEngine? decisions;
    try {
      decisions = await DecisionEngine.load(
        DecisionModel(
          encoder: ModelSource.path(modelPath),
          head: ModelSource.path(headPath),
          config: configPath == null ? null : ModelSource.path(configPath),
        ),
        params: const DecisionModelParams(device: ComputeDevice.cpu),
      );

      final result = await decisions.systemOne(
        state: row.state,
        questions: {row.questionId: DecisionQuestion.fromJson(row.question)},
      );

      print(
        'RESULT decision_engine_cpu_placement backend=cpu '
        'headDevice=${_oneWord(decisions.info.deviceName)}',
      );
      expect(decisions.info.deviceName, 'CPU');
      final parity = DecisionParity(
        probTolerance: _tolerance(_probToleranceKey, 0.05),
      )..checkAnswer(row, result.answers[row.questionId]!);
      expect(parity.failures, isEmpty, reason: parity.failures.join('\n'));
      await decisions.dispose();
      expect(
        (await decisions.capabilities).unsupportedReason,
        'The DecisionEngine is disposed.',
      );
    } finally {
      await decisions?.dispose();
    }
  });

  test('rejects a config longer than the encoder was trained for', () async {
    final modelPath = _requiredFile(_modelPathKey);
    final headPath = _requiredFile(_headPathKey);
    if (modelPath == null || headPath == null) {
      return;
    }
    final engine = LlamaEngine(LlamaBackend());
    final tempDir = Directory.systemTemp.createTempSync(
      'decision_long_config_',
    );
    try {
      await engine.loadModel(
        modelPath,
        modelParams: ModelParams(
          contextSize: 512,
          preferredBackend: _backend(),
          gpuLayers: 0,
        ),
      );
      final head = await engine.loadDecisionHeadBackend(
        headPath,
        configPath: _optionalFile(_configPathKey),
      );
      final config = jsonDecode(head.configJson) as Map<String, Object?>;
      await engine.freeDecisionHeadBackend(head.handle);
      final longConfig = File('${tempDir.path}/rl_agent_config.json')
        ..writeAsStringSync(jsonEncode({...config, 'max_len': 1 << 20}));

      await expectLater(
        DecisionEngine.attach(
          engine,
          head: ModelSource.path(headPath),
          config: ModelSource.path(longConfig.path),
        ),
        throwsA(
          isA<LlamaModelException>().having(
            (error) => error.message,
            'message',
            contains('but the loaded encoder was trained for'),
          ),
        ),
      );
    } finally {
      await engine.dispose();
      tempDir.deleteSync(recursive: true);
    }
  });

  test('tokenizes the text after U+0000 as llama-tokenize does', () async {
    final modelPath = _requiredFile(_modelPathKey);
    if (modelPath == null) {
      return;
    }
    final engine = LlamaEngine(LlamaBackend());
    try {
      await engine.loadModel(
        modelPath,
        modelParams: ModelParams(
          contextSize: 512,
          preferredBackend: _backend(),
          gpuLayers: 0,
        ),
      );

      // `printf 'ab\0cd' | llama-tokenize --stdin --ids --no-bos` at
      // llama.cpp 7fe450e19 on laya-Q8_0.gguf.
      expect(await engine.tokenize('ab\u0000cd', addSpecial: false), [
        357,
        177,
        2428,
      ]);
    } finally {
      await engine.dispose();
    }
  });

  test('engine dispose frees a head that was not disposed', () async {
    final modelPath = _requiredFile(_modelPathKey);
    final headPath = _requiredFile(_headPathKey);
    if (modelPath == null || headPath == null) {
      return;
    }
    final backend = _backend();
    final engine = LlamaEngine(LlamaBackend());
    var engineDisposed = false;
    try {
      await engine.loadModel(
        modelPath,
        modelParams: ModelParams(
          contextSize: 512,
          preferredBackend: backend,
          gpuLayers: backend == GpuBackend.cpu ? 0 : ModelParams.maxGpuLayers,
        ),
      );
      final configPath = _optionalFile(_configPathKey);
      final decisions = await DecisionEngine.attach(
        engine,
        head: ModelSource.path(headPath),
        config: configPath == null ? null : ModelSource.path(configPath),
      );
      final questions = {
        'refund': DecisionQuestion.noul('Does the user request a refund?'),
      };
      await decisions.systemOne(state: 'Refund me.', questions: questions);

      await engine.dispose();
      engineDisposed = true;

      await expectLater(
        decisions.systemOne(state: 'Refund me.', questions: questions),
        throwsA(isA<LlamaStateException>()),
      );
      await decisions.dispose();
    } finally {
      if (!engineDisposed) await engine.dispose();
    }
  });

  test(
    'attach shares one encoder between heads and leaves it loaded',
    () async {
      final modelPath = _requiredFile(_modelPathKey);
      final headPath = _requiredFile(_headPathKey);
      if (modelPath == null || headPath == null) {
        return;
      }
      final configPath = _optionalFile(_configPathKey);
      final config = configPath == null ? null : ModelSource.path(configPath);
      final row = DecisionFixture.load().rows.first;
      final questions = {
        row.questionId: DecisionQuestion.fromJson(row.question),
      };
      final engine = LlamaEngine(LlamaBackend());
      try {
        await engine.loadModel(
          modelPath,
          modelParams: DecisionModelParams(
            device: _backend() == GpuBackend.cpu
                ? ComputeDevice.cpu
                : ComputeDevice.auto,
          ).encoderModelParams,
        );
        final first = await DecisionEngine.attach(
          engine,
          head: ModelSource.path(headPath),
          config: config,
        );
        final second = await DecisionEngine.attach(
          engine,
          head: ModelSource.path(headPath),
          config: config,
        );
        final expected = await first.systemOne(
          state: row.state,
          questions: questions,
        );
        await first.dispose();

        final answer = await second.systemOne(
          state: row.state,
          questions: questions,
        );
        expect(engine.isReady, isTrue);
        expect(
          answer.answers[row.questionId]!.confidence,
          closeTo(expected.answers[row.questionId]!.confidence, 1e-6),
        );
        await second.dispose();
        expect(engine.isReady, isTrue);
      } finally {
        await engine.dispose();
      }
    },
  );
}

GpuBackend _backend() {
  final name = Platform.environment[_backendKey]?.trim();
  return GpuBackend.values.byName(name == null || name.isEmpty ? 'cpu' : name);
}

String _oneWord(String value) => value.replaceAll(RegExp(r'\s+'), '_');

double _tolerance(String environmentKey, double fallback) {
  final value = Platform.environment[environmentKey]?.trim();
  if (value == null || value.isEmpty) return fallback;
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    throw StateError('$environmentKey must be a non-negative number.');
  }
  return parsed;
}

String? _requiredFile(String environmentKey) {
  final value = Platform.environment[environmentKey];
  if (value == null || value.isEmpty) {
    markTestSkipped('Set $environmentKey to run the decision engine E2E.');
    return null;
  }
  if (!File(value).existsSync()) {
    throw StateError('$environmentKey does not exist.');
  }
  return value;
}

String? _optionalFile(String environmentKey) {
  final value = Platform.environment[environmentKey];
  if (value == null || value.isEmpty) return null;
  if (!File(value).existsSync()) {
    throw StateError('$environmentKey does not exist.');
  }
  return value;
}
