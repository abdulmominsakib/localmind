// Real-model child; only the maintained outer scenario owns its deadline.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_sampler_params.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';

import '../support/litert_lm_v1_thinking_qualification.dart';
import '../support/litert_lm_v1_thinking_owner.dart';
import '../support/litert_lm_thinking_input_observer.dart';
import '../support/litert_lm_thinking_direct_cache.dart';

void event(String stage, [Map<String, Object?> data = const {}]) => stdout
    .writeln('$thinkingEventPrefix${jsonEncode({'stage': stage, ...data})}');
Future<String> digest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
String hex(List<int> bytes) =>
    bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

Map<String, Object?> effectiveSampler({double? repetitionPenalty}) => {
  'temperature': 0,
  'top_k': liteRtLmEffectiveTopK(temperature: 0, topK: 40),
  'top_p': 0.9,
  'seed': 1,
  'repetition_penalty_override': repetitionPenalty,
  'presence_penalty_override': null,
  'speculation': false,
};

Future<void> main(List<String> args) async {
  if (args.length != 8) {
    throw ArgumentError(
      'Expected library, model, both digests, runtime manifest/digest, scratch and source revision.',
    );
  }
  final libraryPath = args[0],
      modelPath = args[1],
      librarySha = args[2],
      modelSha = args[3];
  final clients = <LiteRtLmV1RuntimeClient>[];
  final owners = ThinkingOwnerTracker();
  LiteRtLmService? service;
  LiteRtLmV1RuntimeClient? direct;
  var success = false;
  try {
    if (modelSha != thinkingModelSha256) {
      throw StateError(
        'The fixed maintained Gemma model identity is required.',
      );
    }
    if (await digest(libraryPath) != librarySha) {
      throw StateError('Core library SHA256 did not match.');
    }
    if (await digest(args[4]) != args[5]) {
      throw StateError('Runtime manifest SHA256 did not match.');
    }
    final manifest = thinkingRuntimeManifest(
      await File(args[4]).readAsString(),
    );
    final directory = File(libraryPath).parent.resolveSymbolicLinksSync();
    final coreName = File(libraryPath).uri.pathSegments.last;
    if (!manifest.any(
      (item) => item.name == coreName && item.sha256 == librarySha,
    )) {
      throw StateError('Manifest does not bind the selected core.');
    }
    final actualNames = Directory(directory)
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dylib'))
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    if (actualNames.length != manifest.length ||
        !actualNames.containsAll(manifest.map((entry) => entry.name))) {
      throw StateError('Manifest must bind every adjacent runtime dylib.');
    }
    final payloads = <String, Map<String, Object>>{};
    for (final entry in manifest) {
      final file = File('$directory/${entry.name}');
      final path = file.resolveSymbolicLinksSync();
      if (File(path).parent.path != directory ||
          await file.length() != entry.bytes ||
          await digest(path) != entry.sha256) {
        throw StateError('Runtime payload identity mismatch: ${entry.name}.');
      }
      payloads[entry.name] = {
        'path': path,
        'bytes': entry.bytes,
        'sha256': entry.sha256,
      };
    }
    if (await File(modelPath).length() != thinkingModelBytes ||
        await digest(modelPath) != modelSha) {
      throw StateError('Fixed model bytes or SHA256 did not match.');
    }
    if (!Platform.isMacOS || Abi.current() != Abi.macosArm64) {
      throw LlamaUnsupportedException(
        'This prepared actual thinking qualifier requires macOS arm64.',
      );
    }
    final version = await Process.run('/usr/bin/sw_vers', ['-productVersion']);
    final major = int.tryParse('${version.stdout}'.trim().split('.').first);
    if (version.exitCode != 0 || major == null || major < 14) {
      throw LlamaUnsupportedException(
        'The prepared candidate requires macOS 14 or later.',
      );
    }
    final channel = readLiteRtLmBundleFirstChannelDetails(modelPath);
    if (channel?.name != 'thought' ||
        channel?.start != thinkingStart ||
        channel?.end != thinkingEnd) {
      throw StateError('Fixed Gemma first-channel metadata changed.');
    }
    for (final payload in payloads.values) {
      final dependencies = await Process.run('/usr/bin/otool', [
        '-L',
        payload['path'] as String,
      ]);
      if (dependencies.exitCode != 0) {
        throw StateError('Cannot inspect runtime dependencies.');
      }
      payload['dependencies'] = '${dependencies.stdout}'
          .split('\n')
          .skip(1)
          .where((line) => line.trim().isNotEmpty)
          .toList();
    }
    event('identity', {
      'source_revision': args[7],
      'library_sha256': librarySha,
      'runtime_payloads': payloads,
      'model_sha256': modelSha,
      'model_bytes': thinkingModelBytes,
      'model_revision': '6b78abd019e61a1ca4cbe3b212d2c9ce8ff38a94',
      'abi': Abi.current().toString(),
      'os': Platform.operatingSystemVersion,
      'backend': 'cpu',
      'threads': 2,
      'context_size': 4096,
      'fixed_output_cap': thinkingOutputCap,
      'prior_768_failures_preserved': true,
      'prompt': thinkingPrompt,
      'prompt_sha256': sha256.convert(utf8.encode(thinkingPrompt)).toString(),
      'requested_sampler': {
        'temperature': 0,
        'top_k': 40,
        'top_p': 0.9,
        'seed': 1,
        'penalty': 1.1,
        'presence_penalty': 0,
      },
      'planned_effective_setter_values': effectiveSampler(),
      'sampler_evidence':
          'Successful turn observations report production setter values after returned-status checks; native API has no sampler readback.',
      'accelerator_execution_verified': false,
    });
    final library = DynamicLibrary.open(libraryPath);
    Future<void> loadedImages(String stage) async {
      final process = DynamicLibrary.process();
      final count = process.lookupFunction<Uint32 Function(), int Function()>(
        '_dyld_image_count',
      )();
      final name = process
          .lookupFunction<
            Pointer<Utf8> Function(Uint32),
            Pointer<Utf8> Function(int)
          >('_dyld_get_image_name');
      final images = <Map<String, Object>>[];
      var unexpected = false;
      for (var index = 0; index < count; index++) {
        final pointer = name(index);
        if (pointer == nullptr) continue;
        final path = pointer.toDartString();
        if (path.startsWith('/System/') ||
            path.startsWith('/usr/lib/') ||
            !path.endsWith('.dylib')) {
          continue;
        }
        final file = File(path);
        final basename = file.uri.pathSegments.last;
        final resolved = file.resolveSymbolicLinksSync();
        final actualSha = await digest(resolved);
        final expected = payloads[basename];
        final admitted =
            expected != null &&
            expected['path'] == resolved &&
            expected['sha256'] == actualSha;
        images.add({
          'path': resolved,
          'bytes': await file.length(),
          'sha256': actualSha,
          'matches_manifest': admitted,
        });
        if (!admitted) unexpected = true;
      }
      event(stage, {'loaded_runtime_images': images});
      if (unexpected ||
          !images.any(
            (image) => image['path'] == payloads[coreName]!['path'],
          )) {
        throw StateError(
          'Actual loaded runtime images escaped the admitted payload family.',
        );
      }
    }

    final probe = LiteRtLmV1RuntimeClient(library);
    if (!probe.supportsThinkingBudget ||
        !probe.supportsFinishReasons ||
        !probe.supportsMessageRendering) {
      throw StateError('Loaded core lacks thinking/finish/render contracts.');
    }
    probe.dispose();
    final versionParts = calloc<Int>(3);
    try {
      final status = library
          .lookupFunction<
            Int Function(Pointer<Int>, Pointer<Int>, Pointer<Int>),
            int Function(Pointer<Int>, Pointer<Int>, Pointer<Int>)
          >(
            'litert_lm_get_api_version',
          )(versionParts, versionParts + 1, versionParts + 2);
      event('loaded_contract', {
        'version_status': status,
        'c_api': [versionParts[0], versionParts[1], versionParts[2]],
        'callback_abi': library
            .lookupFunction<Int32 Function(), int Function()>(
              'stream_proxy_callback_abi_version',
            )(),
        'finish_reason_abi': library
            .lookupFunction<Int32 Function(), int Function()>(
              'stream_proxy_finish_reason_abi_version',
            )(),
      });
      if (status != 0) throw StateError('Version probe failed.');
    } finally {
      calloc.free(versionParts);
    }
    final scratch = Directory(args[6]);
    var sendStage = 'unexpected';
    service = LiteRtLmService(
      runtimeClientFactory: () {
        final client = createTrackedThinkingClient(library, owners);
        clients.add(client);
        return ThinkingInputObserver(client, (input) {
          event('${sendStage}_input', input);
          if (sendStage == 'unbounded_baseline') {
            requireThinkingBaselineInput(input);
          }
        });
      },
      linkParentDirectory: Directory('${scratch.path}/links')
        ..createSync(recursive: true),
      useTempCacheDir: false,
    );
    final active = service;
    final params = ModelParams(
      liteRtLmBackend: LiteRtLmBackendPreference.cpu,
      numberOfThreads: 2,
      contextSize: 4096,
      liteRtLmCacheDir: '${scratch.path}/cache',
    );
    var model = await active.loadModel(modelPath, params);
    var context = active.createContext(model, params);
    final startIds = await active.tokenize(model, thinkingStart, false);
    final endIds = await active.tokenize(model, thinkingEnd, false);
    final decodedStart = await active.detokenize(model, startIds, false);
    final decodedEnd = await active.detokenize(model, endIds, false);
    event('boundaries', {
      'name': channel!.name,
      'reasoning_flag': channel.isReasoning,
      'start': channel.start,
      'end': channel.end,
      'start_ids': startIds,
      'end_ids': endIds,
      'decoded_start': decodedStart,
      'decoded_end': decodedEnd,
    });
    if (startIds.isEmpty ||
        endIds.isEmpty ||
        startIds.any((id) => id < 0) ||
        endIds.any((id) => id < 0) ||
        jsonEncode(startIds) == jsonEncode(endIds) ||
        decodedStart != thinkingStart ||
        decodedEnd != thinkingEnd) {
      throw StateError(
        'Actual native tokenizer did not preserve whole Gemma markers.',
      );
    }
    await loadedImages('loaded_before_generation');
    Future<String> run(String stage, {int? budget, String? baseline}) async {
      // Native creation is lazy; this binds the actual engine, not a capability probe.
      await active.tokenize(model, thinkingStart, false);
      final turnOwner = owners.capture();
      sendStage = stage;
      final bytes = <int>[];
      try {
        await for (final chunk in active.generateChat(
          context,
          const [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: thinkingPrompt,
            ),
          ],
          GenerationParams(
            maxTokens: thinkingOutputCap,
            temp: 0,
            seed: 1,
            thinkingBudget: budget == null
                ? null
                : ThinkingBudget(maxTokens: budget),
          ),
          enableThinking: true,
        )) {
          bytes.addAll(chunk);
        }
      } finally {
        event('${stage}_raw', {
          'assembled_output_utf8_hex': hex(bytes),
          'assembled_output_text': utf8.decode(bytes, allowMalformed: true),
        });
      }
      final text = utf8.decode(bytes);
      final split = splitThinkingOutput(text);
      final ids = await active.tokenize(model, split.reasoning, false);
      final metrics = active.getPerformanceContext(context);
      final observation = owners.observe(turnOwner);
      final finish = observation.finish;
      if (active.nativeSettlement.name != observation.settlement) {
        throw StateError('Service and actual turn owner settlement disagree.');
      }
      event(stage, {
        'budget': budget,
        'effective_setter_values': effectiveSampler(),
        'reasoning': split.reasoning,
        'final_content': split.content,
        'reasoning_ids': ids,
        'reasoning_tokens': ids.length,
        'engine_epoch': observation.engineEpoch,
        'native_finish': finish,
        'owner_native_settlement': observation.settlement,
        'native_settlement': active.nativeSettlement.name,
        'metrics': metrics == null
            ? null
            : {
                'input_tokens': metrics.promptEvalTokens,
                'output_tokens': metrics.evalTokens,
                'load_ms': metrics.loadMs,
                'prefill_ms': metrics.promptEvalMs,
                'decode_ms': metrics.evalMs,
              },
      });
      if (metrics == null ||
          metrics.promptEvalTokens <= 0 ||
          metrics.evalTokens <= 0 ||
          [
            metrics.loadMs,
            metrics.promptEvalMs,
            metrics.evalMs,
          ].any((value) => !value.isFinite || value < 0)) {
        throw StateError('Invalid native metrics.');
      }
      requireThinkingResult(
        reasoningTokens: ids.length,
        finalContent: split.content,
        finish: finish,
        settlement: observation.settlement,
        budget: budget,
      );
      if (baseline != null) requireThinkingReuse(baseline, text);
      return text;
    }

    final baseline = await run('unbounded_baseline');
    await run('bounded_12', budget: 12);
    await run('after_bounded', baseline: baseline);
    await active.tokenize(model, thinkingStart, false);
    final cancelOwner = owners.capture();
    sendStage = 'cancel';
    var requested = false;
    final cancelledBytes = <int>[];
    try {
      await for (final chunk in active.generateChat(
        context,
        const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: thinkingPrompt,
          ),
        ],
        const GenerationParams(
          maxTokens: thinkingOutputCap,
          temp: 0,
          seed: 1,
          penalty: 1.5,
          thinkingBudget: ThinkingBudget(maxTokens: 4),
        ),
        enableThinking: true,
      )) {
        cancelledBytes.addAll(chunk);
        if (!requested && chunk.isNotEmpty) {
          final observation = owners.observe(cancelOwner);
          if (observation.settlement != 'pending') {
            throw StateError('Actual cancellation owner was not pending.');
          }
          active.cancelGeneration();
          requested = true;
        }
      }
    } finally {
      event('cancel_raw', {
        'assembled_output_utf8_hex': hex(cancelledBytes),
        'assembled_output_text': utf8.decode(
          cancelledBytes,
          allowMalformed: true,
        ),
      });
    }
    final cancelObservation = owners.observe(cancelOwner);
    if (active.nativeSettlement.name != cancelObservation.settlement) {
      throw StateError('Service and cancellation owner settlement disagree.');
    }
    final cancelMetrics = active.getPerformanceContext(context);
    event('cancel', {
      'requested': requested,
      'received_bytes': cancelledBytes.length,
      'effective_setter_values': effectiveSampler(repetitionPenalty: 1.5),
      'metrics': cancelMetrics == null
          ? null
          : {
              'input_tokens': cancelMetrics.promptEvalTokens,
              'output_tokens': cancelMetrics.evalTokens,
              'load_ms': cancelMetrics.loadMs,
              'prefill_ms': cancelMetrics.promptEvalMs,
              'decode_ms': cancelMetrics.evalMs,
            },
      'engine_epoch': cancelObservation.engineEpoch,
      'native_finish': cancelObservation.finish,
      'owner_native_settlement': cancelObservation.settlement,
      'native_settlement': active.nativeSettlement.name,
    });
    requireThinkingCancelled(
      requested: requested,
      receivedBytes: cancelledBytes.length,
      finish: cancelObservation.finish,
      settlement: cancelObservation.settlement,
    );
    await run('after_cancel', baseline: baseline);
    final oldModel = model, oldContext = context;
    model = await active.loadModel(modelPath, params);
    context = active.createContext(model, params);
    if (model == oldModel || context == oldContext) {
      throw StateError('Reload reused service handles.');
    }
    await run('reload_unbounded', baseline: baseline);
    await run('reload_bounded_12', budget: 12);
    active.dispose();
    service = null;
    final directCache = createThinkingDirectCache(scratch);
    direct = LiteRtLmV1RuntimeClient(library);
    await direct.initialize(
      modelPath: modelPath,
      backend: 'cpu',
      numberOfThreads: 2,
      maxTokens: 4096,
      cacheDir: directCache.path,
      speculativeDecoding: false,
    );
    direct.createConversation(
      extraContext: {'enable_thinking': false},
      temperature: 0,
      topK: 40,
      topP: 0.9,
      seed: 1,
    );
    var refused = false;
    try {
      direct.generateMessageJson(
        '{"role":"user","content":"$thinkingPrompt"}',
        thinkingTokenBudget: 12,
      );
    } on LlamaUnsupportedException {
      refused = true;
    }
    event('disabled_context', {
      'typed_unsupported': refused,
      'native_settlement': direct.nativeSettlement.name,
    });
    if (!refused ||
        direct.nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw StateError('Disabled context did not refuse the explicit budget.');
    }
    direct.createConversation(
      extraContext: {'enable_thinking': true},
      temperature: 0,
      topK: 40,
      topP: 0.9,
      seed: 1,
    );
    final message = <String, dynamic>{
      'role': 'user',
      'content': [
        {'type': 'text', 'text': thinkingPrompt},
      ],
    };
    final rendered = direct.renderMessageToString(message);
    event('direct_reuse_prompt', {
      'rendered_prompt': rendered,
      'rendered_prompt_utf8_hex': hex(utf8.encode(rendered)),
      'rendered_prompt_sha256': sha256
          .convert(utf8.encode(rendered))
          .toString(),
      'rendered_prompt_native_token_ids_without_added_start': direct.tokenize(
        rendered,
        addSpecial: false,
      ),
      'effective_conversation_sampler': effectiveSampler(),
      'requested_max_output_tokens': thinkingOutputCap,
      'requested_thinking_budget': 12,
    });
    final directBytes = <int>[];
    final clock = Stopwatch()..start();
    try {
      await for (final text in direct.generateMessageJson(
        jsonEncode(message),
        maxOutputTokens: thinkingOutputCap,
        thinkingTokenBudget: 12,
      )) {
        directBytes.addAll(utf8.encode(text));
      }
    } finally {
      event('direct_reuse_raw', {
        'assembled_output_utf8_hex': hex(directBytes),
        'assembled_output_text': utf8.decode(directBytes, allowMalformed: true),
      });
    }
    clock.stop();
    final split = splitThinkingOutput(utf8.decode(directBytes));
    final ids = direct.tokenize(split.reasoning, addSpecial: false);
    final metrics = direct.readMetrics(
      wallMilliseconds: clock.elapsedMilliseconds,
    );
    event('direct_reuse_bounded_12', {
      'budget': 12,
      'effective_setter_values': effectiveSampler(),
      'reasoning': split.reasoning,
      'final_content': split.content,
      'reasoning_ids': ids,
      'reasoning_tokens': ids.length,
      'native_finish': direct.lastFinishReason?.name,
      'native_settlement': direct.nativeSettlement.name,
      'metrics': metrics.toJson(),
    });
    if (metrics.inputTokens <= 0 || metrics.outputTokens <= 0) {
      throw StateError('Direct reuse native metrics were empty.');
    }
    requireThinkingResult(
      reasoningTokens: ids.length,
      finalContent: split.content,
      finish: direct.lastFinishReason?.name,
      settlement: direct.nativeSettlement.name,
      budget: 12,
    );
    await loadedImages('loaded_after_generation');
    final finalModelSha = await digest(modelPath);
    final finalPayloads = <String, String>{};
    for (final item in payloads.entries) {
      finalPayloads[item.key] = await digest(item.value['path'] as String);
    }
    event('input_recheck', {
      'model_sha256': finalModelSha,
      'runtime_payload_sha256': finalPayloads,
    });
    if (finalModelSha != modelSha ||
        finalPayloads.entries.any(
          (entry) => entry.value != payloads[entry.key]!['sha256'],
        )) {
      throw StateError('Input bytes changed during qualification.');
    }
    success = true;
  } on Object catch (error) {
    event('failure', {
      'type': error.runtimeType.toString(),
      'detail': error.toString().substring(
        0,
        error.toString().length.clamp(0, 512),
      ),
    });
  } finally {
    if ([service?.nativeSettlement, direct?.nativeSettlement].any(
      (state) => state != null && state != LiteRtLmNativeSettlement.settled,
    )) {
      event('cleanup_retained');
      await Completer<void>().future;
    }
    service?.dispose();
    direct?.dispose();
    for (final client in clients) {
      client.dispose();
    }
    event('cleanup', {'native_settlement': 'settled'});
  }
  event('run_end', {'success': success});
  exitCode = success ? 0 : 1;
}
