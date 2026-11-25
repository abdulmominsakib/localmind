import 'dart:convert';
import 'dart:typed_data';

import '../exceptions.dart';
import 'image_generation_model.dart';

/// Reads [length] bytes of a file from [offset]; returns fewer at its end.
typedef ImageModelFileReader =
    Future<Uint8List> Function(int offset, int length);

/// Shape and name of one tensor in a model file header.
class ImageModelTensor {
  /// Tensor name as stored in the file.
  final String name;

  /// Dimensions as stored: GGUF lists the innermost first, safetensors the
  /// outermost first.
  final List<int> shape;

  /// Safetensors dtype, when read from that container.
  final String? dtype;

  /// GGUF tensor type wire value, when read from that container.
  final int? ggufType;

  /// Creates a tensor description.
  const ImageModelTensor(this.name, this.shape, {this.dtype, this.ggufType});
}

/// The metadata and tensor list of a GGUF or safetensors file.
class ImageModelFileHeader {
  /// Whether the file is GGUF; otherwise it is safetensors.
  final bool isGguf;

  /// GGUF key-value metadata (array values are left out), or the
  /// safetensors `__metadata__` object.
  final Map<String, Object?> metadata;

  /// Every tensor, or none when [stoppedAtArchitecture].
  final List<ImageModelTensor> tensors;

  /// Whether reading stopped after `general.architecture` named a language
  /// model, without reading the rest of the header.
  final bool stoppedAtArchitecture;

  /// Creates a header.
  const ImageModelFileHeader({
    required this.isGguf,
    required this.metadata,
    required this.tensors,
    this.stoppedAtArchitecture = false,
  });

  /// GGUF `general.architecture`, if any.
  String? get architecture => metadata['general.architecture'] as String?;
}

/// GGUF architectures of llama.cpp language models, usable only as the `llm`
/// text encoder. Reading stops at `general.architecture` for these, before
/// their large tokenizer arrays.
const Set<String> imageModelLanguageModelArchitectures = <String>{
  'llama',
  'mistral',
  'mistral3',
  'qwen2',
  'qwen2vl',
  'qwen25vl',
  'qwen3',
  'qwen3moe',
  'qwen3vl',
  'gemma2',
  'gemma3',
  'glm4',
  'phi3',
  'minicpm',
  'llada',
  'llada-moe',
};

// Bounds on what a header may declare, so a crafted file fails fast instead
// of costing seconds and gigabytes. The largest real values, from 70 GGUF and
// safetensors files of image models and llama.cpp language models, are in
// parentheses; each bound leaves a wide margin above them.

/// GGUF tensors (1411, a Gemma 4 projector; the largest MoE models have
/// about 3000).
const int maxImageModelGgufTensors = 1 << 16;

/// GGUF metadata keys (56).
const int maxImageModelGgufKeys = 1 << 16;

/// Items in one GGUF array (514906, Gemma 4's tokenizer merges).
const int maxImageModelGgufArrayItems = 1 << 22;

/// Bytes in one GGUF string (16982, a chat template).
const int maxImageModelGgufStringBytes = 1 << 20;

/// Bytes of a whole GGUF header (15.8 MB, Gemma 4).
const int maxImageModelHeaderBytes = 64 << 20;

/// Bytes of a safetensors JSON header (0.39 MB, an SDXL checkpoint).
const int maxImageModelSafetensorsHeaderBytes = 16 << 20;
const Map<int, int> _ggufScalarBytes = <int, int>{
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

/// Reads the header of a GGUF or safetensors file through [read], fetching
/// only the header bytes. Set [stopAtLanguageModelArchitecture] to false
/// when every tensor type is needed, including language-model encoders.
///
/// Throws [FormatException] when the file is neither, or its header is
/// truncated or implausible.
Future<ImageModelFileHeader> readImageModelFileHeader(
  ImageModelFileReader read, {
  bool stopAtLanguageModelArchitecture = true,
}) async {
  final reader = _HeaderReader(read);
  final magic = await reader.bytes(4);
  if (ascii.decode(magic, allowInvalid: true) == 'GGUF') {
    return _readGguf(reader, stopAtLanguageModelArchitecture);
  }
  reader.position = 0;
  final length = await reader.u64();
  if (length < 2 || length > maxImageModelSafetensorsHeaderBytes) {
    throw const FormatException('Not a GGUF or safetensors file.');
  }
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(await reader.bytes(length)));
  } on FormatException {
    throw const FormatException('Not a GGUF or safetensors file.');
  }
  if (json is! Map<String, Object?>) {
    throw const FormatException('Not a GGUF or safetensors file.');
  }
  final metadata = json['__metadata__'];
  final tensors = <ImageModelTensor>[];
  for (final MapEntry(key: name, value: info) in json.entries) {
    if (name == '__metadata__') {
      continue;
    }
    final shape = info is Map ? info['shape'] : null;
    if (shape is! List || shape.any((dim) => dim is! int)) {
      throw const FormatException('Malformed safetensors header.');
    }
    tensors.add(
      ImageModelTensor(
        name,
        shape.cast<int>(),
        dtype: info is Map && info['dtype'] is String
            ? info['dtype'] as String
            : null,
      ),
    );
  }
  return ImageModelFileHeader(
    isGguf: false,
    metadata: metadata is Map ? metadata.cast<String, Object?>() : const {},
    tensors: tensors,
  );
}

/// Reads the GGUF key/value metadata through [read], stopping after the key
/// [stopAt] or at the end of the block; tensor infos are not read. At most
/// [maxBytes] of the file are parsed.
///
/// Throws [FormatException] when the file is not GGUF, or its metadata is
/// truncated, implausible or longer than [maxBytes].
Future<Map<String, Object?>> readGgufMetadata(
  ImageModelFileReader read, {
  required int maxBytes,
  String? stopAt,
}) async {
  final reader = _HeaderReader(read, maxBytes: maxBytes);
  if (ascii.decode(await reader.bytes(4), allowInvalid: true) != 'GGUF') {
    throw const FormatException('Not a GGUF file.');
  }
  await reader.u32();
  await reader.u64();
  final metadata = <String, Object?>{};
  await _readGgufKeys(reader, metadata, (key, _) => key == stopAt);
  return metadata;
}

/// Reads key/value pairs into [metadata] until [stop] holds for one or the
/// block ends; returns whether [stop] ended it.
Future<bool> _readGgufKeys(
  _HeaderReader reader,
  Map<String, Object?> metadata,
  bool Function(String key, Object? value) stop,
) async {
  final keyCount = _checkedCount(await reader.u64(), maxImageModelGgufKeys);
  for (var i = 0; i < keyCount; i++) {
    final key = await reader.string();
    final value = await _ggufValue(reader, await reader.u32());
    if (value != null) {
      metadata[key] = value;
    }
    if (stop(key, value)) {
      return true;
    }
  }
  return false;
}

Future<ImageModelFileHeader> _readGguf(
  _HeaderReader reader,
  bool stopAtLanguageModelArchitecture,
) async {
  await reader.u32();
  final tensorCount = _checkedCount(
    await reader.u64(),
    maxImageModelGgufTensors,
  );
  final metadata = <String, Object?>{};
  if (await _readGgufKeys(
    reader,
    metadata,
    (key, value) =>
        stopAtLanguageModelArchitecture &&
        key == 'general.architecture' &&
        imageModelLanguageModelArchitectures.contains(value),
  )) {
    return ImageModelFileHeader(
      isGguf: true,
      metadata: metadata,
      tensors: const [],
      stoppedAtArchitecture: true,
    );
  }
  final tensors = <ImageModelTensor>[];
  for (var i = 0; i < tensorCount; i++) {
    final name = await reader.string();
    final dims = await reader.u32();
    if (dims > 8) {
      throw const FormatException('Malformed GGUF tensor info.');
    }
    final shape = <int>[for (var d = 0; d < dims; d++) await reader.u64()];
    final type = await reader.u32();
    await reader.u64();
    tensors.add(ImageModelTensor(name, shape, ggufType: type));
  }
  return ImageModelFileHeader(
    isGguf: true,
    metadata: metadata,
    tensors: tensors,
  );
}

int _checkedCount(int count, int max) {
  if (count < 0 || count > max) {
    throw const FormatException('Implausible GGUF header count.');
  }
  return count;
}

/// Reads one GGUF value of [type]; arrays are skipped and return `null`.
Future<Object?> _ggufValue(_HeaderReader reader, int type) async {
  if (type == 8) {
    return reader.string();
  }
  if (type == 9) {
    final itemType = await reader.u32();
    final count = _checkedCount(
      await reader.u64(),
      maxImageModelGgufArrayItems,
    );
    if (itemType == 8) {
      for (var i = 0; i < count; i++) {
        await reader.skip(_checkedStringLength(await reader.u64()));
      }
    } else {
      final size =
          _ggufScalarBytes[itemType] ??
          (throw const FormatException('Malformed GGUF array.'));
      await reader.skip(size * count);
    }
    return null;
  }
  final size =
      _ggufScalarBytes[type] ??
      (throw const FormatException('Malformed GGUF value.'));
  final data = ByteData.sublistView(await reader.bytes(size));
  return switch (type) {
    0 => data.getUint8(0),
    1 => data.getInt8(0),
    2 => data.getUint16(0, Endian.little),
    3 => data.getInt16(0, Endian.little),
    4 => data.getUint32(0, Endian.little),
    5 => data.getInt32(0, Endian.little),
    6 => data.getFloat32(0, Endian.little),
    7 => data.getUint8(0) != 0,
    10 => _uint64(data),
    11 => _uint64(data),
    _ => data.getFloat64(0, Endian.little),
  };
}

/// The little-endian 64-bit value at the start of [data], read as two
/// 32-bit halves because dart2js has no 64-bit accessors.
int _uint64(ByteData data) =>
    data.getUint32(4, Endian.little) * 0x100000000 +
    data.getUint32(0, Endian.little);

int _checkedStringLength(int length) {
  if (length < 0 || length > maxImageModelGgufStringBytes) {
    throw const FormatException('Implausible GGUF string length.');
  }
  return length;
}

/// Sequential reader that fetches in growing blocks.
class _HeaderReader {
  _HeaderReader(this._read, {this.maxBytes = maxImageModelHeaderBytes});

  final ImageModelFileReader _read;
  final int maxBytes;
  int _blockSize = 64 * 1024;
  Uint8List _buffer = Uint8List(0);
  int _bufferStart = 0;
  int position = 0;

  Future<Uint8List> bytes(int count) async {
    _checkBudget(count);
    final start = position - _bufferStart;
    if (start < 0 || start + count > _buffer.length) {
      final fetchLength = count > _blockSize ? count : _blockSize;
      _buffer = await _read(position, fetchLength);
      _bufferStart = position;
      if (_blockSize < (16 << 20)) {
        _blockSize *= 2;
      }
      if (_buffer.length < count) {
        throw const FormatException('Truncated model file header.');
      }
    }
    final offset = position - _bufferStart;
    position += count;
    return Uint8List.sublistView(_buffer, offset, offset + count);
  }

  Future<void> skip(int count) async {
    if (count < 0) {
      throw const FormatException('Malformed model file header.');
    }
    _checkBudget(count);
    position += count;
  }

  void _checkBudget(int count) {
    if (position + count > maxBytes) {
      throw const FormatException('Model file header is too large.');
    }
  }

  Future<int> u32() async =>
      ByteData.sublistView(await bytes(4)).getUint32(0, Endian.little);

  Future<int> u64() async => _uint64(ByteData.sublistView(await bytes(8)));

  Future<String> string() async => utf8.decode(
    await bytes(_checkedStringLength(await u64())),
    allowMalformed: true,
  );
}

/// What a file's header shows it is.
enum ImageModelFileKind {
  /// A file stable-diffusion.cpp loads in one of the [ImageModelRole]s.
  component,

  /// A LoRA adapter.
  lora,

  /// An image upscaler.
  upscaler,

  /// A vision encoder or multimodal projector, used only for image editing.
  visionEncoder,

  /// A decoder-only tiny autoencoder export, which the runtime rejects.
  decoderOnlyTaesd,

  /// No known image-model layout.
  unknown,
}

/// The outcome of classifying one file header.
class ImageModelFileClassification {
  /// What the file is.
  final ImageModelFileKind kind;

  /// Role the file loads in, when [kind] is
  /// [ImageModelFileKind.component].
  final ImageModelRole? role;

  /// Latent channels the file's diffusion weights produce or its decoder
  /// takes, when the header shows them.
  final int? latentChannels;

  /// The header signals the classification rests on, for error messages.
  final String signals;

  /// Whether a checkpoint's embedded decoder is a tiny autoencoder, as in
  /// SDXS.
  final bool embedsTinyAutoencoder;

  /// Width of the text context the first cross-attention block of a UNet
  /// checkpoint or original-layout ControlNet takes: 768 for SD 1.x, 1024
  /// for SD 2.x. `null` when the header does not show it.
  final int? crossAttentionWidth;

  /// Input channels of an original-layout ControlNet's hint block; `null`
  /// for other files and layouts.
  final int? controlHintChannels;

  /// Whether separate diffusion weights have the FLUX.1 [dev] and Kontext
  /// transformer layout: double blocks, a guidance embedder and 64-wide
  /// patch input (16 latent channels in 2x2 patches, no inpainting or
  /// control channels).
  final bool fluxGuidanceTransformer;

  /// Creates a classification.
  const ImageModelFileClassification(
    this.kind,
    this.signals, {
    this.role,
    this.latentChannels,
    this.embedsTinyAutoencoder = false,
    this.crossAttentionWidth,
    this.controlHintChannels,
    this.fluxGuidanceTransformer = false,
  });

  const ImageModelFileClassification._role(
    ImageModelRole this.role,
    this.signals, {
    this.latentChannels,
    this.embedsTinyAutoencoder = false,
    this.crossAttentionWidth,
    this.controlHintChannels,
    this.fluxGuidanceTransformer = false,
  }) : kind = ImageModelFileKind.component;
}

const List<String> _checkpointPrefixes = <String>[
  'model.diffusion_model.',
  'first_stage_model.',
  'cond_stage_model.',
  'conditioner.embedders.',
  'text_encoders.',
];

final RegExp _loraName = RegExp(
  r'(lora_(up|down|A|B)\b|\.lora\.(up|down)|lora_unet_|lora_te|hada_w1|lokr_w)',
);

/// Classifies a file from its [header] alone.
ImageModelFileClassification classifyImageModelFile(
  ImageModelFileHeader header,
) {
  final architecture = header.architecture;
  if (header.stoppedAtArchitecture) {
    return ImageModelFileClassification._role(
      ImageModelRole.llm,
      'GGUF architecture $architecture',
    );
  }
  final tensors = header.tensors;
  final byName = <String, ImageModelTensor>{
    for (final tensor in tensors) tensor.name: tensor,
  };
  bool anyName(bool Function(String name) test) =>
      tensors.any((tensor) => test(tensor.name));
  bool hasPrefix(String prefix) => anyName((name) => name.startsWith(prefix));

  if (anyName(_loraName.hasMatch)) {
    return const ImageModelFileClassification(
      ImageModelFileKind.lora,
      'LoRA tensor names',
    );
  }
  if (hasPrefix('control_model.') ||
      anyName(
        (name) =>
            name.contains('input_hint_block') || name.startsWith('controlnet_'),
      )) {
    // stable-diffusion.cpp strips `control_model.` and loads SD 1.x
    // ControlNets only in this layout; it converts Diffusers names for SDXL.
    final prefix = hasPrefix('control_model.') ? 'control_model.' : '';
    final hint = byName['${prefix}input_hint_block.0.weight'];
    final original =
        hint != null &&
        byName.containsKey('${prefix}zero_convs.0.0.weight') &&
        byName.containsKey('${prefix}middle_block_out.0.weight');
    return ImageModelFileClassification._role(
      ImageModelRole.controlNet,
      'ControlNet tensor names',
      crossAttentionWidth: original
          ? _crossAttentionWidth(byName, header.isGguf, prefix)
          : null,
      controlHintChannels: original
          ? _convInputChannels(hint, header.isGguf)
          : null,
    );
  }

  final prefixed = tensors
      .where((tensor) => _checkpointPrefixes.any(tensor.name.startsWith))
      .length;
  if (tensors.isNotEmpty && prefixed > tensors.length * 0.9) {
    if (!hasPrefix('model.diffusion_model.')) {
      return const ImageModelFileClassification(
        ImageModelFileKind.unknown,
        'checkpoint names without diffusion weights',
      );
    }
    return ImageModelFileClassification._role(
      ImageModelRole.checkpoint,
      'checkpoint tensor names',
      latentChannels: _diffusionLatentChannels(
        byName,
        header.isGguf,
        'model.diffusion_model.',
      ),
      embedsTinyAutoencoder: hasPrefix('first_stage_model.decoder.layers.'),
      crossAttentionWidth: _crossAttentionWidth(
        byName,
        header.isGguf,
        'model.diffusion_model.',
      ),
    );
  }

  if (header.isGguf && architecture == 'clip') {
    return const ImageModelFileClassification(
      ImageModelFileKind.visionEncoder,
      'GGUF architecture clip',
    );
  }
  if (architecture == 't5' ||
      architecture == 't5encoder' ||
      hasPrefix('enc.blk.') ||
      hasPrefix('encoder.block.') ||
      (hasPrefix('shared.') && hasPrefix('encoder.'))) {
    return const ImageModelFileClassification._role(
      ImageModelRole.t5xxl,
      'T5 encoder tensor names',
    );
  }
  if ((architecture != null &&
          imageModelLanguageModelArchitectures.contains(architecture)) ||
      (hasPrefix('blk.') && hasPrefix('token_embd.')) ||
      (hasPrefix('model.layers.') &&
          anyName((name) => name.contains('self_attn.q_proj')))) {
    return const ImageModelFileClassification._role(
      ImageModelRole.llm,
      'language-model tensor names',
    );
  }
  if (hasPrefix('visual.blocks.') ||
      hasPrefix('v.blk.') ||
      hasPrefix('vision_model.')) {
    return const ImageModelFileClassification(
      ImageModelFileKind.visionEncoder,
      'vision encoder tensor names',
    );
  }

  final tokenEmbedding =
      byName['text_model.embeddings.token_embedding.weight'] ??
      byName['transformer.text_model.embeddings.token_embedding.weight'] ??
      byName['token_embedding.weight'] ??
      byName['model.token_embedding.weight'];
  if (tokenEmbedding != null && tokenEmbedding.shape.isNotEmpty) {
    final width = tokenEmbedding.shape.reduce((a, b) => a < b ? a : b);
    return ImageModelFileClassification._role(
      width >= 1280 ? ImageModelRole.clipG : ImageModelRole.clipL,
      'CLIP text encoder of width $width',
    );
  }

  if (hasPrefix('decoder.layers.') || hasPrefix('encoder.layers.')) {
    return ImageModelFileClassification._role(
      ImageModelRole.taesd,
      'tiny autoencoder tensor names',
      latentChannels: _convInputChannels(
        byName['decoder.layers.0.weight'],
        header.isGguf,
      ),
    );
  }
  if (tensors.isNotEmpty &&
      tensors.length < 100 &&
      anyName(RegExp(r'^\d+\.(conv\.)?\d*\.?(weight|bias)$').hasMatch)) {
    return const ImageModelFileClassification(
      ImageModelFileKind.decoderOnlyTaesd,
      'decoder-only tiny autoencoder names',
    );
  }
  if (hasPrefix('decoder.') &&
      (hasPrefix('encoder.') ||
          hasPrefix('post_quant_conv') ||
          hasPrefix('decoder.conv_in'))) {
    return ImageModelFileClassification._role(
      ImageModelRole.vae,
      'VAE tensor names',
      latentChannels: _convInputChannels(
        byName['decoder.conv_in.weight'],
        header.isGguf,
      ),
    );
  }

  const diffusionPrefixes = <String>[
    'input_blocks.',
    'down_blocks.',
    'joint_blocks.',
    'double_blocks.',
    'single_transformer_blocks.',
    'cap_embedder.',
    'transformer_blocks.',
    'blocks.',
    'layers.',
  ];
  if (diffusionPrefixes.any(hasPrefix)) {
    final patchInput = byName['img_in.weight'];
    return ImageModelFileClassification._role(
      ImageModelRole.diffusionModel,
      'diffusion tensor names',
      latentChannels: _diffusionLatentChannels(byName, header.isGguf, ''),
      fluxGuidanceTransformer:
          hasPrefix('double_blocks.') &&
          byName.containsKey('guidance_in.in_layer.weight') &&
          patchInput != null &&
          patchInput.shape.length == 2 &&
          (header.isGguf ? patchInput.shape[0] : patchInput.shape[1]) == 64,
    );
  }
  if (hasPrefix('conv_first') ||
      anyName((name) => name.contains('RRDB')) ||
      hasPrefix('model.0.')) {
    return const ImageModelFileClassification(
      ImageModelFileKind.upscaler,
      'upscaler tensor names',
    );
  }
  return const ImageModelFileClassification(
    ImageModelFileKind.unknown,
    'no known image-model tensor names',
  );
}

/// Input channels of a convolution weight: torch stores `[out, in, h, w]`,
/// GGUF the reverse.
int? _convInputChannels(ImageModelTensor? weight, bool isGguf) {
  if (weight == null || weight.shape.length != 4) {
    return null;
  }
  return isGguf ? weight.shape[2] : weight.shape[1];
}

/// Input width of the cross-attention key in the first attention block of a
/// UNet whose names start with [prefix]: torch stores `[out, in]`, GGUF the
/// reverse.
int? _crossAttentionWidth(
  Map<String, ImageModelTensor> byName,
  bool isGguf,
  String prefix,
) {
  final key =
      byName['${prefix}input_blocks.1.1.transformer_blocks.0.attn2.to_k.weight'];
  if (key == null || key.shape.length != 2) {
    return null;
  }
  return isGguf ? key.shape[0] : key.shape[1];
}

/// Latent channels of diffusion weights whose names start with [prefix].
///
/// A UNet's output convolution gives them exactly; its input can take more
/// (9 for inpainting checkpoints). Transformers that unpatchify 2x2 patches
/// (SD 3.5, FLUX, Z-Image, Qwen-Image) output 4 values per latent channel;
/// that guess counts only when it gives a family's 4 or 16 channels.
int? _diffusionLatentChannels(
  Map<String, ImageModelTensor> byName,
  bool isGguf,
  String prefix,
) {
  final unetOutput =
      byName['${prefix}out.2.weight'] ?? byName['${prefix}conv_out.weight'];
  if (unetOutput != null && unetOutput.shape.length == 4) {
    return isGguf ? unetOutput.shape[3] : unetOutput.shape[0];
  }
  final patches = switch (byName['${prefix}final_layer.linear.bias']?.shape) {
    [final width] when width % 4 == 0 => width ~/ 4,
    _ => null,
  };
  return patches == 4 || patches == 16 ? patches : null;
}

/// One file to assign: its explicit role, if any, and a reader of its local
/// copy.
class ImageModelFileInput {
  /// Role the caller gave, or `null` to detect it.
  final ImageModelRole? role;

  /// Reads the file's bytes.
  final ImageModelFileReader read;

  /// Creates an input.
  const ImageModelFileInput({required this.read, this.role});
}

/// How errors name the file at [index]: the main file, then components
/// counted from 1.
String describeImageModelFile(int index) =>
    index == 0 ? 'the main file' : 'component $index';

/// The roles [assignImageModelRoles] gave a set of files.
class ImageModelAssignment {
  /// Index of the file in each role.
  final Map<ImageModelRole, int> roles;

  /// Whether a tiny autoencoder decodes: a [ImageModelRole.taesd] file, or a
  /// checkpoint whose header shows an embedded one.
  final bool decodesWithTinyAutoencoder;

  /// Header proof of a four-channel embedded full VAE or TAESD decoder.
  final bool vaeTilingDecoderVerified;

  /// Header proof of exactly an SD 1.x checkpoint with its embedded full VAE
  /// and an original-layout SD 1.x ControlNet with a three-channel hint.
  final bool controlNetRecipeVerified;

  /// Header proof of exactly a 16-channel FLUX guidance transformer, the
  /// 16-channel FLUX autoencoder, CLIP-L and T5-XXL: the file set FLUX.1
  /// Kontext [dev] loads with.
  final bool fluxKontextRecipeVerified;

  /// Creates an assignment.
  const ImageModelAssignment(
    this.roles, {
    required this.decodesWithTinyAutoencoder,
    this.vaeTilingDecoderVerified = false,
    this.controlNetRecipeVerified = false,
    this.fluxKontextRecipeVerified = false,
  });
}

/// Assigns each of [files] its runtime role, from its header unless the
/// caller set one.
///
/// Throws [LlamaModelException] for a file that is not an image-model
/// component (a LoRA, upscaler, vision encoder, decoder-only
/// TAESD or unknown layout), for two files in one role, for a set without
/// diffusion weights or with both a checkpoint and separate diffusion
/// weights, and for a VAE or TAESD whose latent channels differ from the
/// diffusion model's. Errors name files by position and role, not path.
Future<ImageModelAssignment> assignImageModelRoles(
  List<ImageModelFileInput> files,
) async {
  final roles = <ImageModelRole, int>{};
  final latents = <ImageModelRole, int>{};
  final contextWidths = <ImageModelRole, int>{};
  int? controlHintChannels;
  var fluxGuidanceTransformer = false;
  var embeddedTinyAutoencoder = false;
  var embeddedFullVae = false;
  for (final (index, file) in files.indexed) {
    final name = describeImageModelFile(index);
    final explicit = file.role;
    ImageModelFileClassification? classification;
    try {
      final header = await readImageModelFileHeader(file.read);
      classification = classifyImageModelFile(header);
      if (classification.role == ImageModelRole.checkpoint &&
          (explicit == null || explicit == ImageModelRole.checkpoint)) {
        embeddedFullVae = header.tensors.any(
          (tensor) => tensor.name == 'first_stage_model.decoder.conv_in.weight',
        );
      }
    } on FormatException {
      if (explicit == null) {
        throw LlamaModelException(
          'Cannot detect the role of $name: it is not a GGUF or safetensors '
          'file. Pass it as ImageModelComponent(source, role: ...).',
        );
      }
    } on LlamaException {
      rethrow;
    } catch (_) {
      // The read error can name the file's path; keep it out of the message.
      throw LlamaModelException('Cannot read the header of $name.');
    }
    final role = explicit ?? _detectedRole(classification!, name);
    final previous = roles[role];
    if (previous != null) {
      throw LlamaModelException(
        '${_capitalized(describeImageModelFile(previous))} and $name are '
        'both ${role.name} files; pass one file per role.',
      );
    }
    roles[role] = index;
    final channels = classification?.role == role
        ? classification!.latentChannels
        : null;
    if (channels != null) {
      latents[role] = channels;
    }
    if (classification?.role == role) {
      if (classification!.crossAttentionWidth case final width?) {
        contextWidths[role] = width;
      }
      if (role == ImageModelRole.controlNet) {
        controlHintChannels = classification.controlHintChannels;
      }
      fluxGuidanceTransformer |= classification.fluxGuidanceTransformer;
    }
    if (role == ImageModelRole.checkpoint &&
        (classification?.embedsTinyAutoencoder ?? false)) {
      embeddedTinyAutoencoder = true;
    }
  }
  if (roles.containsKey(ImageModelRole.checkpoint) &&
      roles.containsKey(ImageModelRole.diffusionModel)) {
    throw LlamaModelException(
      'The image model files include both a checkpoint '
      '(${describeImageModelFile(roles[ImageModelRole.checkpoint]!)}) and '
      'separate diffusion weights '
      '(${describeImageModelFile(roles[ImageModelRole.diffusionModel]!)}).',
    );
  }
  final diffusion = roles.containsKey(ImageModelRole.checkpoint)
      ? ImageModelRole.checkpoint
      : roles.containsKey(ImageModelRole.diffusionModel)
      ? ImageModelRole.diffusionModel
      : null;
  if (diffusion == null) {
    throw LlamaModelException(
      'None of the image model files holds diffusion weights: pass a '
      'checkpoint or diffusion model.',
    );
  }
  final diffusionChannels = latents[diffusion];
  if (diffusionChannels != null) {
    for (final decoder in const [ImageModelRole.vae, ImageModelRole.taesd]) {
      final channels = latents[decoder];
      if (channels != null && channels != diffusionChannels) {
        throw LlamaModelException(
          'The ${decoder.name} file '
          '(${describeImageModelFile(roles[decoder]!)}) decodes '
          '$channels-channel latents, but the diffusion weights '
          '(${describeImageModelFile(roles[diffusion]!)}) produce '
          '$diffusionChannels-channel latents. Use the decoder made for this '
          'model family.',
        );
      }
    }
  }
  return ImageModelAssignment(
    roles,
    vaeTilingDecoderVerified:
        latents[ImageModelRole.checkpoint] == 4 &&
        (roles.containsKey(ImageModelRole.taesd)
            ? latents[ImageModelRole.taesd] == 4
            : embeddedFullVae),
    decodesWithTinyAutoencoder:
        roles.containsKey(ImageModelRole.taesd) || embeddedTinyAutoencoder,
    controlNetRecipeVerified:
        roles.length == 2 &&
        roles.containsKey(ImageModelRole.checkpoint) &&
        roles.containsKey(ImageModelRole.controlNet) &&
        latents[ImageModelRole.checkpoint] == 4 &&
        embeddedFullVae &&
        !embeddedTinyAutoencoder &&
        contextWidths[ImageModelRole.checkpoint] == 768 &&
        contextWidths[ImageModelRole.controlNet] == 768 &&
        controlHintChannels == 3,
    fluxKontextRecipeVerified:
        roles.length == 4 &&
        roles.containsKey(ImageModelRole.clipL) &&
        roles.containsKey(ImageModelRole.t5xxl) &&
        fluxGuidanceTransformer &&
        latents[ImageModelRole.diffusionModel] == 16 &&
        latents[ImageModelRole.vae] == 16,
  );
}

ImageModelRole _detectedRole(
  ImageModelFileClassification classification,
  String name,
) {
  final role = classification.role;
  if (role != null) {
    return role;
  }
  final what = switch (classification.kind) {
    ImageModelFileKind.lora =>
      'a LoRA adapter, which image generation does '
          'not load yet',
    ImageModelFileKind.upscaler =>
      'an upscaler, which image generation does '
          'not load',
    ImageModelFileKind.visionEncoder =>
      'a vision encoder or projector, used '
          'only for image editing, which image generation does not support',
    ImageModelFileKind.decoderOnlyTaesd =>
      'a decoder-only tiny autoencoder, '
          'which the runtime rejects; use the full TAESD file '
          '(diffusion_pytorch_model.safetensors)',
    ImageModelFileKind.component || ImageModelFileKind.unknown =>
      'not a known image-model file (${classification.signals}). If it is '
          'one, pass it as ImageModelComponent(source, role: ...)',
  };
  throw LlamaModelException('${_capitalized(name)} is $what.');
}

String _capitalized(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
