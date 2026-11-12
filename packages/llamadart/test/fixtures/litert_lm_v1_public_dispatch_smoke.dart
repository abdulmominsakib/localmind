// Compiled-fixture dispatch only; this is never a real-model qualification row.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart' as spi;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';

import '../../tool/litert_lm_asr_smoke.dart' as speech;

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args[1]);
  int count(String name) =>
      library.lookupFunction<Int Function(), int Function()>('fixture_$name')();
  void require(bool condition, String reason) {
    if (!condition) throw StateError(reason);
  }

  void emit(String? value, {required bool finalChunk, int reason = 1}) {
    final text = value?.toNativeUtf8(allocator: calloc) ?? nullptr;
    try {
      library.lookupFunction<
        Void Function(Pointer<Utf8>, Bool, Int),
        void Function(Pointer<Utf8>, bool, int)
      >('fixture_client_emit')(text, finalChunk, reason);
    } finally {
      if (text != nullptr) calloc.free(text);
    }
  }

  Future<void> sent(int before) async {
    final watch = Stopwatch()..start();
    while (count('sends') == before) {
      if (watch.elapsed > const Duration(seconds: 5)) {
        throw StateError('Fixture send not reached.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  if (args[0] == 'speech') {
    final config =
        jsonDecode(File(args[3]).readAsStringSync()) as Map<String, dynamic>;
    await speech.runLiteRtLmAsrSmoke([
      args[2],
      (config['tokenizer'] as Map)['path'] as String,
      (config['audio'] as Map)['path'] as String,
      config['preset'] as String,
      config['expected_transcript'] as String,
    ], libraryPath: args[1]);
    require(
      count('asr_engines') == 0 && count('asr_sessions') == 0,
      'ASR owners leaked.',
    );
  } else if (args[0] == 'direct') {
    final client = spi.LiteRtLmRuntimeClient(libraryPath: args[1]);
    try {
      for (var lifetime = 0; lifetime < 2; lifetime++) {
        await client.initialize(
          modelPath: args[2],
          backend: 'cpu',
          speculativeDecoding: false,
        );
        require(
          client.supportsFinishReasons &&
              client.tokenize('hello', addSpecial: false).isNotEmpty,
          'Public v1 metadata/tokenizer missing.',
        );
        client.createConversation(temperature: 0);
        var before = count('sends');
        var answer = client.generate('fixture').join();
        await sent(before);
        emit(
          '{"role":"assistant","content":[{"type":"text","text":"fixture answer"}]}',
          finalChunk: true,
        );
        require(
          await answer == 'fixture answer',
          'Direct dispatch changed fixture bytes.',
        );
        require(
          client.lastFinishReason == spi.LiteRtLmFinishReason.stop,
          'Direct finish missing.',
        );
        before = count('sends');
        final firstOutput = Completer<void>();
        answer = client.generate('cancel fixture').map((chunk) {
          if (chunk.isNotEmpty && !firstOutput.isCompleted) {
            firstOutput.complete();
          }
          return chunk;
        }).join();
        await sent(before);
        emit(
          '{"role":"assistant","content":[{"type":"text","text":"partial"}]}',
          finalChunk: false,
        );
        await firstOutput.future.timeout(const Duration(seconds: 5));
        client.cancel();
        emit(null, finalChunk: true, reason: 4);
        await answer;
        require(
          client.lastFinishReason == spi.LiteRtLmFinishReason.cancelled &&
              client.nativeSettlement == spi.LiteRtLmNativeSettlement.settled,
          'Direct cancellation did not settle.',
        );
      }
    } finally {
      client.dispose();
    }
  } else if (args[0] == 'service') {
    final service = LiteRtLmService(useTempCacheDir: false);
    final params = ModelParams(
      device: ComputeDevice.cpu,
      liteRtLmCacheDir: '${Directory.systemTemp.path}/public-dispatch-cache',
    );
    try {
      require(
        service.reportsFinishReasons(),
        'Default service probe missed v1.',
      );
      for (var lifetime = 0; lifetime < 2; lifetime++) {
        final model = await service.loadModel(args[2], params);
        require(
          (await service.tokenize(model, 'hello', false)).isNotEmpty,
          'Default service tokenizer missing.',
        );
        final context = service.createContext(model, params);
        var before = count('sends');
        var answer = service
            .generateChat(
              context,
              const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'fixture',
                ),
              ],
              const GenerationParams(temp: 0),
              enableThinking: false,
            )
            .toList();
        await sent(before);
        emit(
          '{"role":"assistant","content":[{"type":"text","text":"fixture answer"}]}',
          finalChunk: true,
        );
        require(
          utf8.decode((await answer).expand((chunk) => chunk).toList()) ==
              'fixture answer',
          'Default service changed fixture bytes.',
        );
        before = count('sends');
        final firstOutput = Completer<void>();
        answer = service
            .generateChat(
              context,
              const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'cancel fixture',
                ),
              ],
              const GenerationParams(temp: 0),
              enableThinking: false,
            )
            .map((chunk) {
              if (chunk.isNotEmpty && !firstOutput.isCompleted) {
                firstOutput.complete();
              }
              return chunk;
            })
            .toList();
        await sent(before);
        emit(
          '{"role":"assistant","content":[{"type":"text","text":"partial"}]}',
          finalChunk: false,
        );
        await firstOutput.future.timeout(const Duration(seconds: 5));
        service.cancelGeneration();
        emit(null, finalChunk: true, reason: 4);
        await answer;
        require(
          service.nativeSettlement == spi.LiteRtLmNativeSettlement.settled,
          'Default service cancellation did not settle.',
        );
      }
    } finally {
      service.dispose();
    }
  } else {
    throw ArgumentError('Unknown fixture route.');
  }
  require(count('live') == 0, 'Native fixture owners leaked.');
  if (args.length > 4 && args[4] == 'tagged-settings') {
    final tagged = count('public_tagged_creates');
    final attempts = count('public_engine_attempts');
    final cpu = count('public_cpu_creates');
    final gpu = count('public_gpu_refusals');
    require(
      tagged == attempts && cpu >= 2 && tagged == cpu + gpu,
      'Tagged settings changed across native creation or automatic fallback: tagged=$tagged attempts=$attempts cpu=$cpu gpu=$gpu.',
    );
  }
  print(
    'PUBLIC_FIXTURE_DISPATCH ${args[0]} settled; model_qualification=false',
  );
}
