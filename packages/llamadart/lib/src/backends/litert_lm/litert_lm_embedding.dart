import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../../core/exceptions.dart';
import '../../core/models/chat/content_part.dart';
import '../../core/models/inference/embedding.dart';

/// Rejects unqualified accelerators before loading or calling the native ABI.
void ensureLiteRtLmNativeEmbeddingBackend(String backend) {
  if (backend != 'cpu') {
    throw LlamaUnsupportedException(
      backend == 'gpu'
          ? 'LiteRT-LM native GPU embeddings are unavailable: EmbeddingGemma 2 crashed in the WebGPU accelerator with the absl ABI mismatch that google-ai-edge/LiteRT@dd3db31236 repairs, and no runtime has been requalified on GPU since. Select CPU.'
          : 'LiteRT-LM native embeddings are qualified only on CPU; select ComputeDevice.cpu.',
    );
  }
}

/// A copied runtime input; type values follow LiteRtLmInputDataType.
class LiteRtLmEmbeddingPart {
  /// Text (0), encoded image (1), or encoded audio (3).
  final int type;

  /// Owned UTF-8 or encoded media, safe to send to a worker.
  final Uint8List bytes;

  /// Creates an owned runtime input.
  LiteRtLmEmbeddingPart(this.type, this.bytes);
}

/// Worker-owned session contract shared by version-specific embedding ABIs.
abstract interface class LiteRtLmEmbeddingRuntimeSession {
  /// Processor-backed modalities of the loaded bundle.
  LlamaEmbeddingCapabilities get capabilities;

  /// Copies one vector from the selected runtime's owned native response.
  Future<List<double>> compute(
    List<LiteRtLmEmbeddingPart> input, {
    required bool normalize,
  });

  /// Releases a settled engine exactly once.
  void dispose();
}

/// Snapshots bytes, rejects unresolved sources and merges adjacent text verbatim.
List<LiteRtLmEmbeddingPart> prepareLiteRtLmEmbedding(
  LlamaEmbeddingInput input,
) {
  final result = <LiteRtLmEmbeddingPart>[];
  final text = StringBuffer();
  var hasText = false;
  void flush() {
    if (hasText) {
      result.add(
        LiteRtLmEmbeddingPart(
          0,
          Uint8List.fromList(utf8.encode(text.toString())),
        ),
      );
    }
    text.clear();
    hasText = false;
  }

  for (final part in input.parts) {
    if (part is LlamaTextContent) {
      text.write(part.text);
      hasText = true;
      continue;
    }
    flush();
    switch (part) {
      case LlamaImageContent():
        if (part.path != null || part.url != null || part.bytes == null) {
          throw LlamaUnsupportedException(
            'LiteRT-LM embedding images require encoded PNG or JPEG bytes; paths and URLs are unsupported.',
          );
        }
        final bytes = Uint8List.fromList(part.bytes!);
        final png =
            bytes.length >= 8 &&
            bytes[0] == 137 &&
            ascii.decode(bytes.sublist(1, 4), allowInvalid: true) == 'PNG';
        final jpeg =
            bytes.length >= 3 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255;
        if (!png && !jpeg) {
          throw LlamaUnsupportedException(
            'LiteRT-LM embedding images require encoded PNG or JPEG bytes.',
          );
        }
        try {
          final decoded = png ? image.decodePng(bytes) : image.decodeJpg(bytes);
          if (decoded == null) {
            throw const FormatException();
          }
        } on Object {
          throw LlamaInferenceException(
            'LiteRT-LM embedding image decoding failed.',
          );
        }
        result.add(LiteRtLmEmbeddingPart(1, bytes));
      case LlamaAudioContent():
        if (part.path != null ||
            (part.samples == null) == (part.bytes == null)) {
          throw LlamaUnsupportedException(
            'LiteRT-LM embedding audio requires mono 16 kHz PCM samples or WAV bytes; paths and multiple sources are unsupported.',
          );
        }
        final bytes = part.samples != null
            ? liteRtLmEmbeddingWav(part.samples!)
            : Uint8List.fromList(part.bytes!);
        if (bytes.length < 44 ||
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
          throw LlamaUnsupportedException(
            'LiteRT-LM embedding audio requires WAV bytes or mono 16 kHz PCM samples.',
          );
        }
        _validateWav(bytes);
        result.add(LiteRtLmEmbeddingPart(3, bytes));
      default:
        throw LlamaUnsupportedException(
          'LiteRT-LM embeddings support text, image and audio only.',
        );
    }
  }
  flush();
  return result;
}

// Decode the accepted WAV subset before any batch item reaches inference.
void _validateWav(Uint8List bytes) {
  try {
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(4, Endian.little) + 8 != bytes.length) {
      throw const FormatException();
    }
    int? format, bits, blockAlign;
    var hasData = false;
    for (var offset = 12; offset < bytes.length;) {
      final size = data.getUint32(offset + 4, Endian.little);
      final start = offset + 8;
      final end = start + size;
      if (end > bytes.length) throw const FormatException();
      final kind = ascii.decode(bytes.sublist(offset, offset + 4));
      if (kind == 'fmt ') {
        if (size < 16) throw const FormatException();
        format = data.getUint16(start, Endian.little);
        bits = data.getUint16(start + 14, Endian.little);
        blockAlign = data.getUint16(start + 12, Endian.little);
        if (data.getUint16(start + 2, Endian.little) != 1 ||
            data.getUint32(start + 4, Endian.little) != 16000 ||
            !((format == 1 && bits == 16) || (format == 3 && bits == 32)) ||
            blockAlign != bits ~/ 8 ||
            data.getUint32(start + 8, Endian.little) != 16000 * blockAlign) {
          throw const FormatException();
        }
      } else if (kind == 'data') {
        if (format == null || size == 0 || size % blockAlign! != 0) {
          throw const FormatException();
        }
        hasData = true;
        if (format == 3) {
          for (var i = start; i < end; i += 4) {
            final sample = data.getFloat32(i, Endian.little);
            if (!sample.isFinite || sample.abs() > 1) {
              throw const FormatException();
            }
          }
        }
      }
      offset = end + (size & 1);
    }
    if (!hasData) throw const FormatException();
  } on Object {
    throw LlamaInferenceException(
      'LiteRT-LM embedding WAV decoding failed; use mono 16 kHz PCM16 or Float32 WAV.',
    );
  }
}

/// Encodes the portable mono 16 kHz PCM convention as IEEE Float32 WAV.
Uint8List liteRtLmEmbeddingWav(Float32List samples) {
  if (samples.isEmpty ||
      samples.any((value) => !value.isFinite || value.abs() > 1)) {
    throw LlamaArgumentException(
      'Embedding PCM must contain finite samples in [-1, 1].',
    );
  }
  final bytes = Uint8List(44 + samples.length * 4);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 3, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 64000, Endian.little);
  data.setUint16(32, 4, Endian.little);
  data.setUint16(34, 32, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, samples.length * 4, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setFloat32(44 + i * 4, samples[i], Endian.little);
  }
  return bytes;
}

/// Reads actual TFLite section model_type metadata from a bounded bundle header.
/// Unknown/malformed headers enable no modalities.
LlamaEmbeddingCapabilities liteRtLmEmbeddingBundleCapabilities(
  Uint8List bytes,
) {
  try {
    if (bytes.length < 32 || ascii.decode(bytes.sublist(0, 8)) != 'LITERTLM') {
      return const LlamaEmbeddingCapabilities();
    }
    final prefix = ByteData.sublistView(bytes);
    if (prefix.getUint32(28, Endian.little) != 0) {
      return const LlamaEmbeddingCapabilities();
    }
    final end = prefix.getUint32(24, Endian.little);
    if (end > bytes.length || end <= 32 || end > 16 * 1024 * 1024) {
      return const LlamaEmbeddingCapabilities();
    }
    final b = ByteData.sublistView(bytes, 32, end);
    int u32(int p) => b.getUint32(p, Endian.little);
    int indirect(int p) => p + u32(p);
    int? field(int table, int index) {
      final v = table - b.getInt32(table, Endian.little);
      final slot = 4 + index * 2;
      if (slot >= b.getUint16(v, Endian.little)) {
        return null;
      }
      final offset = b.getUint16(v + slot, Endian.little);
      return offset == 0 ? null : table + offset;
    }

    List<int> tables(int location) {
      final p = indirect(location);
      final count = u32(p);
      if (count > b.lengthInBytes ~/ 4) {
        throw const FormatException();
      }
      return [for (var i = 0; i < count; i++) indirect(p + 4 + i * 4)];
    }

    String string(int location) {
      final p = indirect(location);
      return utf8.decode(b.buffer.asUint8List(b.offsetInBytes + p + 4, u32(p)));
    }

    final sections = field(indirect(0), 1);
    if (sections == null) {
      return const LlamaEmbeddingCapabilities();
    }
    final objects = field(indirect(sections), 0);
    if (objects == null) {
      return const LlamaEmbeddingCapabilities();
    }
    final types = <String>{};
    for (final section in tables(objects)) {
      final type = field(section, 3);
      if (type == null || b.getUint8(type) != 3) {
        continue;
      }
      final items = field(section, 0);
      if (items == null) {
        continue;
      }
      for (final item in tables(items)) {
        final key = field(item, 0),
            kind = field(item, 1),
            value = field(item, 2);
        if (key == null ||
            kind == null ||
            value == null ||
            b.getUint8(kind) != 9 ||
            string(key) != 'model_type') {
          continue;
        }
        final text = field(indirect(value), 0);
        if (text != null) {
          types.add(string(text));
        }
      }
    }
    final text =
        types.contains('tf_lite_text_encoder') &&
        types.contains('tf_lite_embedder');
    return LlamaEmbeddingCapabilities(
      text: text,
      image:
          text &&
          types.contains('tf_lite_vision_encoder') &&
          types.contains('tf_lite_vision_adapter'),
      audio:
          text &&
          types.contains('tf_lite_audio_encoder_hw') &&
          types.contains('tf_lite_audio_adapter'),
    );
  } on Object {
    return const LlamaEmbeddingCapabilities();
  }
}
