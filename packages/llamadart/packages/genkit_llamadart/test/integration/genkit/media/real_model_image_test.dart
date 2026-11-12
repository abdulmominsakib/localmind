@Tags(['real-model', 'image-model'])
@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';
import 'package:llamadart/llamadart.dart' as llama;
import 'package:image/image.dart' as image;
import 'package:test/test.dart';

void main() {
  test(
    'real checksum-pinned SDXS produces a complete PNG through Genkit',
    () async {
      final path = Platform.environment['GENKIT_IMAGE_MODEL'];
      if (path == null) {
        markTestSkipped(
          'Set GENKIT_IMAGE_MODEL and opt into stable_diffusion for image qualification.',
        );
        return;
      }
      expect(
        (await sha256.bind(File(path).openRead()).first).toString(),
        '409ab23582ee074c6b9d5395784fc0741b0599fb9d138686c69087c71678eb6a',
      );
      final engine = await llama.ImageGenerationEngine.load(
        llama.ImageGenerationModel(llama.ModelSource.path(path)),
        params: const llama.ImageModelParams(device: llama.ComputeDevice.cpu),
      );
      final capabilities = await engine.capabilities;
      expect(capabilities.backendName, 'CPU');
      print(
        'Image runtime: ${capabilities.runtimeVersion}; backend: ${capabilities.backendName}',
      );
      final plugin = LlamaDartMediaPlugin(
        models: [
          LlamaDartImageModel(name: 'image', engine: engine, ownsEngine: true),
        ],
      );
      final ai = Genkit(plugins: [plugin], isDevEnv: false);
      addTearDown(() async {
        await plugin.dispose();
        await ai.shutdown();
      });
      final response = await ai.generate(
        model: LlamaDartMediaPlugin.modelRef('image'),
        prompt: 'A red apple on a plain blue background.',
        config: {
          'width': 256,
          'height': 256,
          'steps': 1,
          'guidanceScale': 1,
          'seed': 42,
          'sampler': 'eulerAncestral',
          'scheduler': 'discrete',
        },
      );
      expect(
        response.finishReason,
        FinishReason.stop,
        reason: '${response.error}',
      );
      final media = response.media!;
      expect(media.contentType, 'image/png');
      final bytes = UriData.parse(media.url).contentAsBytes();
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final decoded = image.decodePng(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 256);
      expect(decoded.height, 256);
      final first = decoded.getPixel(0, 0);
      final reference = (first.r, first.g, first.b);
      expect(
        decoded.any((pixel) => (pixel.r, pixel.g, pixel.b) != reference),
        isTrue,
      );
      final output = Platform.environment['GENKIT_IMAGE_PNG_OUTPUT'];
      if (output != null) await File(output).writeAsBytes(bytes);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
