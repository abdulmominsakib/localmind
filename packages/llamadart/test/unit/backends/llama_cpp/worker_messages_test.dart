@TestOn('vm')
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/worker_messages.dart';
import 'package:test/test.dart';

void main() {
  test(
    'worker snapshot merges text verbatim and copies every media source',
    () {
      final port = ReceivePort();
      addTearDown(port.close);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final pcm = Float32List.fromList([0, 0.25]);
      final request = EmbedContentBatchRequest(
        7,
        [
          LlamaEmbeddingInput([
            const LlamaTextContent('a '),
            const LlamaTextContent(''),
            const LlamaTextContent('\nbé'),
            LlamaImageContent(bytes: bytes, width: 1, height: 1),
            const LlamaTextContent('c'),
            const LlamaTextContent('d'),
            LlamaAudioContent(samples: pcm),
            LlamaAudioContent(bytes: bytes),
            const LlamaImageContent(path: 'image'),
            const LlamaAudioContent(path: 'audio'),
            const LlamaImageContent(url: 'https://invalid.example'),
          ]),
        ],
        false,
        123,
        port.sendPort,
      );
      bytes[0] = 9;
      pcm[0] = 1;
      final parts = request.inputs.single.parts;
      expect(parts, hasLength(8));
      expect((parts[0] as LlamaTextContent).text, 'a \nbé');
      expect((parts[1] as LlamaImageContent).bytes, [1, 2, 3]);
      expect((parts[1] as LlamaImageContent).width, 1);
      expect((parts[2] as LlamaTextContent).text, 'cd');
      expect((parts[3] as LlamaAudioContent).samples, [0, 0.25]);
      expect((parts[4] as LlamaAudioContent).bytes, [1, 2, 3]);
      expect((parts[5] as LlamaImageContent).path, 'image');
      expect((parts[6] as LlamaAudioContent).path, 'audio');
      expect((parts[7] as LlamaImageContent).url, 'https://invalid.example');
    },
  );
}
