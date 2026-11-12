import 'dart:convert';
import 'dart:typed_data';

/// A tensor in a header-only fixture: its name and stored shape (GGUF lists
/// the innermost dimension first, safetensors the outermost).
typedef FixtureTensor = (String name, List<int> shape);

/// The header of a GGUF file holding [metadata] (string, int, bool,
/// `List<String>`, [GgufU64] or [GgufArray] values) and [tensors], without
/// tensor data.
Uint8List ggufHeader({
  Map<String, Object> metadata = const {},
  List<FixtureTensor> tensors = const [],
  int tensorType = 0,
}) {
  final out = BytesBuilder();
  void u32(int value) => out.add(
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List(),
  );
  void u64(int value) => out.add(_uint64Bytes(value));
  void string(String value) {
    final bytes = utf8.encode(value);
    u64(bytes.length);
    out.add(bytes);
  }

  out.add(ascii.encode('GGUF'));
  u32(3);
  u64(tensors.length);
  u64(metadata.length);
  for (final MapEntry(:key, :value) in metadata.entries) {
    string(key);
    switch (value) {
      case String():
        u32(8);
        string(value);
      case bool():
        u32(7);
        out.addByte(value ? 1 : 0);
      case int():
        u32(4);
        u32(value);
      case List<String>():
        u32(9);
        u32(8);
        u64(value.length);
        value.forEach(string);
      case GgufU64(:final value):
        u32(10);
        u64(value);
      case GgufArray(:final itemType, :final count, :final itemBytes):
        u32(9);
        u32(itemType);
        u64(count);
        out.add(Uint8List(itemBytes));
      default:
        throw ArgumentError.value(value, key);
    }
  }
  for (final (name, shape) in tensors) {
    string(name);
    u32(shape.length);
    shape.forEach(u64);
    u32(tensorType);
    u64(0);
  }
  return out.takeBytes();
}

/// A GGUF `uint64` metadata value.
final class GgufU64 {
  /// Creates a value.
  const GgufU64(this.value);

  /// The value.
  final int value;
}

/// A GGUF array of [count] items of scalar [itemType], declared with only
/// [itemBytes] bytes of data after it.
final class GgufArray {
  /// Creates an array declaration.
  const GgufArray(this.itemType, this.count, {this.itemBytes = 0});

  /// GGUF value type of the items, such as 0 for `uint8`.
  final int itemType;

  /// Declared item count.
  final int count;

  /// Bytes of item data actually written.
  final int itemBytes;
}

/// The header of a safetensors file holding [tensors], followed by
/// [dataBytes] zero bytes of tensor data.
Uint8List safetensorsHeader(
  List<FixtureTensor> tensors, {
  Map<String, String>? metadata,
  int dataBytes = 0,
  String dtype = 'F16',
}) {
  final header = utf8.encode(
    jsonEncode(<String, Object?>{
      '__metadata__': ?metadata,
      for (final (name, shape) in tensors)
        name: {
          'dtype': dtype,
          'shape': shape,
          'data_offsets': [0, 0],
        },
    }),
  );
  return Uint8List.fromList([
    ..._uint64Bytes(header.length),
    ...header,
    ...Uint8List(dataBytes),
  ]);
}

/// [value] as 8 little-endian bytes, written as two 32-bit halves because
/// dart2js has no 64-bit accessors.
Uint8List _uint64Bytes(int value) =>
    (ByteData(8)
          ..setUint32(0, value % 0x100000000, Endian.little)
          ..setUint32(4, value ~/ 0x100000000, Endian.little))
        .buffer
        .asUint8List();

/// Header-only fixtures named after the files their tensor names and shapes
/// come from.
abstract final class ImageModelHeaders {
  /// SDXS-512 GGUF: a checkpoint whose embedded decoder is a tiny
  /// autoencoder.
  static final Uint8List sdxsCheckpoint = ggufHeader(
    tensors: [
      ('model.diffusion_model.input_blocks.0.0.weight', [3, 3, 4, 320]),
      ('model.diffusion_model.out.2.weight', [3, 3, 320, 4]),
      ('first_stage_model.decoder.layers.0.weight', [3, 3, 4, 64]),
      (
        'cond_stage_model.transformer.text_model.final_layer_norm.weight',
        [768],
      ),
    ],
  );

  /// SD-Turbo GGUF: a checkpoint with a full VAE.
  static final Uint8List sdTurboCheckpoint = ggufHeader(
    tensors: [
      ('model.diffusion_model.input_blocks.0.0.weight', [3, 3, 4, 320]),
      ('model.diffusion_model.out.2.weight', [3, 3, 320, 4]),
      ('first_stage_model.decoder.conv_in.weight', [3, 3, 4, 512]),
      ('first_stage_model.quant_conv.weight', [1, 1, 8, 8]),
      ('cond_stage_model.model.token_embedding.weight', [1024, 49408]),
    ],
  );

  /// SDXL-Lightning safetensors checkpoint.
  static final Uint8List sdxlCheckpoint = safetensorsHeader([
    ('model.diffusion_model.input_blocks.0.0.weight', [320, 4, 3, 3]),
    ('model.diffusion_model.out.2.weight', [4, 320, 3, 3]),
    ('first_stage_model.decoder.conv_in.weight', [512, 4, 3, 3]),
    (
      'conditioner.embedders.0.transformer.text_model.final_layer_norm.weight',
      [768],
    ),
  ]);

  /// An SD 1.x inpainting checkpoint: its UNet takes 9 input channels
  /// (latents, masked image and mask) and outputs 4 latent channels.
  static final Uint8List inpaintingCheckpoint = safetensorsHeader([
    ('model.diffusion_model.input_blocks.0.0.weight', [320, 9, 3, 3]),
    ('model.diffusion_model.out.2.weight', [4, 320, 3, 3]),
    ('first_stage_model.decoder.conv_in.weight', [512, 4, 3, 3]),
    ('cond_stage_model.transformer.text_model.final_layer_norm.weight', [768]),
  ]);

  /// A diffusion transformer whose final layer outputs 128 values per
  /// patch, which the 2x2-patch channel guess does not cover.
  static final Uint8List wideTransformer = ggufHeader(
    tensors: [
      ('double_blocks.0.img_attn.qkv.weight', [3072, 9216]),
      ('final_layer.linear.bias', [128]),
    ],
  );

  /// SD 3.5 Large Turbo GGUF diffusion transformer (16 latent channels).
  static final Uint8List sd35Diffusion = ggufHeader(
    tensors: [
      ('joint_blocks.0.context_block.attn.qkv.weight', [2432, 7296]),
      ('x_embedder.proj.weight', [2, 2, 16, 2432]),
      ('final_layer.linear.bias', [64]),
    ],
  );

  /// FLUX.1-schnell GGUF diffusion transformer (16 latent channels).
  static final Uint8List fluxDiffusion = ggufHeader(
    tensors: [
      ('double_blocks.0.img_attn.qkv.weight', [3072, 9216]),
      ('img_in.weight', [64, 3072]),
      ('final_layer.linear.bias', [64]),
    ],
  );

  /// FLUX.1-Kontext-dev GGUF diffusion transformer: the FLUX.1-schnell
  /// layout plus a guidance embedder.
  static final Uint8List fluxKontextDiffusion = ggufHeader(
    tensors: [
      ('double_blocks.0.img_attn.qkv.weight', [3072, 9216]),
      ('guidance_in.in_layer.weight', [256, 3072]),
      ('img_in.weight', [64, 3072]),
      ('final_layer.linear.bias', [64]),
    ],
  );

  /// FLUX.1-Fill-dev GGUF diffusion transformer: a guidance embedder and
  /// 384-wide patch input for the masked image and mask.
  static final Uint8List fluxFillDiffusion = ggufHeader(
    tensors: [
      ('double_blocks.0.img_attn.qkv.weight', [3072, 9216]),
      ('guidance_in.in_layer.weight', [256, 3072]),
      ('img_in.weight', [384, 3072]),
      ('final_layer.linear.bias', [64]),
    ],
  );

  /// Z-Image-Turbo GGUF diffusion transformer (16 latent channels).
  static final Uint8List zImageDiffusion = ggufHeader(
    tensors: [
      ('cap_embedder.1.weight', [2560, 3840]),
      ('layers.0.attention.qkv.weight', [3840, 11520]),
      ('final_layer.linear.bias', [64]),
    ],
  );

  /// FLUX `ae.safetensors` (16 latent channels).
  static final Uint8List fluxVae = safetensorsHeader([
    ('decoder.conv_in.weight', [512, 16, 3, 3]),
    ('encoder.conv_in.weight', [128, 3, 3, 3]),
  ]);

  /// SDXL VAE (4 latent channels).
  static final Uint8List sdxlVae = safetensorsHeader([
    ('decoder.conv_in.weight', [512, 4, 3, 3]),
    ('encoder.conv_in.weight', [128, 3, 3, 3]),
    ('post_quant_conv.weight', [4, 4, 1, 1]),
  ]);

  /// TAESD and TAESDXL (4 latent channels).
  static final Uint8List taesd = safetensorsHeader([
    ('decoder.layers.0.weight', [64, 4, 3, 3]),
    ('encoder.layers.0.weight', [64, 3, 3, 3]),
  ]);

  /// TAEF1 and TAESD3 (16 latent channels).
  static final Uint8List taef1 = safetensorsHeader([
    ('decoder.layers.0.weight', [64, 16, 3, 3]),
    ('encoder.layers.0.weight', [64, 3, 3, 3]),
  ]);

  /// `taesd_decoder.safetensors`: a decoder-only export.
  static final Uint8List decoderOnlyTaesd = safetensorsHeader([
    ('1.weight', [64, 4, 3, 3]),
    ('3.conv.0.weight', [64, 64, 3, 3]),
  ]);

  /// CLIP-L GGUF text encoder.
  static final Uint8List clipL = ggufHeader(
    tensors: [
      ('text_model.embeddings.token_embedding.weight', [768, 49408]),
    ],
  );

  /// CLIP-G GGUF text encoder.
  static final Uint8List clipG = ggufHeader(
    tensors: [
      ('text_model.embeddings.token_embedding.weight', [1280, 49408]),
    ],
  );

  /// T5-XXL GGUF encoder.
  static final Uint8List t5xxl = ggufHeader(
    tensors: [
      ('encoder.block.0.layer.0.SelfAttention.q.weight', [4096, 4096]),
      ('shared.weight', [4096, 32128]),
    ],
  );

  /// Qwen3 GGUF: `general.architecture` comes before a large tokenizer.
  static final Uint8List qwen3Llm = ggufHeader(
    metadata: {
      'general.architecture': 'qwen3',
      'tokenizer.ggml.tokens': List<String>.filled(50000, 'token'),
    },
    tensors: [
      ('token_embd.weight', [2560, 151936]),
      ('blk.0.attn_q.weight', [2560, 4096]),
    ],
  );

  /// A LoRA adapter for an SDXL UNet.
  static final Uint8List lora = safetensorsHeader([
    ('lora_unet_down_blocks_0_attentions_0_proj_in.lora_down.weight', [4, 320]),
    ('lora_unet_down_blocks_0_attentions_0_proj_in.lora_up.weight', [320, 4]),
  ]);

  /// A ControlNet.
  static final Uint8List controlNet = safetensorsHeader([
    ('control_model.input_hint_block.0.weight', [16, 3, 3, 3]),
    ('control_model.input_blocks.0.0.weight', [320, 4, 3, 3]),
  ]);

  /// An SD 1.x safetensors checkpoint with its full VAE. The cross-attention
  /// key of its first attention block takes a [contextWidth]-wide text
  /// context: 768 for SD 1.x, 1024 for SD 2.x.
  static Uint8List sd15Checkpoint({int contextWidth = 768}) =>
      safetensorsHeader([
        ('model.diffusion_model.input_blocks.0.0.weight', [320, 4, 3, 3]),
        (
          'model.diffusion_model.input_blocks.1.1.transformer_blocks.0.attn2.'
              'to_k.weight',
          [320, contextWidth],
        ),
        ('model.diffusion_model.out.2.weight', [4, 320, 3, 3]),
        ('first_stage_model.decoder.conv_in.weight', [512, 4, 3, 3]),
        (
          'cond_stage_model.transformer.text_model.final_layer_norm.weight',
          [768],
        ),
      ]);

  /// An SD 1.x ControlNet in the original (lllyasviel) layout, as in
  /// `control_v11p_sd15_canny`, with names under [prefix]; shapes follow
  /// stable-diffusion.cpp's `ControlNetBlock` for SD 1.x.
  static Uint8List sd15ControlNet({
    String prefix = 'control_model.',
    int contextWidth = 768,
    int hintChannels = 3,
    bool gguf = false,
  }) {
    final tensors = <FixtureTensor>[
      ('${prefix}input_hint_block.0.weight', [16, hintChannels, 3, 3]),
      ('${prefix}input_blocks.0.0.weight', [320, 4, 3, 3]),
      (
        '${prefix}input_blocks.1.1.transformer_blocks.0.attn2.to_k.weight',
        [320, contextWidth],
      ),
      ('${prefix}zero_convs.0.0.weight', [320, 320, 1, 1]),
      ('${prefix}middle_block_out.0.weight', [1280, 1280, 1, 1]),
    ];
    return gguf
        ? ggufHeader(
            tensors: [
              for (final (name, shape) in tensors)
                (name, shape.reversed.toList()),
            ],
          )
        : safetensorsHeader(tensors);
  }

  /// An SD 1.x ControlNet in the Diffusers layout, which stable-diffusion.cpp
  /// converts only for SDXL.
  static final Uint8List diffusersControlNet = safetensorsHeader([
    ('controlnet_cond_embedding.conv_in.weight', [16, 3, 3, 3]),
    (
      'down_blocks.0.attentions.0.transformer_blocks.0.attn2.to_k.weight',
      [320, 768],
    ),
    ('controlnet_down_blocks.0.weight', [320, 320, 1, 1]),
    ('controlnet_mid_block.weight', [1280, 1280, 1, 1]),
  ]);

  /// An ESRGAN upscaler.
  static final Uint8List upscaler = safetensorsHeader([
    ('conv_first.weight', [64, 3, 3, 3]),
    ('body.0.rdb1.conv1.weight', [32, 64, 3, 3]),
  ]);

  /// A llama.cpp multimodal projector GGUF.
  static final Uint8List mmproj = ggufHeader(
    metadata: {'general.architecture': 'clip', 'clip.has_vision_encoder': true},
    tensors: [
      ('v.blk.0.attn_q.weight', [1024, 1024]),
    ],
  );

  /// A safetensors file with no image-model tensor names.
  static final Uint8List unknown = safetensorsHeader([
    ('head.dense.weight', [768, 768]),
    ('head.out_proj.weight', [2, 768]),
  ]);

  /// The first bytes of a pickled `.ckpt` file.
  static final Uint8List pickle = Uint8List.fromList([
    0x80,
    0x02,
    0x7d,
    0x71,
    0x00,
    ...List<int>.filled(64, 0x58),
  ]);
}
