/// Source-only prepared runner. Calling this performs model inference on Android.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart' as spi;
import 'package:llamadart/llamadart.dart';
// Same default-service boundary as the accepted macOS public qualifier.
// ignore: implementation_imports
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';

import 'android_qualification_io.dart';

import 'android_litert_qualification.dart';
import 'android_litert_qualification_io.dart';
import 'src/s24_litert_params.dart';

typedef S24LiteRtEmit = void Function(Map<String, dynamic> event);

/// Uses default service discovery and factories; the direct control is separate.
Future<void> runS24LiteRtQualification(
  Map<String, dynamic> config,
  S24LiteRtEmit emit,
) async {
  final producerClock = Stopwatch()..start();
  if (!Platform.isAndroid ||
      Abi.current() != Abi.androidArm64 ||
      config['pid'] != pid) {
    throw StateError('Fresh Android arm64 instrumentation arguments required');
  }
  final binding = Map<String, dynamic>.from(config['binding'] as Map);
  requireS24LiteRtBinding(binding);
  const compiledSource = String.fromEnvironment('S24_LITERT_SOURCE_COMMIT');
  const compiledInventory = String.fromEnvironment(
    'S24_LITERT_SOURCE_INVENTORY_SHA256',
  );
  if (compiledSource != binding['source_commit'] ||
      compiledInventory != binding['source_inventory_sha256']) {
    throw StateError('Compiled source differs from the admitted build');
  }
  final device = config['device'] as Map;
  if (device['model'] != 'SC-51E' ||
      device['api'] != 36 ||
      !'${device['soc']}'.contains('SM8650') ||
      '${device['build']}'.isEmpty) {
    throw StateError('Exact SC-51E/API36/SM8650 device required');
  }
  final directory = Directory(config['native_directory'] as String);
  final stage = Directory(config['stage'] as String);
  final output = Directory(config['output'] as String);
  final profiles = binding['profiles'] as Map;
  await requireS24LiteRtPayloads(directory, binding);
  for (final backend in ['cpu', 'gpu']) {
    await requireS24LiteRtFile(
      File('${stage.path}/$backend.litertlm'),
      (profiles[backend] as Map)['model'] as Map,
    );
  }
  final library = DynamicLibrary.open('${directory.path}/libLiteRtLm.so');
  final version = calloc<Int32>(3);
  try {
    final status = library
        .lookupFunction<
          Int32 Function(Pointer<Int32>, Pointer<Int32>, Pointer<Int32>),
          int Function(Pointer<Int32>, Pointer<Int32>, Pointer<Int32>)
        >('litert_lm_get_api_version')(version, version + 1, version + 2);
    if (status != 0 || version[0] != 1 || version[1] != 0 || version[2] < 0) {
      throw StateError('Actual mapped library does not provide C API 1.0.x');
    }
    emit({
      'event': 'identity',
      'binding': binding,
      'device': device,
      'c_api_version': [version[0], version[1], version[2]],
      'v1_selection_evidence':
          'derived_from_frozen_default_source_and_mapped_C_API_1_library',
      'v1_route_counters': 'not_exposed_not_measured',
      'public_raw_native_json': 'not_exposed_separate_direct_control_only',
      'public_finish': 'not_exposed_by_default_service',
      'required_case_ids': s24LiteRtCases,
      'stage_deadlines_seconds': s24LiteRtStageSeconds,
      'injected_runtime_factory': false,
      'backend_override': false,
      'mappings': await captureS24LiteRtMappings(directory, binding),
    });
  } finally {
    calloc.free(version);
  }

  String? active;
  var sequence = 0;
  void record(Map<String, dynamic> value) =>
      emit({'sequence': sequence++, 'case_id': active, ...value});
  void milestone(String phase, {String? library}) => record({
    'event': 'producer_phase',
    'phase': phase,
    'monotonic_elapsed_us': producerClock.elapsedMicroseconds,
    'library': ?library,
  });
  Future<Map<String, dynamic>> mappings() => captureS24LiteRtMappings(
    directory,
    binding,
    diagnostic: (phase, library) => milestone(phase, library: library),
  );
  final failures = <String>[];
  Future<void> run(String id, Future<void> Function(File stderr) body) async {
    active = id;
    record({'event': 'case_started'});
    final stderr = File('${output.path}/$id.stderr');
    final capture = S24LiteRtStderr.open(stderr);
    Object? error;
    try {
      await body(stderr);
    } on Object catch (caught) {
      error = caught;
    }
    // body retains unsettled work forever; the outer process owns its timeout.
    capture.close();
    final raw = await stderr.readAsBytes();
    record({
      'event': 'native_stderr',
      'capture': captureCompactS24LiteRtBytes(raw),
    });
    record({'event': 'mappings', ...await mappings()});
    if (error != null) failures.add(id);
    record({
      'event': 'case_result',
      'status': error == null ? 'PASS' : 'FAIL',
      if (error != null) 'error_type': error.runtimeType.toString(),
      if (error != null) 'error': '$error',
    });
    active = null;
  }

  Directory cache(String name) =>
      Directory('${stage.path}/$name-cache')..createSync();
  Future<void> retainIfUnsettled(
    spi.LiteRtLmNativeSettlement settlement,
  ) async {
    if (settlement != spi.LiteRtLmNativeSettlement.settled) {
      record({
        'event': 'cleanup_retained',
        'native_settlement': settlement.name,
      });
      await Completer<void>().future;
    }
  }

  bool guarded(Object error) =>
      '$error'.contains('Android GPU safety restriction') &&
      '$error'.contains(s24LiteRtGpuHash) &&
      '$error'.contains('134217728');

  final statuses = <String, String>{
    for (final id in s24LiteRtCases) id: 'NOT_RUN',
  };
  final executionHash = s24LiteRtHash(binding);
  final nativeAnswers = <String, Map<String, List<int>>>{};
  var stageSequence = 0;
  void phase(String name) {
    record({
      'event': 'stage_started',
      'stage': name,
      'stage_sequence': stageSequence++,
      'deadline_ms': s24LiteRtStageSeconds[name]! * 1000,
    });
  }

  final template = File('${stage.path}/template.jinja');
  if (await s24LiteRtFileHash(template) != binding['template_sha256'] ||
      await template.readAsString() != liteRtLmQwen3ChatTemplate) {
    throw StateError(
      'Native and public controls require the same maintained template',
    );
  }
  Future<bool> child(String id, String mode, String modelProfile) async {
    active = id;
    record({'event': 'case_started'});
    try {
      final captured = await captureAndroidNativeChild(
        executable: '${directory.path}/libllamadart_litert_child.so',
        arguments: [
          mode,
          '${directory.path}/libLiteRtLm.so',
          '${stage.path}/$modelProfile.litertlm',
          cache(id).path,
          template.path,
          executionHash,
          id,
        ],
        output: Directory('${output.path}/$id'),
        binding: executionHash,
        caseId: id,
        timeout: const Duration(seconds: 120),
        environment: {'LD_LIBRARY_PATH': directory.path},
      );
      final rawOut = await File(
        '${output.path}/$id/stdout.jsonl',
      ).readAsBytes();
      final rawErr = await File('${output.path}/$id/stderr.log').readAsBytes();
      record({
        'event': 'owned_child_capture',
        'receipt': captured,
        'stdout': captureCompactS24LiteRtBytes(rawOut),
        'stderr': captureCompactS24LiteRtBytes(rawErr),
        'shared_gguf_protocol_ignored': true,
      });
      final rows = readS24LiteRtChildRecords(
        captured,
        rawOut,
        rawErr,
        binding: executionHash,
        caseId: id,
      );
      if (rows.first['mode'] != mode) {
        throw StateError(
          'Owned native child mode differs from the fixed graph',
        );
      }
      if (mode == 'probe') {
        if (rows.length != 2 || rows.last['model_free_launch'] != true) {
          throw StateError('Owned child launch was not verified');
        }
      } else if (mode == 'guard') {
        if (rows.length != 2 ||
            rows.last['guard_refused'] != true ||
            !guarded(rows.last['native_error'] ?? '')) {
          throw StateError('Native legacy GPU guard missing');
        }
      } else {
        final generations = rows
            .where(
              (row) =>
                  row['event'] == 'generation' &&
                  row['native_json_hex'] is String,
            )
            .toList();
        if (generations.length != 2 || rows.last['engine_deleted'] != true) {
          throw StateError('Incomplete native control');
        }
        final maps = rows.where((row) => row['event'] == 'maps').toList();
        if (maps.length != 1) throw StateError('Missing native child mapping');
        final mapText = utf8.decode(
          readS24LiteRtHex(maps.single['raw_hex'] as String),
        );
        var coreSeen = false;
        for (final line in mapText.split('\n')) {
          final match = RegExp(
            r'(/[^\n]*\.so)(?: \(deleted\))?$',
          ).firstMatch(line);
          if (match == null) continue;
          final path = match.group(1)!;
          final name = Uri.file(path).pathSegments.last;
          if (!(binding['owner_libraries'] as Map).containsKey(name)) continue;
          if (path != '${directory.path}/$name') {
            throw StateError('Native child mapped another runtime');
          }
          await requireS24LiteRtFile(
            File(path),
            (binding['libraries'] as Map)[name] as Map,
          );
          if (name == 'libLiteRtLm.so') coreSeen = true;
        }
        if (!coreSeen) throw StateError('Native child core mapping absent');
        for (var index = 0; index < 2; index++) {
          final name = index == 0 ? 'hello' : 'arithmetic';
          final fixture = (profiles['cpu'] as Map)['fixtures'][name] as Map;
          final row = generations[index];
          final measured = rows
              .where(
                (value) =>
                    value['event'] == 'generation' &&
                    value['fixture'] == name &&
                    value.containsKey('input_tokens'),
              )
              .toList();
          if (measured.length != 1 ||
              measured.single['input_tokens'] is! int ||
              measured.single['input_tokens'] <= 0 ||
              measured.single['output_tokens'] is! int ||
              measured.single['output_tokens'] <= 0) {
            throw StateError(
              'Native C04 control lacks positive input/output counters',
            );
          }

          if (row['fixture'] != name || row['prompt'] != fixture['prompt']) {
            throw StateError('Changed native C04 fixture');
          }
          final raw = readS24LiteRtHex(row['native_json_hex'] as String);
          // Exact rawOut was persisted and embedded before any JSON interpretation.
          final answer = readS24LiteRtNativeAnswer(raw);
          record({
            'event': 'native_answer_observation',
            'fixture': name,
            'model_sha256': s24LiteRtCpuHash,
            'answer_capture': captureCompactS24LiteRtBytes(utf8.encode(answer)),
            'native_finish': 'not_exposed_by_sync_native_control',
          });
          requireS24LiteRtAnswer(name, utf8.encode(answer));
          nativeAnswers.putIfAbsent(mode, () => {})[name] = utf8.encode(answer);
        }
        if (mode == 'gpu') {
          record({
            'event': 'native_cpu_gpu_text_comparison',
            'fixtures': {
              for (final name in ['hello', 'arithmetic'])
                name: {
                  'cpu': captureCompactS24LiteRtBytes(
                    nativeAnswers['cpu']![name]!,
                  ),
                  'gpu': captureCompactS24LiteRtBytes(
                    nativeAnswers['gpu']![name]!,
                  ),
                  'byte_equal':
                      base64Encode(nativeAnswers['cpu']![name]!) ==
                      base64Encode(nativeAnswers['gpu']![name]!),
                },
            },
            'oracle': 'unchanged_C04_positive_oracles',
          });
        }
        if (mode == 'gpu') {
          record({
            'event': 'native_gpu_initialization',
            'backend': s24LiteRtGpuInitializationBackend(
              utf8.decode(rawErr, allowMalformed: true),
            ),
            'gpu_per_request_execution': 'not_observed',
          });
        }
        if (mode == 'gpu' &&
            !s24LiteRtGpuInitialized(
              utf8.decode(rawErr, allowMalformed: true),
            )) {
          throw StateError(
            'Native corrected GPU control lacks correlated Vulkan or full OpenCL delegate initialization',
          );
        }
      }
      statuses[id] = 'PASS';
    } on Object catch (error) {
      statuses[id] = 'FAIL';
      failures.add(id);
      record({
        'event': 'case_error',
        'error': '$error',
        'error_type': error.runtimeType.toString(),
      });
    }
    record({'event': 'case_result', 'status': statuses[id]});
    active = null;
    return statuses[id] == 'PASS';
  }

  phase('native-guard');
  final launch = await child('s24.native.launch', 'probe', 'cpu');
  if (!launch) {
    throw StateError(
      'Installed owned native child could not launch; no inference attempted',
    );
  }
  final guardPassed = await child('s24.native.gpu-guard', 'guard', 'gpu');
  if (!guardPassed) {
    record({
      'event': 'dependent_cases_not_run',
      'case_ids': s24LiteRtCases
          .where((id) => statuses[id] == 'NOT_RUN')
          .toList(),
      'reason':
          'native_legacy_GPU_guard_failed_no_dependent_public_GPU_attempt',
    });
    throw StateError('Native legacy GPU safety guard failed');
  }
  phase('public-gpu-refusal');
  LiteRtLmService service() =>
      LiteRtLmService(useTempCacheDir: false)..setLogLevel(LlamaLogLevel.debug);
  ModelParams params(ComputeDevice device, String name) =>
      s24LiteRtPublicParams(device, cacheDir: cache(name).path);
  await run('public.legacy.gpu-refusal', (_) async {
    final selected = service();
    if (!selected.reportsFinishReasons()) {
      throw StateError(
        'Default discovery did not admit the bound v1 finish capability',
      );
    }
    record({'event': 'default_discovery_probe', 'mappings': await mappings()});
    Object? refusal;
    try {
      final options = params(ComputeDevice.gpu, 'public-gpu');
      final model = await selected.loadModel(
        '${stage.path}/gpu.litertlm',
        options,
      );
      final context = selected.createContext(model, options);
      await for (final chunk in selected.generateChat(
        context,
        [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text:
                (profiles['gpu'] as Map)['fixtures']['hello']['prompt']
                    as String,
          ),
        ],
        const GenerationParams(maxTokens: 32, temp: 0, seed: 1),
        enableThinking: false,
      )) {
        record({
          'event': 'public_chunk',
          'boundary': 'default_service_UTF8',
          'capture': captureCompactS24LiteRtBytes(chunk),
        });
      }
    } on Object catch (error) {
      refusal = error;
    } finally {
      await retainIfUnsettled(selected.nativeSettlement);
      selected.dispose();
    }
    record({
      'event': 'public_refusal',
      'typed_unsupported': refusal is LlamaUnsupportedException,
      'requested_backend': 'gpu',
      'model_sha256': s24LiteRtGpuHash,
      'error': '$refusal',
    });
    if (refusal is! LlamaUnsupportedException || !guarded(refusal)) {
      throw StateError(
        'Explicit public GPU did not preserve typed native refusal',
      );
    }
  });
  statuses['public.legacy.gpu-refusal'] =
      failures.contains('public.legacy.gpu-refusal') ? 'FAIL' : 'PASS';

  final legacySemanticFailures = <String>[];
  Map<String, dynamic>? processCpuDelegateInitialization;
  Future<void> publicGroup(
    String route,
    String profileName,
    ComputeDevice device, {
    bool legacy = false,
  }) async {
    final selectedProfile = profiles[profileName] as Map;
    final warnings = <String>[];
    await LlamaLogging.configure(
      level: LlamaLogLevel.info,
      handler: (value) {
        warnings.add(value.message);
        record({
          'event': 'dart_log',
          'level': value.level.name,
          'message': value.message,
          if (value.error != null) 'error': '${value.error}',
        });
      },
    );
    LiteRtLmService? selected;
    try {
      for (final lifetime in [1, 2]) {
        selected = service();
        if (!selected.reportsFinishReasons()) {
          throw StateError(
            'Default discovery did not admit the bound v1 finish capability',
          );
        }
        record({
          'event': 'default_discovery_probe',
          'mappings': await mappings(),
        });
        final prefix = '$route.$lifetime';
        final stderr = File('${output.path}/$prefix.lifetime.stderr');
        if (stderr.existsSync()) {
          throw StateError('A lifetime cannot reuse an old native log');
        }
        final capture = S24LiteRtStderr.open(stderr);
        record({
          'event': 'lifetime_started',
          'lifetime_id': prefix,
          'native_log_empty': stderr.lengthSync() == 0,
        });
        warnings.clear();
        try {
          final options = params(device, prefix);
          final model = await selected.loadModel(
            '${stage.path}/$profileName.litertlm',
            options,
          );
          final context = selected.createContext(model, options);
          Map<String, dynamic>? completedGpuObservation;
          for (final entry in (selectedProfile['fixtures'] as Map).entries) {
            active = '$prefix.${entry.key}';
            record({'event': 'case_started'});
            Object? failure;
            try {
              final chunks = <List<int>>[];
              await for (final chunk in selected.generateChat(
                context,
                [
                  LlamaChatMessage.fromText(
                    role: LlamaChatRole.user,
                    text: (entry.value as Map)['prompt'] as String,
                  ),
                ],
                const GenerationParams(maxTokens: 32, temp: 0, seed: 1),
                enableThinking: false,
              )) {
                chunks.add(List<int>.of(chunk));
                record({
                  'event': 'public_chunk',
                  'boundary': 'default_service_UTF8',
                  'capture': captureCompactS24LiteRtBytes(chunk),
                });
              }
              record({
                'event': 'producer_phase',
                'phase': 'public_stream_completed',
                'monotonic_elapsed_us': producerClock.elapsedMicroseconds,
                'native_settlement': selected.nativeSettlement.name,
              });
              final bytes = chunks.expand((value) => value).toList();
              final metrics = selected.getPerformanceContext(context);
              milestone('public_metrics_completed');
              final native = await stderr.readAsBytes();
              final maps = await mappings();
              if (processCpuDelegateInitialization == null &&
                  utf8
                      .decode(native, allowMalformed: true)
                      .contains(
                        'Created TensorFlow Lite XNNPACK delegate for CPU.',
                      )) {
                processCpuDelegateInitialization = {
                  'pid': pid,
                  'lifetime_id': prefix,
                  'capture': captureCompactS24LiteRtBytes(native),
                };
                record({
                  'event': 'process_cpu_delegate_initialization',
                  'evidence': processCpuDelegateInitialization,
                });
              }

              final observation = <String, dynamic>{
                'event': 'public_observation',
                'lifetime': lifetime,
                'requested_device': device.name,
                'model_profile': profileName,
                'model_sha256': (selectedProfile['model'] as Map)['sha256'],
                'answer_capture': captureCompactS24LiteRtBytes(bytes),
                'native_finish': 'not_exposed_by_default_service',
                'native_settlement': selected.nativeSettlement.name,
                'backend_name': selected.getActiveBackendName(),
                'reported_gpu_layers': selected.getResolvedGpuLayers(),
                'input_tokens': metrics?.promptEvalTokens,
                'output_tokens': metrics?.evalTokens,
                'warnings': List<String>.of(warnings),
                'public_process_pid': pid,
                'process_cpu_delegate_initialization':
                    processCpuDelegateInitialization,
                'native_gpu_initialization_backend':
                    s24LiteRtGpuInitializationBackend(
                      utf8.decode(native, allowMalformed: true),
                    ),
                'native_gpu_initialization': s24LiteRtGpuInitialized(
                  utf8.decode(native, allowMalformed: true),
                ),
                'mapped_core_verified': (maps['verified'] as List).contains(
                  'libLiteRtLm.so',
                ),
                'native_stderr': {
                  ...captureCompactS24LiteRtBytes(native),
                  'lifetime_id': prefix,
                  'empty_at_load': true,
                },
                'mappings': maps,
                'gpu_per_request_execution': 'not_observed',
              };
              record(observation);
              var semantic = true;
              try {
                requireS24LiteRtAnswer(entry.key as String, bytes);
              } on FormatException {
                semantic = false;
              }
              record({
                'event': 'semantic_oracle',
                'passed': semantic,
                'legacy_observation_only': legacy,
              });
              if (!semantic && legacy) legacySemanticFailures.add(active!);
              if (!semantic && !legacy) {
                throw StateError(
                  'Fixed corrected-model C04 semantic oracle failed',
                );
              }
              if (device == ComputeDevice.cpu || legacy) {
                requireS24LiteRtCpuObservation(
                  observation,
                  automatic: device == ComputeDevice.auto,
                  lifetimeId: prefix,
                );
              } else {
                requireS24LiteRtGpuObservation(observation, lifetimeId: prefix);
                completedGpuObservation = observation;
              }
              if (utf8.decode(bytes).trim().isEmpty) {
                throw StateError('Empty public transport');
              }
            } on Object catch (error) {
              failure = error;
              failures.add(active!);
            }
            statuses[active!] = failure == null ? 'PASS' : 'FAIL';
            record({
              'event': 'case_result',
              'status': statuses[active],
              if (failure != null) 'error': '$failure',
            });
          }
          if (lifetime == 1) {
            active = '$route.cancel';
            record({'event': 'case_started'});
            var cancelled = false;
            final chunks = <List<int>>[];
            await for (final chunk in selected.generateChat(
              context,
              const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text:
                      'Write the numbers 1 through 1000, one per line. Start immediately.',
                ),
              ],
              const GenerationParams(maxTokens: 512, temp: 0, seed: 1),
              enableThinking: false,
            )) {
              chunks.add(List<int>.of(chunk));
              record({
                'event': 'public_chunk',
                'boundary': 'default_service_UTF8',
                'capture': captureCompactS24LiteRtBytes(chunk),
              });
              if (!cancelled && chunk.isNotEmpty) {
                selected.cancelGeneration();
                cancelled = true;
              }
            }
            record({
              'event': 'producer_phase',
              'phase': 'public_cancel_stream_completed',
              'monotonic_elapsed_us': producerClock.elapsedMicroseconds,
              'native_settlement': selected.nativeSettlement.name,
            });
            record({
              'event': 'public_cancel',
              'cancel_sent': cancelled,
              'answer_capture': captureCompactS24LiteRtBytes(
                chunks.expand((value) => value).toList(),
              ),
              'native_finish': 'not_exposed_by_default_service',
              'native_settlement': selected.nativeSettlement.name,
            });
            var pass =
                cancelled &&
                selected.nativeSettlement ==
                    spi.LiteRtLmNativeSettlement.settled;
            if (device == ComputeDevice.auto && !legacy) {
              try {
                final native = await stderr.readAsBytes();
                final log = utf8.decode(native);
                final gpu = <String, dynamic>{
                  ...?completedGpuObservation,
                  'backend_name': selected.getActiveBackendName(),
                  'reported_gpu_layers': selected.getResolvedGpuLayers(),
                  'native_settlement': selected.nativeSettlement.name,
                  'warnings': List<String>.of(warnings),
                  'native_gpu_initialization': s24LiteRtGpuInitialized(log),
                  'native_gpu_initialization_backend':
                      s24LiteRtGpuInitializationBackend(log),
                  'native_stderr': {
                    ...captureCompactS24LiteRtBytes(native),
                    'lifetime_id': prefix,
                    'empty_at_load': true,
                  },
                };
                record({
                  'event': 'public_cancel_gpu_observation',
                  'counters_source': 'preceding_completed_C04',
                  'observation': gpu,
                });
                requireS24LiteRtGpuObservation(gpu, lifetimeId: prefix);
              } on Object catch (error) {
                pass = false;
                record({
                  'event': 'public_cancel_gpu_failed',
                  'error': '$error',
                });
              }
            }
            statuses[active!] = pass ? 'PASS' : 'FAIL';
            if (!pass) failures.add(active!);
            record({'event': 'case_result', 'status': statuses[active]});
          }
        } finally {
          await retainIfUnsettled(selected.nativeSettlement);
          milestone('lifetime_dispose_started');
          selected.dispose();
          milestone('lifetime_dispose_completed');
          selected = null;
          capture.close();
          record({
            'event': 'lifetime_closed',
            'route': route,
            'lifetime': lifetime,
            'native_stderr': captureCompactS24LiteRtBytes(
              await stderr.readAsBytes(),
            ),
          });
          active = null;
        }
      }
    } on Object catch (error) {
      failures.add(route);
      record({'event': 'group_failed', 'route': route, 'error': '$error'});
    } finally {
      if (selected != null) {
        await retainIfUnsettled(selected.nativeSettlement);
        selected.dispose();
      }
      await LlamaLogging.configure();
    }
  }

  phase('native-cpu-corrected');
  final nativeCpu = await child('s24.native.cpu-corrected', 'cpu', 'cpu');
  phase('public-cpu-corrected');
  await publicGroup('cpu-corrected', 'cpu', ComputeDevice.cpu);
  if (statuses['public.legacy.gpu-refusal'] == 'PASS') {
    phase('public-auto-legacy');
    await publicGroup('auto-legacy', 'gpu', ComputeDevice.auto, legacy: true);
  } else {
    record({
      'event': 'dependent_cases_not_run',
      'case_ids': s24LiteRtCases
          .where((id) => id.startsWith('auto-legacy'))
          .toList(),
      'reason': 'explicit_public_legacy_GPU_refusal_failed',
    });
  }
  var nativeGpu = false;
  if (nativeCpu) {
    phase('native-gpu-corrected');
    nativeGpu = await child('s24.native.gpu-corrected', 'gpu', 'cpu');
  }
  if (nativeGpu) {
    phase('public-auto-corrected');
    await publicGroup('auto-corrected', 'cpu', ComputeDevice.auto);
  } else {
    record({
      'event': 'dependent_cases_not_run',
      'case_ids': s24LiteRtCases
          .where((id) => id.startsWith('auto-corrected'))
          .toList(),
      'reason':
          'corrected_native_GPU_control_failed_or_unexecuted_no_public_GPU_attempt',
    });
  }
  phase('cleanup-and-export');
  final notRun = statuses.entries
      .where((entry) => entry.value == 'NOT_RUN')
      .map((entry) => entry.key)
      .toList();
  emit({
    'event': 'complete',
    'failed_cases': failures,
    'unexecuted_required_cases': notRun,
    'case_statuses': statuses,
    'legacy_semantic_failures': legacySemanticFailures,
    'legacy_semantic_accuracy_qualified':
        legacySemanticFailures.isEmpty &&
        s24LiteRtCases
            .where((id) => id.startsWith('auto-legacy.'))
            .every((id) => statuses[id] == 'PASS'),
    'corrected_semantic_accuracy_qualified': failures.isEmpty && notRun.isEmpty,
    'scope': 'exact_S24_native_controls_and_uninjected_default_service_only',
    'gpu_per_request_execution_qualified': false,
    'public_finish': 'not_exposed_by_default_service',
  });
  if (failures.isNotEmpty || notRun.isNotEmpty) {
    throw StateError('S24 required gates failed or remain unexecuted');
  }
}
