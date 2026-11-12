@TestOn('vm && (mac-os || linux)')
@Tags(['local-only'])
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_finish_reason.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_v1_runtime.dart';
import 'package:test/test.dart';

/// Candidate-only preparation controls, never a shipped runtime selection.
/// Both files must match caller-supplied hashes before native loading.
void main() {
  test(
    'injected C API 1.0 conversation reuse, cancellation and recreation',
    () async {
      String required(String key) {
        final value = Platform.environment[key];
        if (value == null || value.isEmpty) {
          throw StateError('Set $key for this local-only check.');
        }
        return value;
      }

      Future<String> verified(String key) async {
        final path = required(key);
        expect(
          (await sha256.bind(File(path).openRead()).first).toString(),
          required('${key}_SHA256'),
        );
        return path;
      }

      final libraryPath = await verified('LLAMADART_LITERT_V1_LIBRARY');
      final modelPath = await verified('LLAMADART_LITERT_V1_MODEL');
      final cache = await Directory.systemTemp.createTemp(
        'litert_v1_candidate_',
      );
      final runtime = LiteRtLmV1Runtime(DynamicLibrary.open(libraryPath));
      runtime.load(
        modelPath,
        cacheDir: cache.path,
        contextSize: 2048,
        numberOfThreads: 2,
      );
      final conversation = runtime.openConversation(maxOutputTokens: 32);
      for (var index = 0; index < 2; index++) {
        final turn = conversation.sendText('Say one short greeting.');
        final chunks = turn.chunks.toList();
        final reason = await turn.done;
        final messages = await chunks;
        expect(messages, isNotEmpty);
        for (final message in messages) {
          expect(jsonDecode(message), isA<Map>());
        }
        expect(
          reason,
          anyOf(LiteRtLmFinishReason.stop, LiteRtLmFinishReason.length),
        );
        print(
          jsonEncode({
            'phase': 'normal',
            'turn': index,
            'chunks': messages.length,
            'finish_reason': reason.name,
          }),
        );
      }
      conversation.close();
      final cancelled = runtime.openConversation(maxOutputTokens: 512);
      final turn = cancelled.sendText(
        'Count from one to one hundred, writing every number in words.',
      );
      var requested = false;
      final subscription = turn.chunks.listen((_) {
        if (!requested) {
          requested = true;
          turn.cancel();
        }
      });
      final reason = await turn.done;
      await subscription.cancel();
      expect(requested, isTrue);
      expect(reason, LiteRtLmFinishReason.cancelled);
      expect(
        () => cancelled.sendText('reuse'),
        throwsA(isA<LlamaStateException>()),
      );
      print(
        jsonEncode({
          'phase': 'cancelled',
          'finish_reason': reason.name,
          'old_conversation_refused': true,
        }),
      );
      final fresh = runtime.openConversation(maxOutputTokens: 32);
      final next = fresh.sendText('Say hello.');
      final nextChunks = next.chunks.toList();
      final nextReason = await next.done;
      expect(await nextChunks, isNotEmpty);
      expect(
        nextReason,
        anyOf(LiteRtLmFinishReason.stop, LiteRtLmFinishReason.length),
      );
      cancelled.close();
      expect(runtime.dispose, throwsA(isA<LlamaStateException>()));
      fresh.close();
      runtime.dispose();
      runtime.dispose();
      await cache.delete(recursive: true);
      print(
        jsonEncode({
          'phase': 'recreated',
          'finish_reason': nextReason.name,
          'disposed_twice': true,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
