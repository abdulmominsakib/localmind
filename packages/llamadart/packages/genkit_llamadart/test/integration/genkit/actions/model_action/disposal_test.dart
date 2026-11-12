import 'dart:typed_data';

import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

import '../../../../core/runtime/test_support/fake_runtime.dart';

void main() {
  for (final configuredResolver in [false, true]) {
    for (final (kind, media) in [
      ('text', null),
      ('local image', '/local/image.png'),
      ('data image', 'data:image/png;base64,AQID'),
    ]) {
      test(
        'dispose drains accepted $kind action with resolver=$configuredResolver',
        () async {
          final runtime = FakeRuntime()
            ..createChunks = [textChunk('completed')];
          final resolver = _UnexpectedResolver();
          final plugin = LlamaDartPlugin(
            models: const [
              LlamaModelDefinition(name: 'local', modelPath: '/model.gguf'),
            ],
            runtimeFactory: () => runtime,
            mediaResolver: configuredResolver ? resolver : null,
          );
          addTearDown(plugin.dispose);
          final model = (await plugin.init())
              .whereType<genkit.Model<LlamaDartGenerationConfig>>()
              .single;
          final pending = model(
            genkit.ModelRequest(
              messages: [
                genkit.Message(
                  role: genkit.Role.user,
                  content: [
                    genkit.TextPart(text: 'Hello'),
                    if (media != null)
                      genkit.MediaPart(
                        media: genkit.Media(
                          url: media,
                          contentType: 'image/png',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
          final disposal = plugin.dispose();
          expect((await pending).text, 'completed');
          await disposal;
          expect(runtime.createCallCount, 1);
          expect(runtime.disposeCount, 1);
          expect(resolver.calls, 0);
        },
      );
    }
  }
}

class _UnexpectedResolver implements LlamaDartMediaResolver {
  int calls = 0;
  @override
  Future<Uint8List> resolve(
    Uri uri, {
    required String contentType,
    genkit.CancellationToken? cancel,
  }) {
    calls++;
    throw StateError('No remote resolution was expected.');
  }
}
