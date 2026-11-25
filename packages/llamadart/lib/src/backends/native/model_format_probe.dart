import 'dart:io';

import '../../core/exceptions.dart';
import '../../core/models/model_format.dart';

/// The format read from the header of the local file at [path], or null when
/// the file cannot be read or its header matches no [ModelFormat].
Future<ModelFormat?> readModelFormatHeader(String path) async {
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    return ModelFormat.fromHeader(await file.read(ModelFormat.headerLength));
  } on FileSystemException {
    return null;
  } finally {
    await file?.close();
  }
}

/// The format to load the local file at [path] as.
///
/// The file header decides when it is recognized. Otherwise [requested], then
/// the file extension, then GGUF. Throws [LlamaModelFormatException] when a
/// recognized header contradicts [requested] or, without one, a model file
/// extension.
Future<ModelFormat> resolveLocalModelFormat(
  String path, {
  ModelFormat? requested,
}) async {
  final declared = requested ?? ModelFormat.fromPath(path);
  final detected = await readModelFormatHeader(path);
  if (detected == null) return declared ?? ModelFormat.gguf;
  if (declared != null && declared != detected) {
    throw LlamaModelFormatException(detected: detected, declared: declared);
  }
  return detected;
}
