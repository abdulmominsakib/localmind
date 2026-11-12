import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:llamadart/llamadart.dart';

/// Small deterministic synthetic media; establishes wiring, not retrieval quality.
Map<String, LlamaEmbeddingInput> liteRtEmbeddingInputs() {
  Uint8List png(bool checker) {
    final pixels = BytesBuilder();
    for (var y = 0; y < 32; y++) {
      pixels.addByte(0);
      for (var x = 0; x < 32; x++) {
        final c = checker && (x ~/ 4 + y ~/ 4).isEven ? 255 : 0;
        pixels.add([c, c, c]);
      }
    }
    Uint8List chunk(String name, List<int> data) {
      final body = Uint8List.fromList([...ascii.encode(name), ...data]);
      final out = Uint8List(body.length + 8);
      final b = ByteData.sublistView(out);
      b.setUint32(0, data.length);
      out.setRange(4, 4 + body.length, body);
      b.setUint32(out.length - 4, getCrc32(body));
      return out;
    }

    final ihdr = Uint8List(13);
    final h = ByteData.sublistView(ihdr);
    h.setUint32(0, 32);
    h.setUint32(4, 32);
    ihdr[8] = 8;
    ihdr[9] = 2;
    return Uint8List.fromList([
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      ...chunk('IHDR', ihdr),
      ...chunk('IDAT', ZLibEncoder().encode(pixels.takeBytes())),
      ...chunk('IEND', []),
    ]);
  }

  final black = LlamaImageContent(bytes: png(false));
  final checker = LlamaImageContent(bytes: png(true));
  final silence = LlamaAudioContent(samples: Float32List(16000));
  final tone = LlamaAudioContent(
    samples: Float32List.fromList(
      List.generate(
        16000,
        (i) => 0.2 * math.sin(2 * math.pi * 440 * i / 16000),
      ),
    ),
  );
  return {
    'text': LlamaEmbeddingInput(const [LlamaTextContent('hello world')]),
    'black': LlamaEmbeddingInput([black]),
    'checker': LlamaEmbeddingInput([checker]),
    'silence': LlamaEmbeddingInput([silence]),
    'tone': LlamaEmbeddingInput([tone]),
    'mixed': LlamaEmbeddingInput([
      const LlamaTextContent('first '),
      const LlamaTextContent('\nsecondé'),
      checker,
      const LlamaTextContent('sound'),
      tone,
      const LlamaTextContent('end'),
    ]),
  };
}

/// Cosine and relative L2 for cross-runtime qualification.
({double cosine, double relL2}) embeddingDistance(
  List<double> a,
  List<double> b,
) {
  var dot = 0.0, aa = 0.0, bb = 0.0, delta = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
    delta += math.pow(a[i] - b[i], 2);
  }
  return (cosine: dot / math.sqrt(aa * bb), relL2: math.sqrt(delta / aa));
}
