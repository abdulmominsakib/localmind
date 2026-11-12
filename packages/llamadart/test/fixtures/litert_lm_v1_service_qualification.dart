// Real-model child; only the owning outer scenario runs and bounds it.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_native_settlement.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_finish_reason.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';

import 'litert_lm_v1_schema_contract.dart';

const prefix = 'LITERT_V1_SERVICE_EVENT ';

void event(String stage, [Map<String, Object?> data = const {}]) {
  stdout.writeln('$prefix${jsonEncode({'stage': stage, ...data})}');
}

Future<String> digest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

Future<void> main(List<String> args) async {
  final schemaMode = args.length == 7 && args.last == 'json-schema';
  if (args.length != 6 && !schemaMode) {
    throw ArgumentError(
      'Expected library, model, both SHA256 digests, scratch and source revision.',
    );
  }
  final libraryPath = args[0],
      modelPath = args[1],
      librarySha = args[2],
      modelSha = args[3];
  final scratch = Directory(args[4]);
  LiteRtLmService? service;
  final clients = <LiteRtLmV1RuntimeClient>[];
  var success = false;
  try {
    if (schemaMode &&
        (modelSha != v1SchemaModelSha256 ||
            File(modelPath).lengthSync() != v1SchemaModelBytes)) {
      throw StateError(
        'Schema qualification requires the fixed published CPU profile model identity.',
      );
    }
    if (await digest(libraryPath) != librarySha ||
        await digest(modelPath) != modelSha) {
      throw StateError(
        'Expected runtime/model SHA256 did not match the supplied files.',
      );
    }
    if (schemaMode && (!Platform.isMacOS || Abi.current() != Abi.macosArm64)) {
      throw LlamaUnsupportedException(
        'Internal v1 JSON Schema qualification requires macOS arm64 CPU.',
      );
    }
    if (Platform.isMacOS) {
      final version = await Process.run('/usr/bin/sw_vers', [
        '-productVersion',
      ]);
      final major = int.tryParse('${version.stdout}'.trim().split('.').first);
      if (version.exitCode != 0 || major == null || major < 14) {
        throw LlamaUnsupportedException(
          'The prepared LiteRT v1 macOS artifact requires macOS 14.0 or later.',
        );
      }
    }
    event('identity', {
      'source_revision': args[5],
      'qualification_mode': schemaMode ? 'json-schema' : 'service',
      if (schemaMode)
        'schema_sha256': sha256
            .convert(utf8.encode(jsonEncode(v1SchemaDefinition)))
            .toString(),
      if (schemaMode)
        'prompt_sha256': sha256.convert(utf8.encode(v1SchemaPrompt)).toString(),
      'library_sha256': librarySha,
      'model_sha256': modelSha,
      'model_bytes': File(modelPath).lengthSync(),
      if (schemaMode) 'model_profile': 'chat-litert-cpu',
      'abi': Abi.current().toString(),
      'os': Platform.operatingSystemVersion,
      'requested_backend': 'cpu',
      'requested_threads': 2,
      'requested_context_size': 1024,
      'accelerator_execution_verified': false,
    });
    final library = DynamicLibrary.open(libraryPath);
    final probe = LiteRtLmV1RuntimeClient(library);
    if (!probe.supportsFinishReasons || !probe.supportsMessageRendering) {
      throw StateError(
        'Actual loaded v1 core lacks the required finish/render contract.',
      );
    }
    if (schemaMode && !probe.supportsJsonSchemaConstraints) {
      throw StateError(
        'Loaded v1 core lacks the complete JSON Schema/thinking-disable group.',
      );
    }
    probe.dispose();
    service = LiteRtLmService(
      runtimeClientFactory: () {
        final client = LiteRtLmV1RuntimeClient(library);
        clients.add(client);
        return client;
      },
      linkParentDirectory: Directory('${scratch.path}/links')
        ..createSync(recursive: true),
      useTempCacheDir: false,
    );
    final params = ModelParams(
      liteRtLmBackend: LiteRtLmBackendPreference.cpu,
      numberOfThreads: 2,
      contextSize: 1024,
      liteRtLmCacheDir: '${scratch.path}/cache',
    );
    final active = service;
    Future<void> arithmetic(int context, String stage) async {
      final bytes = <int>[];
      await for (final chunk in active.generateChat(
        context,
        const [
          LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text: 'What is 2 + 2? Reply with only the digit 4.',
          ),
        ],
        const GenerationParams(maxTokens: 32, temp: 0, seed: 7),
        enableThinking: false,
      )) {
        bytes.addAll(chunk);
      }
      final answer = utf8.decode(bytes).trim();
      if (answer != '4') {
        throw StateError(
          'Arithmetic oracle expected exactly 4; received ${answer.length} characters.',
        );
      }
      if (active.nativeSettlement != LiteRtLmNativeSettlement.settled) {
        throw StateError('Completed chat retained native work.');
      }
      final metrics = active.getPerformanceContext(context);
      if (metrics == null ||
          metrics.promptEvalTokens <= 0 ||
          metrics.evalTokens <= 0) {
        throw StateError(
          'Completed chat did not provide positive native token metrics.',
        );
      }
      for (final value in [
        metrics.loadMs,
        metrics.promptEvalMs,
        metrics.evalMs,
      ]) {
        if (!value.isFinite || value < 0) {
          throw StateError('Native metrics were invalid.');
        }
      }
      event(stage, {
        'answer': answer,
        'input_tokens': metrics.promptEvalTokens,
        'output_tokens': metrics.evalTokens,
        'load_ms': metrics.loadMs,
        'prefill_ms': metrics.promptEvalMs,
        'decode_ms': metrics.evalMs,
      });
    }

    const schemaMessages = [
      LlamaChatMessage.fromText(role: LlamaChatRole.user, text: v1SchemaPrompt),
    ];
    const schemaParams = GenerationParams(
      maxTokens: 128,
      temp: 0,
      topK: 1,
      topP: 1,
      penalty: 1,
      seed: 42,
    );
    Future<void> schemaRequest(
      int context,
      String stage, {
      bool constrained = true,
    }) async {
      final bytes = <int>[];
      final stream = constrained
          ? active.generateJsonSchemaChat(
              context,
              schemaMessages,
              schemaParams,
              jsonSchema: jsonEncode(v1SchemaDefinition),
            )
          : active.generateChat(
              context,
              schemaMessages,
              schemaParams,
              enableThinking: false,
            );
      try {
        await for (final chunk in stream) {
          bytes.addAll(chunk);
        }
      } finally {
        event('schema_observation', {
          'request': stage,
          'utf8_hex': bytes
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join(),
          'constrained': constrained,
          'requested_thinking': false,
        });
      }
      final answer = utf8.decode(bytes);
      final decoded = constrained ? requireV1SchemaTypedResponse(answer) : null;
      if (!constrained) requireV1SchemaPlainControl(answer);
      if (active.nativeSettlement != LiteRtLmNativeSettlement.settled ||
          clients.last.lastFinishReason != LiteRtLmFinishReason.stop ||
          active.lastGenerationLimit != null) {
        throw StateError(
          'Schema/control request did not settle with an actual normal stop.',
        );
      }
      final metrics = active.getPerformanceContext(context);
      if (metrics == null ||
          metrics.promptEvalTokens <= 0 ||
          metrics.evalTokens <= 0) {
        throw StateError(
          'Schema/control request lacks positive native token metrics.',
        );
      }
      for (final value in [
        metrics.loadMs,
        metrics.promptEvalMs,
        metrics.evalMs,
      ]) {
        if (!value.isFinite || value < 0) {
          throw StateError('Schema/control metrics are invalid.');
        }
      }
      event(stage, {
        'answer': answer,
        'decoded': ?decoded,
        'constrained': constrained,
        'requested_thinking': false,
        'native_finish': 'stop',
        'native_settlement': 'settled',
        'input_tokens': metrics.promptEvalTokens,
        'output_tokens': metrics.evalTokens,
      });
    }

    final firstModel = await active.loadModel(modelPath, params);
    final firstContext = active.createContext(firstModel, params);
    if (schemaMode) {
      await schemaRequest(firstContext, 'schema_control', constrained: false);
      await schemaRequest(firstContext, 'schema_chat');
      await schemaRequest(firstContext, 'schema_followup', constrained: false);
    } else {
      await arithmetic(firstContext, 'chat');
    }
    var cancellationSent = false;
    var received = 0;
    final cancellationBytes = <int>[];
    LiteRtLmV1RuntimeClient? cancelledClient;
    final cancellationStream = schemaMode
        ? active.generateJsonSchemaChat(
            firstContext,
            schemaMessages,
            schemaParams.copyWith(maxTokens: 512),
            jsonSchema: jsonEncode({
              'type': 'object',
              'properties': {
                'verdict': {
                  'type': 'string',
                  'const': List.filled(800, 'Z').join(),
                },
              },
              'required': ['verdict'],
              'additionalProperties': false,
            }),
          )
        : active.generateChat(
            firstContext,
            const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text:
                    'Write the numbers 1 through 1000, one per line. Start immediately.',
              ),
            ],
            const GenerationParams(maxTokens: 512, temp: 0, seed: 7),
            enableThinking: false,
          );
    try {
      await for (final chunk in cancellationStream) {
        received += chunk.length;
        if (schemaMode) cancellationBytes.addAll(chunk);
        if (!cancellationSent && chunk.isNotEmpty) {
          final pending = clients
              .where(
                (client) =>
                    client.nativeSettlement == LiteRtLmNativeSettlement.pending,
              )
              .toList();
          if (pending.length != 1) {
            throw StateError(
              'Cancellation did not observe exactly one active native client.',
            );
          }
          cancelledClient = pending.single;
          active.cancelGeneration();
          cancellationSent = true;
        }
      }
    } finally {
      if (schemaMode) {
        event('cancel_observation', {
          'utf8_hex': cancellationBytes
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join(),
          'cancellation_sent': cancellationSent,
          'native_finish': cancelledClient?.lastFinishReason?.name,
          'native_settlement': active.nativeSettlement.name,
        });
      }
    }
    if (!cancellationSent ||
        received == 0 ||
        active.nativeSettlement != LiteRtLmNativeSettlement.settled ||
        cancelledClient?.lastFinishReason != LiteRtLmFinishReason.cancelled) {
      throw StateError(
        'Real cancellation did not settle with the actual cancelled native cause.',
      );
    }
    event('cancel', {
      'received_bytes': received,
      'native_finish': 'cancelled',
      'native_settlement': 'settled',
    });
    if (schemaMode) await schemaRequest(firstContext, 'schema_after_cancel');
    final secondModel = await active.loadModel(modelPath, params);
    final secondContext = active.createContext(secondModel, params);
    if (secondModel == firstModel || secondContext == firstContext) {
      throw StateError('Reload reused the old service handles.');
    }
    if (schemaMode) {
      await schemaRequest(secondContext, 'reload_schema');
      await schemaRequest(secondContext, 'reload_followup', constrained: false);
    } else {
      await arithmetic(secondContext, 'reload_chat');
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
    if (service?.nativeSettlement != null &&
        service!.nativeSettlement != LiteRtLmNativeSettlement.settled) {
      event('cleanup_retained', {
        'native_settlement': service.nativeSettlement.name,
      });
      // The outer owner kills this process at its deadline. Do not run C exit
      // teardown or delete leases while native work may still use them.
      await Completer<void>().future;
    }
    service?.dispose();
    for (final client in clients) {
      client.dispose();
    }
    event('cleanup', {'native_settlement': 'settled'});
  }
  event('run_end', {'success': success});
  exitCode = success ? 0 : 1;
}
