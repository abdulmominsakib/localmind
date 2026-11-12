@TestOn('vm && !windows')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_bundle_template.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_chat_templates.dart';
import 'package:test/test.dart';

import '../../support/suite_system_temp.dart';

/// Uses an existing, read-only legacy Qwen3 bundle; never downloads weights.
void main() {
  useSuiteSystemTemp();
  final modelPath = Platform.environment['LITERT_LM_MODEL'];
  final skip = modelPath == null || !File(modelPath).existsSync()
      ? 'Set LITERT_LM_MODEL to the legacy Qwen3-0.6B bundle.'
      : false;
  final canonical = kLiteRtLmChatTemplates
      .singleWhere((item) => item.id == 'qwen3')
      .template;

  for (final name in ['Qwen3-0.6B.litertlm', 'qwen.litertlm', 'download']) {
    for (final override in [false, true]) {
      test('$name override=$override thinking disabled', () async {
        final temp = await Directory.systemTemp.createTemp('qwen3_renamed_');
        final link = await Link('${temp.path}/$name').create(modelPath!);
        final engine = LlamaEngine(LlamaBackend());
        try {
          expect(readLiteRtLmBundleMetadata(link.path), (
            chatTemplate: null,
            isQwen3: false,
          ));
          await engine.loadModel(
            link.path,
            modelParams: ModelParams(
              contextSize: 1024,
              liteRtLmBackend: LiteRtLmBackendPreference.cpu,
              liteRtLmCacheDir: '${temp.path}/cache',
              chatTemplate: override ? canonical : null,
            ),
          );
          final answer = StringBuffer();
          await for (final chunk in engine.create(
            const [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: 'What is 2+2? Answer only with the number.',
              ),
            ],
            params: const GenerationParams(maxTokens: 32, temp: 0, seed: 1),
            enableThinking: false,
          )) {
            for (final choice in chunk.choices) {
              answer.write(choice.delta.content ?? '');
            }
          }
          print(
            'QWEN3_RESULT ${jsonEncode({'name': name, 'override': override, 'content': answer.toString()})}',
          );
          if (name.startsWith('Qwen3') || override) {
            expect(answer.toString().trim(), isNotEmpty);
          } else {
            // This artifact has no family declaration or Jinja template.
            // Its generic ChatML metadata cannot identify Qwen3 reliably.
            expect(answer.toString(), isEmpty);
          }
        } finally {
          await engine.dispose();
          await temp.delete(recursive: true);
        }
      }, skip: skip);
    }
  }
}
