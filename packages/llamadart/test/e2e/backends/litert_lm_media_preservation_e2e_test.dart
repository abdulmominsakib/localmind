@TestOn('vm')
@Tags(['local-only', 'e2e'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../tool/litert_lm_chat_features_smoke.dart' as smoke;
import '../../support/suite_system_temp.dart';
import 'multimodal_embedding_litert_inputs.dart';

const _modelSha =
    'e3360b658c929ff35ab740a21f5e4b688096a72e351b8d347e26ccda314121b7';
const _checkerSha =
    '608559c1cef09a7d4669ea459ee1e8825771634f543fb1a93a6e768a48da9b09';
const _operationTimeout = Duration(seconds: 30);
const _params = GenerationParams(
  maxTokens: 64,
  temp: 0,
  seed: 1,
  speculativeDecoding: false,
);

void main() {
  final temp = useSuiteSystemTemp();
  final model = Platform.environment['LITERT_LM_VISION_MODEL'];

  test(
    'Qwen3.5 CPU preserves encoded images through history and lifecycle',
    () async {
      final file = File(model!);
      expect(await file.length(), 1302262448);
      expect(
        (await sha256.bind(file.openRead()).first.timeout(_operationTimeout))
            .toString(),
        _modelSha,
        reason:
            'Use litert-community/Qwen3.5-0.8B revision '
            '10243c0a01d24e6b122a0e814f8c4d984c9c92d6, '
            'Qwen3.5-0.8B-VL_int8.litertlm.',
      );
      final checker =
          liteRtEmbeddingInputs()['checker']!.parts.single as LlamaImageContent;
      final bytes = checker.bytes!;
      expect(bytes.length, 117);
      expect(sha256.convert(bytes).toString(), _checkerSha);
      final image = File('${temp().path}/checker.png');
      await image.writeAsBytes(bytes);
      print(
        jsonEncode({
          'case': 'fixtures',
          'modelSha256': _modelSha,
          'modelBytes': 1302262448,
          'checkerSha256': _checkerSha,
          'checkerBytes': bytes.length,
          'modelRevision': '10243c0a01d24e6b122a0e814f8c4d984c9c92d6',
        }),
      );

      final nativeRender = await smoke
          .renderLiteRtLmNativeMediaPrompt(
            modelPath: model,
            backend: LiteRtLmBackendPreference.cpu,
            imagePath: image.path,
          )
          .timeout(_operationTimeout);
      expect(nativeRender.marker, '<image_soft_token>');
      expect(nativeRender.renderedLength, greaterThan(0));
      print(
        jsonEncode({'case': 'native_media_render', ...nativeRender.toJson()}),
      );

      List<LlamaChatMessage> messages(LlamaImageContent content) => [
        LlamaChatMessage.withContent(
          role: LlamaChatRole.user,
          content: [
            const LlamaTextContent('Describe the image in one short sentence.'),
            content,
          ],
        ),
      ];

      var engine = LlamaEngine(LlamaBackend());
      Future<void> load() async {
        await engine
            .loadModel(
              model,
              modelParams: ModelParams(
                device: ComputeDevice.cpu,
                contextSize: 2048,
                liteRtLmCacheDir: '${temp().path}/cache',
              ),
            )
            .timeout(_operationTimeout);
        expect(engine.runtime, LlamaRuntime.liteRtLm);
        final capabilities = await engine.capabilities.timeout(
          _operationTimeout,
        );
        final supportsVision = await engine.supportsVision.timeout(
          _operationTimeout,
        );
        expect(capabilities.supportsVision, isTrue);
        expect(supportsVision, isTrue);
        print(
          jsonEncode({
            'case': 'capabilities',
            'runtime': engine.runtime?.name,
            'requestedDevice': 'cpu',
            'capabilitiesSupportsVision': capabilities.supportsVision,
            'supportsVision': supportsVision,
          }),
        );
      }

      Future<String> generate(List<LlamaChatMessage> history) async {
        final completion = await engine
            .create(history, enableThinking: false, params: _params)
            .collect()
            .timeout(_operationTimeout);
        final text = completion.text.trim();
        expect(text.toLowerCase(), contains('checkerboard'), reason: text);
        return text;
      }

      final pathMessages = messages(LlamaImageContent(path: image.path));
      final bytesMessages = messages(LlamaImageContent(bytes: bytes));
      try {
        await load();
        final baseline = await generate(pathMessages);
        print(jsonEncode({'case': 'image_path', 'text': baseline}));
        final bytesReply = await generate(bytesMessages);
        expect(bytesReply, baseline);
        print(jsonEncode({'case': 'image_bytes_parity', 'text': bytesReply}));
        final historyReply = await generate([
          ...pathMessages,
          LlamaChatMessage.fromText(
            role: LlamaChatRole.assistant,
            text: baseline,
          ),
          const LlamaChatMessage.fromText(
            role: LlamaChatRole.user,
            text:
                'What pattern was in the image? Answer in one short sentence.',
          ),
        ]);
        print(jsonEncode({'case': 'image_history', 'text': historyReply}));
        // Cancelling the subscription must leave the same engine reusable.
        await engine
            .create(bytesMessages, enableThinking: false, params: _params)
            .first
            .timeout(_operationTimeout);
        final afterCancellation = await generate(pathMessages);
        expect(afterCancellation, baseline);
        print(
          jsonEncode({
            'case': 'first_chunk_cancellation_reuse',
            'subscriptionCancelled': true,
            'text': afterCancellation,
          }),
        );
        final textOnly = await engine
            .create(
              const [
                LlamaChatMessage.fromText(
                  role: LlamaChatRole.user,
                  text: 'What is 2 + 3? Answer with one digit.',
                ),
              ],
              enableThinking: false,
              params: _params,
            )
            .collect()
            .timeout(_operationTimeout);
        expect(textOnly.text, contains('5'));
        print(
          jsonEncode({
            'case': 'text_only_after_image',
            'text': textOnly.text.trim(),
          }),
        );
        await engine.dispose().timeout(_operationTimeout);
        engine = LlamaEngine(LlamaBackend());
        await load();
        final reloadedReply = await generate(bytesMessages);
        expect(reloadedReply, baseline);
        print(jsonEncode({'case': 'dispose_reload', 'text': reloadedReply}));
      } finally {
        await engine.dispose().timeout(_operationTimeout);
      }
    },
    skip: model == null
        ? 'Set LITERT_LM_VISION_MODEL to the qualified Qwen3.5 VL bundle.'
        : false,
  );
}
