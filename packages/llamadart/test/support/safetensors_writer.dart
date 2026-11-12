import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A tensor to write with [writeSafetensors].
final class TestTensor {
  TestTensor(this.dtype, this.shape, this.bytes);

  TestTensor.f32(List<int> shape, List<double> values)
    : this('F32', shape, Float32List.fromList(values).buffer.asUint8List());

  TestTensor.bits16(String dtype, List<int> shape, List<int> bits)
    : this(dtype, shape, Uint16List.fromList(bits).buffer.asUint8List());

  final String dtype;
  final List<int> shape;
  final Uint8List bytes;
}

/// Writes [tensors] as a safetensors file at [path], in map order.
File writeSafetensors(
  String path,
  Map<String, TestTensor> tensors, {
  Map<String, String>? metadata,
}) {
  final header = <String, Object?>{'__metadata__': ?metadata};
  final data = BytesBuilder(copy: false);
  for (final MapEntry(key: name, value: tensor) in tensors.entries) {
    header[name] = {
      'dtype': tensor.dtype,
      'shape': tensor.shape,
      'data_offsets': [data.length, data.length + tensor.bytes.length],
    };
    data.add(tensor.bytes);
  }
  return writeRawSafetensors(path, jsonEncode(header), data.takeBytes());
}

/// Writes [header] and [data] with an 8-byte little-endian header length,
/// [headerLength] when given.
File writeRawSafetensors(
  String path,
  String header,
  List<int> data, {
  int? headerLength,
}) {
  final headerBytes = utf8.encode(header);
  final prefix = ByteData(8)
    ..setUint64(0, headerLength ?? headerBytes.length, Endian.little);
  return File(path)..writeAsBytesSync([
    ...prefix.buffer.asUint8List(),
    ...headerBytes,
    ...data,
  ]);
}
