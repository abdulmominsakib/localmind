import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/exceptions.dart';

const int _maxHeaderBytes = 100 * 1024 * 1024;

const Map<String, int> _dtypeBytes = {
  'BOOL': 1,
  'U8': 1,
  'I8': 1,
  'F8_E5M2': 1,
  'F8_E4M3': 1,
  'I16': 2,
  'U16': 2,
  'F16': 2,
  'BF16': 2,
  'I32': 4,
  'U32': 4,
  'F32': 4,
  'I64': 8,
  'U64': 8,
  'F64': 8,
};

/// A tensor entry of a safetensors header.
final class SafetensorsTensor {
  SafetensorsTensor._(this.dtype, this.shape, this._begin, this._end);

  /// Safetensors dtype name, such as `F32`.
  final String dtype;

  /// Dimensions, outermost first.
  final List<int> shape;

  final int _begin;
  final int _end;
}

/// A safetensors file whose tensor bytes are read on demand.
final class SafetensorsFile {
  SafetensorsFile._(
    this.path,
    this._file,
    this._dataStart,
    this.metadata,
    this.tensors,
  );

  /// Opens [path] and parses its header without reading tensor bytes.
  ///
  /// Throws [LlamaModelException] naming [path] when the file cannot be read
  /// or its header is malformed, such as a header length that does not fit
  /// the file, invalid JSON, non-string metadata, or a tensor whose byte range
  /// lies outside the data section or, for a known dtype, does not match its
  /// shape.
  static SafetensorsFile open(String path) {
    final RandomAccessFile file;
    try {
      file = File(path).openSync();
    } on FileSystemException catch (error) {
      throw LlamaModelException(
        'Cannot open safetensors file "$path": ${_reason(error)}.',
      );
    }
    try {
      return _parse(path, file);
    } on FileSystemException catch (error) {
      file.closeSync();
      throw LlamaModelException(
        'Cannot read safetensors file "$path": ${_reason(error)}.',
      );
    } catch (_) {
      file.closeSync();
      rethrow;
    }
  }

  static SafetensorsFile _parse(String path, RandomAccessFile file) {
    Never malformed(String reason) =>
        throw LlamaModelException('Invalid safetensors file "$path": $reason.');

    final fileLength = file.lengthSync();
    if (fileLength < 8) {
      malformed('$fileLength bytes is too short for the 8-byte header length');
    }
    final prefix = _readExactly(path, file, 0, Uint8List(8));
    final headerLength = ByteData.sublistView(
      prefix,
    ).getUint64(0, Endian.little);
    if (headerLength < 2 ||
        headerLength > fileLength - 8 ||
        headerLength > _maxHeaderBytes) {
      malformed(
        'header length ${BigInt.from(headerLength).toUnsigned(64)} does not '
        'fit a $fileLength-byte file (at most $_maxHeaderBytes bytes)',
      );
    }

    final Object? header;
    try {
      header = jsonDecode(
        utf8.decode(_readExactly(path, file, 8, Uint8List(headerLength))),
      );
    } on FormatException catch (error) {
      malformed('header is not UTF-8 JSON (${error.message})');
    }
    if (header is! Map<String, Object?>) {
      malformed('header is not a JSON object');
    }

    final dataStart = 8 + headerLength;
    final dataLength = fileLength - dataStart;
    var metadata = const <String, String>{};
    final tensors = <String, SafetensorsTensor>{};
    for (final MapEntry(key: name, :value) in header.entries) {
      if (name == '__metadata__') {
        if (value is! Map ||
            value.values.any((metadataValue) => metadataValue is! String)) {
          malformed('__metadata__ is not a map of strings');
        }
        metadata = Map.unmodifiable(value.cast<String, String>());
        continue;
      }
      if (value is! Map) malformed('tensor "$name" is not a JSON object');
      final dtype = value['dtype'];
      final shape = value['shape'];
      final offsets = value['data_offsets'];
      if (dtype is! String) malformed('tensor "$name" has no string dtype');
      if (shape is! List || shape.any((dim) => dim is! int || dim < 0)) {
        malformed('tensor "$name" shape $shape is not a list of sizes');
      }
      if (offsets is! List ||
          offsets.length != 2 ||
          offsets[0] is! int ||
          offsets[1] is! int) {
        malformed('tensor "$name" data_offsets $offsets is not [begin, end]');
      }
      final begin = offsets[0] as int;
      final end = offsets[1] as int;
      if (begin < 0 || begin > end || end > dataLength) {
        malformed(
          'tensor "$name" data_offsets [$begin, $end] fall outside the '
          '$dataLength-byte data section',
        );
      }
      final dims = List<int>.unmodifiable(shape.cast<int>());
      final elementBytes = _dtypeBytes[dtype];
      if (elementBytes != null) {
        var elements = dims.contains(0) ? 0 : 1;
        for (final dim in dims) {
          if (elements > dataLength ~/ math.max(dim, 1)) {
            elements = dataLength + 1;
            break;
          }
          elements *= dim;
        }
        if (elements > dataLength || elements * elementBytes != end - begin) {
          malformed(
            'tensor "$name" is $dtype $dims but spans ${end - begin} bytes',
          );
        }
      }
      tensors[name] = SafetensorsTensor._(dtype, dims, begin, end);
    }
    return SafetensorsFile._(
      path,
      file,
      dataStart,
      metadata,
      Map.unmodifiable(tensors),
    );
  }

  /// Path the file was opened from.
  final String path;

  /// The header's `__metadata__` entries; empty when it has none.
  final Map<String, String> metadata;

  /// Tensor entries by name.
  final Map<String, SafetensorsTensor> tensors;

  final RandomAccessFile _file;
  final int _dataStart;
  bool _closed = false;

  /// Reads tensor [name] and converts it to F32.
  ///
  /// Supports F32, F16 and BF16 tensors. Throws [LlamaModelException] when
  /// the tensor is missing, has another dtype or cannot be read in full, and
  /// [LlamaStateException] after [close].
  Float32List readFloat32(String name) {
    final (tensor, count) = _floatTensor(name);
    final values = Float32List(count);
    _readFloat32(tensor, values);
    return values;
  }

  /// Reads tensor [name] into [target], converting it to F32.
  ///
  /// [target] may view native memory. Throws what [readFloat32] throws, and
  /// [ArgumentError] when [target]'s length is not the tensor's element
  /// count.
  void readFloat32Into(String name, Float32List target) {
    final (tensor, count) = _floatTensor(name);
    if (target.length != count) {
      throw ArgumentError(
        'Tensor "$name" has $count elements; the target has ${target.length}.',
      );
    }
    _readFloat32(tensor, target);
  }

  (SafetensorsTensor, int) _floatTensor(String name) {
    if (_closed) {
      throw LlamaStateException('Safetensors file "$path" is closed.');
    }
    final tensor = tensors[name];
    if (tensor == null) {
      throw LlamaModelException(
        'Safetensors file "$path" has no tensor "$name".',
      );
    }
    final dtype = tensor.dtype;
    if (dtype != 'F32' && dtype != 'F16' && dtype != 'BF16') {
      throw LlamaModelException(
        'Tensor "$name" in "$path" is $dtype; only F32, F16 and BF16 tensors '
        'convert to F32.',
      );
    }
    return (tensor, (tensor._end - tensor._begin) ~/ _dtypeBytes[dtype]!);
  }

  void _readFloat32(SafetensorsTensor tensor, Float32List target) {
    final position = _dataStart + tensor._begin;
    if (tensor.dtype == 'F32') {
      _readExactly(
        path,
        _file,
        position,
        target.buffer.asUint8List(target.offsetInBytes, target.lengthInBytes),
      );
      return;
    }
    final halves = _readExactly(
      path,
      _file,
      position,
      Uint8List(target.length * 2),
    ).buffer.asUint16List();
    final bits = target.buffer.asUint32List(
      target.offsetInBytes,
      target.length,
    );
    if (tensor.dtype == 'F16') {
      final table = _halfToFloatBits;
      for (var i = 0; i < halves.length; i++) {
        bits[i] = table[halves[i]];
      }
    } else {
      for (var i = 0; i < halves.length; i++) {
        bits[i] = halves[i] << 16;
      }
    }
  }

  /// Closes the file. Later reads throw; closing again does nothing. A failure
  /// to close is ignored, because the file is only read.
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _file.closeSync();
    } on FileSystemException catch (_) {}
  }
}

Uint8List _readExactly(
  String path,
  RandomAccessFile file,
  int position,
  Uint8List bytes,
) {
  final length = bytes.length;
  try {
    file.setPositionSync(position);
    var read = 0;
    while (read < length) {
      final count = file.readIntoSync(bytes, read);
      if (count <= 0) {
        throw LlamaModelException(
          'Safetensors file "$path" ended $read bytes into a $length-byte read '
          'at offset $position.',
        );
      }
      read += count;
    }
  } on FileSystemException catch (error) {
    throw LlamaModelException(
      'Cannot read safetensors file "$path": ${_reason(error)}.',
    );
  }
  return bytes;
}

String _reason(FileSystemException error) =>
    error.osError?.message ?? error.message;

final Uint32List _halfToFloatBits = Uint32List.fromList([
  for (var half = 0; half < 0x10000; half++) _halfBitsToFloatBits(half),
]);

int _halfBitsToFloatBits(int half) {
  final sign = (half & 0x8000) << 16;
  final exponent = (half >> 10) & 0x1f;
  var mantissa = half & 0x3ff;
  if (exponent == 0x1f) return sign | 0x7f800000 | (mantissa << 13);
  if (exponent != 0) return sign | ((exponent + 112) << 23) | (mantissa << 13);
  if (mantissa == 0) return sign;
  var floatExponent = 113;
  while (mantissa & 0x400 == 0) {
    mantissa <<= 1;
    floatExponent--;
  }
  return sign | (floatExponent << 23) | ((mantissa & 0x3ff) << 13);
}
