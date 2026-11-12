@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/backend.dart';
import 'package:test/test.dart';

import '../../../tool/litert_lm_tokenizer_fixture.dart';
import '../../support/suite_system_temp.dart';

const _operationTimeout = Duration(seconds: 30);
const _prompt = 'Reply with one short sentence saying hello.';

void main() {
  final temp = useSuiteSystemTemp();
  final model = Platform.environment['LITERT_LM_UTILITY_MODEL'];

  test(
    'public Qwen3 CPU tokenizer and benchmark utility remain usable',
    () async {
      final file = File(model!);
      expect(await file.length(), 613722264);
      expect(
        (await sha256.bind(file.openRead()).first.timeout(_operationTimeout))
            .toString(),
        qwen3UpdatedModelSha256,
      );
      final cache = Directory('${temp().path}/cache');
      await cache.create(recursive: true);
      final client = LiteRtLmRuntimeClient();
      try {
        await client
            .initialize(
              modelPath: model,
              backend: 'cpu',
              maxTokens: 1024,
              outputTokens: 32,
              cacheDir: cache.path,
              speculativeDecoding: false,
              minLogLevel: 3,
            )
            .timeout(_operationTimeout);
        const text = 'Hello! 😊';
        const tokenIds = [9707, 0, 26525, 232];
        final withoutSpecial = client.tokenize(text, addSpecial: false);
        expect(withoutSpecial, tokenIds);
        expect(client.detokenize(tokenIds), text);
        final startTokens = client.tokenize('', addSpecial: true);
        expect(client.tokenize('', addSpecial: false), isEmpty);
        final withSpecial = client.tokenize(text, addSpecial: true);
        expect(withSpecial, [...startTokens, ...tokenIds]);
        print(
          jsonEncode({
            'case': 'tokenizer',
            'configuredStartTokens': startTokens,
            'withoutSpecial': withoutSpecial,
            'withSpecial': withSpecial,
          }),
        );
        for (final control in ['Hello!', 'Hello! 😊', 'café 한글 日本語', 'ĠðŁĺĬ']) {
          expect(
            client.detokenize(client.tokenize(control, addSpecial: false)),
            control,
          );
        }

        Future<void> run({required int warmup, required int measured}) async {
          final result = await client
              .run(prompt: _prompt, warmupRuns: warmup, measuredRuns: measured)
              .timeout(_operationTimeout);
          expect(result.text.trim(), isNotEmpty);
          expect(client.nativeSettlement, LiteRtLmNativeSettlement.settled);
          final metrics = result.metrics;
          print(
            jsonEncode({
              'case': 'run',
              'warmupRuns': warmup,
              'measuredRuns': measured,
              'nativeSettlement': client.nativeSettlement.name,
              'text': result.text,
              'metrics': metrics.toJson(),
            }),
          );
          expect(metrics.inputTokens, greaterThan(0));
          expect(metrics.outputTokens, greaterThan(0));
          for (final metric in <String, double?>{
            'TTFT': metrics.timeToFirstTokenSeconds,
            'prefill throughput': metrics.prefillTokensPerSecond,
            'decode throughput': metrics.decodeTokensPerSecond,
          }.entries) {
            expect(metric.value, isNotNull, reason: metric.key);
            expect(metric.value!.isFinite, isTrue, reason: metric.key);
            expect(metric.value, greaterThan(0), reason: metric.key);
          }
        }

        await run(warmup: 1, measured: 2);
        await run(warmup: 0, measured: 1);
      } finally {
        client.dispose();
      }
    },
    skip: model == null
        ? 'Set LITERT_LM_UTILITY_MODEL to the qualified Qwen3-0.6B bundle.'
        : false,
  );
}
