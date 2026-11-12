import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:test/test.dart';

void main() {
  test('merges text verbatim across whitespace empty and Unicode parts', () {
    final parts = prepareLiteRtLmEmbedding(
      LlamaEmbeddingInput(const [
        LlamaTextContent('first '),
        LlamaTextContent(''),
        LlamaTextContent('\nsecondé'),
      ]),
    );
    expect(parts, hasLength(1));
    expect(parts.single.type, 0);
    expect(utf8.decode(parts.single.bytes), 'first \nsecondé');
    expect(
      prepareLiteRtLmEmbedding(
        LlamaEmbeddingInput(const [LlamaTextContent('')]),
      ).single.bytes,
      isEmpty,
    );
  });
  test('copies image/audio and preserves interleaving', () {
    final png = image.encodePng(image.Image(width: 2, height: 2));
    final samples = Float32List.fromList([0, 0.5, -0.5]);
    final parts = prepareLiteRtLmEmbedding(
      LlamaEmbeddingInput([
        const LlamaTextContent('x'),
        LlamaImageContent(bytes: png),
        const LlamaTextContent('a'),
        const LlamaTextContent('b'),
        LlamaAudioContent(samples: samples),
      ]),
    );
    expect(parts.map((p) => p.type), [0, 1, 0, 3]);
    expect(utf8.decode(parts[2].bytes), 'ab');
    png[0] = 0;
    samples[1] = 0;
    expect(parts[1].bytes[0], 137);
    final wav = ByteData.sublistView(parts[3].bytes);
    expect(wav.getUint16(20, Endian.little), 3);
    expect(wav.getUint16(22, Endian.little), 1);
    expect(wav.getUint32(24, Endian.little), 16000);
    expect(wav.getUint32(40, Endian.little), 12);
    expect(wav.getFloat32(48, Endian.little), 0.5);
  });
  test('rejects unresolved media and unsupported codecs without payloads', () {
    for (final part in [
      const LlamaImageContent(path: '/secret'),
      const LlamaImageContent(url: 'https://private.invalid'),
      LlamaImageContent(bytes: Uint8List(4)),
      const LlamaAudioContent(path: '/secret'),
      LlamaAudioContent(bytes: Uint8List(4)),
      LlamaAudioContent(bytes: Uint8List(44), samples: Float32List(1)),
    ]) {
      expect(
        () => prepareLiteRtLmEmbedding(LlamaEmbeddingInput([part])),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'redaction',
            isNot(contains('secret')),
          ),
        ),
      );
    }
  });
  test('decodes every media part before batch dispatch', () {
    for (final part in [
      LlamaImageContent(
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
      LlamaImageContent(bytes: Uint8List.fromList([255, 216, 255, 0])),
      LlamaAudioContent(
        bytes: liteRtLmEmbeddingWav(Float32List(2)).sublist(0, 44),
      ),
    ]) {
      expect(
        () => prepareLiteRtLmEmbedding(LlamaEmbeddingInput([part])),
        throwsA(isA<LlamaInferenceException>()),
      );
    }
  });
  test('rejects invalid PCM without encoding it', () {
    for (final samples in [
      Float32List(0),
      Float32List.fromList([double.nan]),
      Float32List.fromList([double.infinity]),
      Float32List.fromList([1.1]),
    ]) {
      expect(
        () => liteRtLmEmbeddingWav(samples),
        throwsA(isA<LlamaArgumentException>()),
      );
    }
  });
  test(
    'JPEG and PCM16 WAV decode; corrupt WAV shapes never reach inference',
    () {
      final jpg = image.encodeJpg(image.Image(width: 2, height: 2));
      expect(
        prepareLiteRtLmEmbedding(
          LlamaEmbeddingInput([LlamaImageContent(bytes: jpg)]),
        ).single.type,
        1,
      );
      final valid = liteRtLmEmbeddingWav(Float32List.fromList([0.5, -0.5]));
      expect(
        prepareLiteRtLmEmbedding(
          LlamaEmbeddingInput([LlamaAudioContent(bytes: valid)]),
        ).single.bytes,
        valid,
      );
      final pcm16 = Uint8List(48)..setAll(0, valid.sublist(0, 44));
      final data = ByteData.sublistView(pcm16);
      data.setUint32(4, 40, Endian.little);
      data.setUint16(20, 1, Endian.little);
      data.setUint16(34, 16, Endian.little);
      data.setUint16(32, 2, Endian.little);
      data.setUint32(28, 32000, Endian.little);
      data.setUint32(40, 4, Endian.little);
      expect(
        prepareLiteRtLmEmbedding(
          LlamaEmbeddingInput([LlamaAudioContent(bytes: pcm16)]),
        ).single.type,
        3,
      );
      final corruptions = <void Function(ByteData)>[
        (b) => b.setUint32(4, 0, Endian.little),
        (b) => b.setUint32(16, 8, Endian.little),
        (b) => b.setUint32(16, 1000, Endian.little),
        (b) => b.setUint16(22, 2, Endian.little),
        (b) => b.setUint32(24, 48000, Endian.little),
        (b) => b.setUint16(20, 99, Endian.little),
        (b) => b.setUint16(32, 1, Endian.little),
        (b) => b.setUint32(28, 1, Endian.little),
        (b) => b.setUint32(40, 7, Endian.little),
        (b) => b.setUint32(36, 0, Endian.little),
        (b) => b.setFloat32(44, double.nan, Endian.little),
        (b) => b.setFloat32(44, 2, Endian.little),
      ];
      for (final corrupt in corruptions) {
        final bytes = Uint8List.fromList(valid);
        corrupt(ByteData.sublistView(bytes));
        expect(
          () => prepareLiteRtLmEmbedding(
            LlamaEmbeddingInput([LlamaAudioContent(bytes: bytes)]),
          ),
          throwsA(isA<LlamaInferenceException>()),
        );
      }
    },
  );
  test('reads only actual TFLite embedding processor sections', () {
    final header = embeddingBundleHeader();
    final all = liteRtLmEmbeddingBundleCapabilities(header);
    expect([all.text, all.image, all.audio], [true, true, true]);
    for (final kind in [
      'tf_lite_embedder',
      'tf_lite_text_encoder',
      'tf_lite_vision_adapter',
      'tf_lite_vision_encoder',
      'tf_lite_audio_adapter',
      'tf_lite_audio_encoder_hw',
    ]) {
      final changed = Uint8List.fromList(header);
      final needle = utf8.encode(kind);
      for (var i = 0; i <= changed.length - needle.length; i++) {
        if (List.generate(
          needle.length,
          (j) => changed[i + j] == needle[j],
        ).every((v) => v)) {
          changed[i] = 88;
        }
      }
      final caps = liteRtLmEmbeddingBundleCapabilities(changed);
      expect(
        caps.text,
        !['tf_lite_embedder', 'tf_lite_text_encoder'].contains(kind),
      );
      if (kind.contains('vision')) expect(caps.image, isFalse);
      if (kind.contains('audio')) expect(caps.audio, isFalse);
    }
  });
  test('unknown truncated malformed and excessive headers enable nothing', () {
    for (final header in [
      Uint8List(0),
      Uint8List(32),
      embeddingBundleHeader().sublist(0, 40),
      Uint8List.fromList(embeddingBundleHeader())..[32] = 255,
    ]) {
      final caps = liteRtLmEmbeddingBundleCapabilities(header);
      expect([caps.text, caps.image, caps.audio], [false, false, false]);
    }
  });
}

/// Bounded header from the qualified bundle; contains no weights or media.
Uint8List embeddingBundleHeader() => base64Decode(
  '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',
);
