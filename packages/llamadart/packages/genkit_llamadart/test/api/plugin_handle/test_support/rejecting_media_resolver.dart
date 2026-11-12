import 'dart:typed_data';

import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:test/test.dart';

class RejectingMediaResolver implements LlamaDartMediaResolver {
  int calls = 0;
  @override
  Future<Uint8List> resolve(
    Uri uri, {
    required String contentType,
    genkit.CancellationToken? cancel,
  }) async {
    calls++;
    throw StateError('test resolver rejection');
  }
}

Future<void> expectResolverUsed(
  LlamaDartPlugin plugin,
  RejectingMediaResolver resolver,
) async {
  if (!const bool.fromEnvironment('dart.library.io')) return;
  final model = (await plugin.init())
      .whereType<genkit.Model<LlamaDartGenerationConfig>>()
      .single;
  await expectLater(
    model(
      genkit.ModelRequest(
        messages: [
          genkit.Message(
            role: genkit.Role.user,
            content: [
              genkit.MediaPart(
                media: genkit.Media(
                  url: 'https://media.example/audio.wav',
                  contentType: 'audio/wav',
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
        genkit.StatusCode.invalidArgument,
      ),
    ),
  );
  expect(resolver.calls, 1);
}
