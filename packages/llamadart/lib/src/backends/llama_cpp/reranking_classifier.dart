import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/exceptions.dart';

/// Checks a bounded GGUF tensor directory for the pinned runtime's classifier.
///
/// BERT/Jina artifacts often omit RANK metadata; their classifier tensors must
/// be verified before an explicit reranker load creates a RANK context. This
/// never interprets tensor payloads or infers a classifier from a filename/model tag.
bool hasRerankingClassifier(String source, int outputs) {
  try {
    final file = File(source).openSync();
    late final Uint8List bytes;
    try {
      bytes = file.readSync(math.min(file.lengthSync(), 64 * 1024 * 1024));
    } finally {
      file.closeSync();
    }
    final reader = _DirectoryReader(bytes);
    if (reader.u32() != 0x46554747 || !const [2, 3].contains(reader.u32())) {
      return false;
    }
    final tensors = reader.u64();
    final metadata = reader.u64();
    if (tensors > 100000 || metadata > 1000000) return false;
    for (var i = 0; i < metadata; i++) {
      reader.skipString();
      reader.skipValue(reader.u32());
    }
    List<int>? projection;
    List<int>? classifier;
    for (var i = 0; i < tensors; i++) {
      final name = reader.string();
      final rank = reader.u32();
      if (rank < 1 || rank > 4) return false;
      final shape = [for (var d = 0; d < rank; d++) reader.u64()];
      reader.skip(12); // Tensor type and payload offset are not dereferenced.
      if (name == 'cls.output.weight') projection = shape;
      if (name == 'cls.weight') classifier = shape;
    }
    final head = projection ?? classifier;
    // GGUF elides trailing unit dimensions; native loaders read [width] as
    // [width, 1]. Jina tiny also omits the separate cls.output projection.
    return outputs > 0 &&
        head != null &&
        head[0] > 0 &&
        ((head.length == 1 && outputs == 1) ||
            (head.length == 2 && head[1] == outputs));
  } on Object {
    return false;
  }
}

class _DirectoryReader {
  _DirectoryReader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int position = 0;
  void skip(int count) {
    if (count < 0 || count > bytes.length - position) {
      throw LlamaUnsupportedException(
        'GGUF classifier directory exceeds the bounded header or is truncated.',
      );
    }
    position += count;
  }

  int u32() {
    final start = position;
    skip(4);
    return data.getUint32(start, Endian.little);
  }

  int u64() {
    final start = position;
    skip(8);
    final value = data.getUint64(start, Endian.little);
    if (value < 0) throw const FormatException('GGUF count overflow');
    return value;
  }

  void skipString() => skip(u64());
  String string() {
    final count = u64();
    if (count > 4096) throw const FormatException('GGUF tensor name too long');
    final start = position;
    skip(count);
    return utf8.decode(Uint8List.sublistView(bytes, start, position));
  }

  void skipValue(int type) {
    const widths = {
      0: 1,
      1: 1,
      2: 2,
      3: 2,
      4: 4,
      5: 4,
      6: 4,
      7: 1,
      10: 8,
      11: 8,
      12: 8,
    };
    if (type == 8) {
      skipString();
      return;
    }
    if (type == 9) {
      final element = u32();
      final count = u64();
      if (element == 8) {
        if (count > 1000000) throw const FormatException('GGUF array too long');
        for (var i = 0; i < count; i++) {
          skipString();
        }
      } else {
        final width = widths[element];
        if (width == null || count > bytes.length ~/ width) {
          throw const FormatException('Unsupported GGUF array');
        }
        skip(count * width);
      }
      return;
    }
    final width = widths[type];
    if (width == null) throw const FormatException('Unsupported GGUF value');
    skip(width);
  }
}
