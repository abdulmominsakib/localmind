@Tags(<String>['real-model'])
library;

import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:genkit/plugin.dart' as genkit;
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:test/test.dart';

void main() {
  test(
    'real native LiteRT local and resolved HTTP media work without a projector',
    () async {
      final path =
          Platform.environment['LLAMADART_INTEGRATION_LITERT_MODEL_PATH'];
      final imagePath =
          Platform.environment['LLAMADART_INTEGRATION_LITERT_IMAGE_PATH'];
      final audioPath =
          Platform.environment['LLAMADART_INTEGRATION_LITERT_AUDIO_PATH'];
      if (path == null || imagePath == null || audioPath == null) {
        markTestSkipped(
          'Set the LiteRT model, image and audio fixture paths documented in CONTRIBUTING.md.',
        );
        return;
      }
      final mediaServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => mediaServer.close(force: true));
      var mediaRequests = 0;
      mediaServer.listen((request) async {
        final isImage = request.uri.path == '/image.png';
        final bytes = await File(isImage ? imagePath : audioPath).readAsBytes();
        mediaRequests++;
        request.response.headers.contentType = ContentType.parse(
          isImage ? 'image/png' : 'audio/wav',
        );
        request.response.add(bytes);
        await request.response.close();
      });
      final client = http.Client();
      addTearDown(client.close);
      final capture = _MediaCapture();
      final plugin = LlamaDartPlugin(
        observers: [capture],
        mediaResolver: HttpLlamaDartMediaResolver(
          client: client,
          allowUri: (uri) =>
              uri.host == '127.0.0.1' && uri.port == mediaServer.port,
        ),
        models: [
          LlamaModelDefinition(
            name: 'real-litert',
            modelPath: path,
            modelParams: const ModelParams(
              device: ComputeDevice.cpu,
              contextSize: 2048,
            ),
          ),
        ],
      );
      addTearDown(plugin.dispose);
      final actions = await plugin.init();
      final model = actions
          .whereType<genkit.Model<LlamaDartGenerationConfig>>()
          .single;
      final embedder = actions
          .whereType<genkit.Embedder<LlamaDartEmbedConfig>>()
          .single;
      Map<String, dynamic> supports() =>
          (model.metadata['model'] as Map<String, dynamic>)['supports']
              as Map<String, dynamic>;
      final config = const LlamaDartGenerationConfig(
        maxTokens: 8,
        temperature: 0,
      ).toJson();
      genkit.ModelRequest request(List<genkit.Part> parts) =>
          genkit.ModelRequest(
            messages: [genkit.Message(role: genkit.Role.user, content: parts)],
            config: config,
          );
      final text = await model(request([genkit.TextPart(text: 'Say hello.')]));
      expect(text.text.trim(), isNotEmpty);
      expect(supports()['constrained'], false);
      expect(supports()['embeddings'], false);
      expect(
        supports()['media'],
        true,
        reason:
            'Use a native LiteRT bundle with confirmed built-in vision or audio encoders.',
      );
      final image = await model(
        request([
          genkit.TextPart(text: 'Describe this image briefly.'),
          genkit.MediaPart(
            media: genkit.Media(
              url: Uri.file(imagePath).toString(),
              contentType: 'image/png',
            ),
          ),
        ]),
      );
      expect(image.text.trim(), isNotEmpty);
      final audio = await model(
        request([
          genkit.TextPart(text: 'Describe this audio briefly.'),
          genkit.MediaPart(
            media: genkit.Media(
              url: Uri.file(audioPath).toString(),
              contentType: 'audio/wav',
            ),
          ),
        ]),
      );
      expect(audio.text.trim(), isNotEmpty);
      for (final (path, type) in [
        ('image.png', 'image/png'),
        ('audio.wav', 'audio/wav'),
      ]) {
        final remote = await model(
          request([
            genkit.TextPart(text: 'Describe this input briefly.'),
            genkit.MediaPart(
              media: genkit.Media(
                url: 'http://127.0.0.1:${mediaServer.port}/$path',
                contentType: type,
              ),
            ),
          ]),
        );
        expect(remote.text.trim(), isNotEmpty);
        final part = capture.chats.last.messages.single.parts.last;
        final actual = part is llama.LlamaImageContent
            ? part.bytes
            : (part as llama.LlamaAudioContent).bytes;
        expect(
          actual,
          await File(type == 'image/png' ? imagePath : audioPath).readAsBytes(),
        );
        print(
          'Native LiteRT remote $type: finishReason=${remote.finishReason}, text=${remote.text}',
        );
      }
      expect(mediaRequests, 2);
      await expectLater(
        model(
          genkit.ModelRequest(
            messages: [
              genkit.Message(
                role: genkit.Role.user,
                content: [genkit.TextPart(text: 'Return JSON.')],
              ),
            ],
            output: genkit.OutputConfig(format: 'json'),
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
      await expectLater(
        embedder(
          genkit.EmbedRequest(
            input: [
              genkit.DocumentData(content: [genkit.TextPart(text: 'Hello')]),
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
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

final class _MediaCapture extends LlamaEngineObserver {
  final chats = <LlamaChatOperation>[];
  @override
  LlamaOperationObserver? onStart(LlamaOperation operation) {
    if (operation is LlamaChatOperation) chats.add(operation);
    return null;
  }
}
