import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import 'image_model_classifier.dart';

/// Refuses FP8 weights before an image runtime older than
/// stable-diffusion-native v0.3.0-1 constructs a Metal context. This is a
/// kernel safety check, not model-family qualification.
/// [name] identifies a file by position or role, never by its private path.
Future<void> validateImageModelMetalDtypes(
  ImageModelFileReader read, {
  required String name,
  required bool isJsonIndex,
}) async {
  final Uint8List prefix;
  try {
    prefix = await read(0, 9);
  } catch (_) {
    throw LlamaModelException('Cannot read the header of $name.');
  }
  final gguf =
      prefix.length >= 4 &&
      ascii.decode(prefix.sublist(0, 4), allowInvalid: true) == 'GGUF';
  // Native format precedence gives GGUF magic priority over a .json suffix.
  // Other ordinary JSON indexes can name FP8 shards this reader cannot inspect.
  // The qualified local-set API is CPU-only.
  if (isJsonIndex && !gguf) {
    throw _uninspectable(name);
  }
  final safetensors =
      prefix.length >= 9 &&
      ((ByteData.sublistView(prefix).getUint32(0, Endian.little) > 2 &&
              ByteData.sublistView(prefix).getUint32(4, Endian.little) == 0) ||
          const [0x7b, 0x20, 0x09, 0x0a, 0x0d].contains(prefix[8]));
  // The pinned Torch ZIP/legacy parser accepts typed float/integer storage,
  // but no FP8 storage. Preserve its existing explicit-role native loading.
  if (!gguf && !safetensors) return;

  final ImageModelFileHeader header;
  try {
    header = await readImageModelFileHeader(
      read,
      stopAtLanguageModelArchitecture: false,
    );
  } on FormatException {
    throw _uninspectable(name);
  } catch (_) {
    throw LlamaModelException('Cannot read the header of $name.');
  }
  for (final tensor in header.tensors) {
    // Up to stable-diffusion-native v0.3.0 (upstream 0518b343, ggml dc998771).
    if (_isFp8(tensor)) {
      throw LlamaUnsupportedException(
        'FP8 image weights in $name are not supported on Metal by this '
        'stable_diffusion runtime: context creation can abort the process '
        '(https://github.com/leehack/llamadart/issues/1446). '
        'stable-diffusion-native v0.3.0-1 or later loads them as F16. '
        'Use ComputeDevice.cpu or compatible non-FP8 weights.',
      );
    }
    if (!header.isGguf && tensor.dtype == null) {
      throw _uninspectable(name);
    }
  }
}

LlamaUnsupportedException _uninspectable(String name) =>
    LlamaUnsupportedException(
      'Cannot verify the tensor dtypes of $name for Metal. This '
      'stable_diffusion runtime can abort on FP8 weights, which '
      'stable-diffusion-native v0.3.0-1 or later loads as F16; use a bounded '
      'GGUF or Safetensors header, or select ComputeDevice.cpu '
      '(https://github.com/leehack/llamadart/issues/1446).',
    );

/// The bytes a runtime that loads FP8 weights as F16 on Metal adds to the
/// file size of [read]'s weights: one per FP8 element. 0 when the file is
/// not a GGUF or Safetensors file whose header can be read.
Future<int> imageModelFp8AsF16ExtraBytes(ImageModelFileReader read) async {
  final ImageModelFileHeader header;
  try {
    header = await readImageModelFileHeader(
      read,
      stopAtLanguageModelArchitecture: false,
    );
  } catch (_) {
    return 0;
  }
  var bytes = 0;
  for (final tensor in header.tensors.where(_isFp8)) {
    bytes += tensor.shape.fold(1, (count, dimension) => count * dimension);
  }
  return bytes;
}

bool _isFp8(ImageModelTensor tensor) =>
    tensor.dtype == 'F8_E4M3' ||
    tensor.dtype == 'F8_E5M2' ||
    tensor.ggufType == 43 ||
    tensor.ggufType == 44;
