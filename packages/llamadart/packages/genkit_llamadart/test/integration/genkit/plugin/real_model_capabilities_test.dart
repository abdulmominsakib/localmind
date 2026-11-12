@Tags(<String>['real-model'])
library;

import 'dart:convert';

import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

import '../test_support/real_model_test_support.dart';

void main() {
  test(
    'real GGUF probe guards media and preserves history and constrained JSON',
    () async {
      final path = await resolveIntegrationModelPath();
      if (path == null) return;
      final observer = _ChatObserver();
      final plugin = LlamaDartPlugin(
        models: [
          LlamaModelDefinition(
            name: 'real-capabilities',
            modelPath: path,
            modelParams: const ModelParams(
              contextSize: 1024,
              device: ComputeDevice.cpu,
            ),
            supportsEmbeddings: false,
          ),
        ],
        observers: [observer],
      );
      addTearDown(plugin.dispose);
      final listed = await plugin.list();
      final action = (await plugin.init())
          .whereType<genkit.Model<LlamaDartGenerationConfig>>()
          .single;
      Map<String, dynamic> supports() =>
          (action.metadata['model'] as Map<String, dynamic>)['supports']
              as Map<String, dynamic>;
      expect(supports()['multiturn'], false);
      expect(observer.chats, 0);
      final inspection = await plugin.inspectModel('real-capabilities');
      expect(inspection.contextSize, 1024);
      expect(inspection.capabilities!.backendName, 'CPU');
      expect(inspection.capabilities!.isSupported, true);
      final tokens = await plugin.tokenize('real-capabilities', 'Hello.');
      expect(tokens, hasLength(2));
      expect(await plugin.countTokens('real-capabilities', 'Hello.'), 2);
      expect(await plugin.countTokens('real-capabilities', ''), 0);
      expect(
        observer.chats,
        0,
        reason: 'Inspection must not perform inference.',
      );
      final response = await action(
        genkit.ModelRequest(
          messages: [
            genkit.Message(
              role: genkit.Role.system,
              content: [genkit.TextPart(text: 'Reply briefly.')],
            ),
            genkit.Message(
              role: genkit.Role.user,
              content: [genkit.TextPart(text: 'Hello.')],
            ),
            genkit.Message(
              role: genkit.Role.model,
              content: [genkit.TextPart(text: 'Hello!')],
            ),
            genkit.Message(
              role: genkit.Role.user,
              content: [genkit.TextPart(text: 'Say hello again.')],
            ),
          ],
          config: const LlamaDartGenerationConfig(
            maxTokens: 16,
            temperature: 0,
          ).toJson(),
        ),
      );
      expect(response.text.trim(), isNotEmpty);
      expect(observer.chats, 1);
      expect(supports()['multiturn'], true);
      expect(supports()['systemRole'], true);
      expect(supports()['constrained'], true);
      expect(supports()['media'], false);
      expect(
        (listed.first.metadata['llamadartCapabilities'] as Map)['state'],
        'verified',
      );
      for (final contentType in ['image/png', 'audio/wav']) {
        await expectLater(
          action(
            genkit.ModelRequest(
              messages: [
                genkit.Message(
                  role: genkit.Role.user,
                  content: [
                    genkit.MediaPart(
                      media: genkit.Media(
                        url: 'data:$contentType;base64,AA==',
                        contentType: contentType,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          throwsA(
            isA<genkit.GenkitException>().having(
              (e) => e.status,
              'status',
              genkit.StatusCode.unimplemented,
            ),
          ),
        );
      }
      expect(
        observer.chats,
        1,
        reason: 'Unsupported media must not start inference.',
      );
      final structured = await action(
        genkit.ModelRequest(
          messages: [
            genkit.Message(
              role: genkit.Role.user,
              content: [
                genkit.TextPart(text: 'Return an answer of yes as JSON.'),
              ],
            ),
          ],
          output: genkit.OutputConfig(
            format: 'json',
            schema: {
              'type': 'object',
              'properties': {
                'answer': {
                  'type': 'string',
                  'enum': ['yes'],
                },
              },
              'required': ['answer'],
              'additionalProperties': false,
            },
          ),
          config: const LlamaDartGenerationConfig(
            maxTokens: 48,
            temperature: 0,
          ).toJson(),
        ),
      );
      expect(jsonDecode(structured.text), {'answer': 'yes'});
    },
  );
}

final class _ChatObserver extends LlamaEngineObserver {
  int chats = 0;
  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) {
    if (operation is LlamaChatOperation) chats++;
    return null;
  }
}
