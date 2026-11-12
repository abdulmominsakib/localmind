part of 'runner.dart';

/// Optional public state API boundary; existing reference adapters need not
/// implement filesystem persistence.
abstract interface class StateValidationEngine {
  bool get supportsStatePersistence;
  bool get supportsNextTokenScoring;
  Future<LlamaStateIdentity> stateIdentity();
  Future<List<int>> tokenizeStatePrompt(String text);
  Future<Map<String, dynamic>> scoreStatePrompt(
    String text, {
    List<int> candidates = const [],
    int topK = 0,
    required bool reuse,
  });
  Future<bool> saveState(String path, List<int> tokens);
  Future<List<int>> loadState(String path, int capacity);
  Future<Map<String, dynamic>> generateStatePrompt(
    String text, {
    required bool reuse,
  });
}

/// Host-owned bounded temporary storage. Common/browser code never imports IO.
abstract interface class StateValidationWorkspace {
  String path(String role);
  Future<Uint8List> read(String role);
  Future<void> write(String role, List<int> bytes);
  Future<void> dispose();
}

final class _StateObserver extends LlamaEngineObserver {
  LlamaOperationResult? result;
  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) =>
      operation is LlamaTextCompletionOperation ? _StateOperation(this) : null;
}

final class _StateOperation extends LlamaOperationObserver {
  _StateOperation(this.owner);
  final _StateObserver owner;
  @override
  void onEnd(LlamaOperationResult result) => owner.result = result;
}

mixin _PublicStateValidation implements StateValidationEngine {
  LlamaEngine get _engine;
  _StateObserver get _stateObserver;
  @override
  bool get supportsStatePersistence => _engine.supportsStatePersistence;
  @override
  bool get supportsNextTokenScoring => _engine.supportsNextTokenScoring;
  @override
  Future<LlamaStateIdentity> stateIdentity() => _engine.stateIdentity();
  @override
  Future<List<int>> tokenizeStatePrompt(String text) =>
      _engine.tokenize(text, addSpecial: true);
  @override
  Future<bool> saveState(String path, List<int> tokens) =>
      _engine.stateSaveFile(path, tokens: tokens);
  @override
  Future<List<int>> loadState(String path, int capacity) async =>
      (await _engine.stateLoadFile(path, tokenCapacity: capacity)).tokens;
  @override
  Future<Map<String, dynamic>> scoreStatePrompt(
    String text, {
    List<int> candidates = const [],
    int topK = 0,
    required bool reuse,
  }) async {
    final scores = await _engine.scoreNextToken(
      text,
      candidates: candidates,
      topK: topK,
      reusePromptPrefix: reuse,
    );
    Map<String, dynamic> row(LlamaTokenLogprob score) => {
      'token': score.token,
      'logprob': score.logprob,
    };
    return {
      'prompt_tokens': scores.promptTokens,
      'candidates': scores.candidates.map(row).toList(),
      'top': scores.top.map(row).toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> generateStatePrompt(
    String text, {
    required bool reuse,
  }) async {
    _stateObserver.result = null;
    final output = await _engine
        .generate(
          text,
          params: GenerationParams(
            maxTokens: 1,
            temp: 0,
            seed: 1,
            topK: 1,
            topP: 1,
            minP: 0,
            penalty: 1,
            reusePromptPrefix: reuse,
          ),
        )
        .join();
    final perf = await _engine.getPerformanceContext();
    final result = _stateObserver.result;
    return {
      'output': output,
      'observer_present': result != null,
      'observer_error': result?.error?.runtimeType.toString(),
      'observer_cancelled': result?.cancelled,
      'finish_reason': result?.finishReason,
      'usage': result?.usage?.toJson(),
      'prompt_eval_tokens': perf?.promptEvalTokens,
    };
  }
}

extension _StateValidation on ValidationRunner {
  Future<Map<String, dynamic>> _stateCase(String id, String location) async {
    if (engine is! StateValidationEngine) {
      return {'status': 'NOT_RUN', 'reason': 'state_adapter_unavailable'};
    }
    final state = engine as StateValidationEngine;
    final diagnostics = await _checked(engine.diagnostics);
    final expected = expectedStateCapability(
      profile,
      web: engine.isWeb,
      diagnostics: diagnostics,
    );
    final capability = <String, dynamic>{
      'supported': state.supportsStatePersistence,
      'scoring': state.supportsNextTokenScoring,
      'diagnostics': diagnostics,
      'web': engine.isWeb,
    };
    if (id == 'P05.identity' &&
        expectedStateIdentityCapability(
              profile,
              web: engine.isWeb,
              diagnostics: diagnostics,
            ) ==
            false) {
      String rejection;
      try {
        await _checked(state.stateIdentity);
        rejection = 'accepted';
      } catch (error) {
        rejection = error is LlamaUnsupportedException
            ? 'LlamaUnsupportedException'
            : error.runtimeType.toString();
      }
      final evidence = <String, dynamic>{
        ...capability,
        'identity_rejection': rejection,
        'recovery': await _checked(
          () => engine.generate(_shortPrompt, profile, raw: !profile.isChat),
        ),
      };
      return {
        ...evidence,
        'status':
            validStateCaseEvidence(
              id,
              evidence,
              profile,
              web: engine.isWeb,
              diagnostics: diagnostics,
            )
            ? 'PASS'
            : 'FAIL',
      };
    }
    if (expected == null) {
      return {
        ...capability,
        'status': 'NOT_RUN',
        'reason': 'state_profile_or_host_unqualified',
      };
    }
    if (id == 'P01.capability') {
      if (!expected && !state.supportsStatePersistence) {
        Future<String> rejection(Future<Object?> Function() call) async {
          try {
            await call();
            return 'accepted';
          } catch (error) {
            return error is LlamaUnsupportedException
                ? 'LlamaUnsupportedException'
                : error.runtimeType.toString();
          }
        }

        capability['save_rejection'] = await rejection(
          () => state.saveState('state-unsupported-probe', const [1]),
        );
        capability['load_rejection'] = await rejection(
          () => state.loadState('state-unsupported-probe', 1),
        );
        capability['recovery'] = await _checked(
          () => engine.generate(_shortPrompt, profile, raw: !profile.isChat),
        );
      }
      return {
        ...capability,
        'status':
            validStateCaseEvidence(
              id,
              capability,
              profile,
              web: engine.isWeb,
              diagnostics: diagnostics,
            )
            ? 'PASS'
            : 'FAIL',
      };
    }
    if (!expected ||
        !state.supportsStatePersistence ||
        !state.supportsNextTokenScoring) {
      return {
        ...capability,
        'status': 'FAIL',
        'reason': 'required_state_capability_missing',
      };
    }
    final factory = stateWorkspaceFactory;
    if (factory == null) {
      return {'status': 'NOT_RUN', 'reason': 'state_workspace_unavailable'};
    }
    final workspace = await _checked(factory);
    final fixture = profile.fixtures['state_persistence'] as Map;
    final prefix = fixture['prefix'] as String;
    final suffix = fixture['suffix'] as String;
    final full = prefix + suffix;
    final phases = <Map<String, dynamic>>[];
    final evidence = <String, dynamic>{
      ...capability,
      'model_sha256': profile.model['sha256'],
      'config_hash': jsonHash(profile.effectiveConfig),
      'phases': phases,
    };
    _partialCaseEvidence = evidence;
    var lifetime = 0;
    Future<Map<String, dynamic>> fresh(
      String role,
      Future<void> Function(Map<String, dynamic>) body,
    ) async {
      _operationPhase = 'state.$role';
      await _checked(engine.dispose);
      await _checked(() => engine.load(location, profile));
      final row = <String, dynamic>{
        'role': role,
        'lifetime': ++lifetime,
        'model_sha256': profile.model['sha256'],
        'config_hash': jsonHash(profile.effectiveConfig),
        'diagnostics': await _checked(engine.diagnostics),
      };
      phases.add(row);
      try {
        await body(row);
      } finally {
        await _checked(engine.dispose);
        row['disposed'] = true;
      }
      return row;
    }

    List<int> tokens = [];
    List<int> candidates = [];
    Uint8List savedBytes = Uint8List(0);
    Future<void> restore(Map<String, dynamic> row) async {
      row['snapshot_sha256'] = evidence['artifact'] is Map
          ? (evidence['artifact'] as Map)['sha256']
          : null;
      row['capacity'] = profile.contextSize;
      row['loaded_tokens'] = await _checked(
        () => state.loadState(workspace.path('valid'), profile.contextSize),
      );
    }

    Future<void> score(
      Map<String, dynamic> row,
      String text,
      bool reuse,
    ) async {
      row['prompt'] = text;
      row['reuse'] = reuse;
      row['score'] = await _checked(
        () =>
            state.scoreStatePrompt(text, candidates: candidates, reuse: reuse),
      );
    }

    Future<void> generate(
      Map<String, dynamic> row,
      String text,
      bool reuse,
    ) async {
      row['prompt'] = text;
      row['reuse'] = reuse;
      row['generation'] = await _checked(
        () => state.generateStatePrompt(text, reuse: reuse),
      );
    }

    Map<String, dynamic> identityJson(LlamaStateIdentity identity) => {
      'runtime_build': identity.runtimeBuild,
      'session_format_version': identity.sessionFormatVersion,
      'context_size': identity.contextSize,
      'context_config_digest': identity.contextConfigDigest,
    };

    try {
      await fresh('source', (row) async {
        tokens = List<int>.of(
          await _checked(() => state.tokenizeStatePrompt(prefix)),
        );
        row['tokens'] = tokens;
        row['add_special'] = true;
        row['reuse'] = false;
        row['prompt'] = prefix;
        final baseline = await _checked(
          () => state.scoreStatePrompt(
            prefix,
            topK: fixture['top_k'] as int,
            reuse: false,
          ),
        );
        row['score'] = baseline;
        candidates = [
          for (final token in baseline['top'] as List)
            (token as Map)['token'] as int,
        ];
        if (id == 'P05.identity') {
          row['identity'] = identityJson(await _checked(state.stateIdentity));
        }
        row['saved'] = await _checked(
          () => state.saveState(workspace.path('valid'), tokens),
        );
        savedBytes = await _checked(() => workspace.read('valid'));
        evidence['artifact'] = {
          'role': 'valid',
          'header': savedBytes.take(8).toList(),
          'bytes': savedBytes.length,
          'sha256': sha256.convert(savedBytes).toString(),
        };
      });
      evidence['candidates'] = candidates;
      if (id == 'P02.roundtrip' || id == 'P05.identity') {
        await fresh('roundtrip', (row) async {
          if (id == 'P05.identity') {
            row['identity_before_load'] = identityJson(
              await _checked(state.stateIdentity),
            );
          }
          await restore(row);
          if (id == 'P05.identity') {
            row['identity'] = identityJson(await _checked(state.stateIdentity));
          }
        });
      } else {
        await fresh('reference_full', (row) async {
          row['tokens'] = await _checked(() => state.tokenizeStatePrompt(full));
          await score(row, full, false);
        });
        await fresh(
          'reference_suffix_only',
          (row) => score(row, suffix, false),
        );
        for (final item in [('score_exact', prefix), ('score_suffix', full)]) {
          await fresh(item.$1, (row) async {
            await restore(row);
            await score(row, item.$2, true);
          });
        }
        for (final item in [
          ('generate_exact', prefix, true, true),
          ('generate_suffix', full, true, true),
          ('control_fresh', full, false, true),
          ('control_reuse_disabled', full, true, false),
        ]) {
          await fresh(item.$1, (row) async {
            if (item.$3) await restore(row);
            await generate(row, item.$2, item.$4);
          });
        }
        if (id == 'P04.invalid_recovery') {
          final short = savedBytes
              .take(fixture['short_header_bytes'] as int)
              .toList();
          final incompatible = Uint8List.fromList(savedBytes);
          if (incompatible.length < 8) {
            throw StateError('Saved state lacks session header');
          }
          ByteData.sublistView(
            incompatible,
          ).setUint32(4, fixture['incompatible_version'] as int, Endian.little);
          await _checked(
            () => workspace.write(
              'garbage',
              (fixture['garbage'] as List).cast<int>(),
            ),
          );
          await _checked(() => workspace.write('short', short));
          await _checked(() => workspace.write('incompatible', incompatible));
          evidence['negative_artifacts'] = {
            'garbage': {
              'bytes': (fixture['garbage'] as List).length,
              'sha256': sha256
                  .convert((fixture['garbage'] as List).cast<int>())
                  .toString(),
            },
            'short': {
              'bytes': short.length,
              'sha256': sha256.convert(short).toString(),
              'inline_bytes': short,
            },
            'incompatible': {
              'bytes': incompatible.length,
              'sha256': sha256.convert(incompatible).toString(),
              'header': incompatible.take(8).toList(),
              'source_sha256': (evidence['artifact'] as Map)['sha256'],
              'recipe': 'replace_le_u32_at_4',
            },
          };
          for (final item in [
            ('missing', profile.contextSize),
            ('garbage', profile.contextSize),
            ('short', profile.contextSize),
            ('incompatible', profile.contextSize),
            ('capacity_zero', 0),
            ('capacity_oversized', profile.contextSize + 1),
            ('capacity_small', tokens.length - 1),
          ]) {
            await fresh('negative_${item.$1}', (row) async {
              final role = item.$1.startsWith('capacity_') ? 'valid' : item.$1;
              row['artifact_role'] = role;
              row['capacity'] = item.$2;
              try {
                row['returned_tokens'] = await _checked(
                  () => state.loadState(workspace.path(role), item.$2),
                );
                row['rejection'] = 'accepted';
              } catch (error) {
                row['rejection'] = error is LlamaArgumentException
                    ? 'LlamaArgumentException'
                    : error is LlamaStateException
                    ? 'LlamaStateException'
                    : error.runtimeType.toString();
              }
            });
            await fresh('recovery_score_${item.$1}', (row) async {
              await restore(row);
              await score(row, full, true);
            });
            await fresh('recovery_${item.$1}', (row) async {
              await restore(row);
              await generate(row, full, true);
            });
          }
        }
      }
    } finally {
      await workspace.dispose();
      evidence['workspace_disposed'] = true;
      // Later core lifecycle cases still expect a ready engine.
      await _checked(() => engine.load(location, profile));
    }
    final available = phases.where((row) => row['generation'] is Map).every((
      row,
    ) {
      final gen = row['generation'] as Map;
      return gen['observer_present'] == true &&
          gen['usage'] is Map &&
          gen['prompt_eval_tokens'] is int;
    });
    return {
      ...evidence,
      'status': !available
          ? 'NOT_RUN'
          : validStateCaseEvidence(
              id,
              evidence,
              profile,
              web: engine.isWeb,
              diagnostics: diagnostics,
            )
          ? 'PASS'
          : 'FAIL',
      if (!available) 'reason': 'state_public_counters_unavailable',
    };
  }
}
