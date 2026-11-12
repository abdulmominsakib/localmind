import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _embd = 16;
const _ff = 16;
const _alignment = 32;

/// Writes a one-layer ModernBERT GGUF with random F32 weights and a
/// byte-fallback SentencePiece vocabulary to [path].
///
/// llama.cpp creates no KV cache for this architecture. [poolingType] is the
/// raw `llama_pooling_type` value; [classifierLabels] adds a
/// `cls.output.weight` head with one output per label. [decisionTokens] sets
/// the SEP (`</s>`) and MASK (`<unk>`) tokens a decision head needs.
File writeSyntheticModernBertGguf(
  String path, {
  int? poolingType,
  List<String>? classifierLabels,
  String? rerankTemplate,
  bool decisionTokens = false,
  int contextLength = 1024,
  int seed = 0,
}) {
  const arch = 'modern-bert';
  final random = math.Random(seed);
  return _writeGguf(
    path,
    arch: arch,
    metadata: {
      '$arch.context_length': _GgufValue.uint32(contextLength),
      '$arch.embedding_length': _GgufValue.uint32(_embd),
      '$arch.feed_forward_length': _GgufValue.uint32(_ff),
      '$arch.block_count': _GgufValue.uint32(1),
      '$arch.attention.head_count': _GgufValue.uint32(2),
      '$arch.attention.layer_norm_epsilon': _GgufValue.float32(1e-5),
      '$arch.attention.causal': _GgufValue.boolean(false),
      if (poolingType != null)
        '$arch.pooling_type': _GgufValue.uint32(poolingType),
      if (classifierLabels != null)
        '$arch.classifier.output_labels': _GgufValue.strings(classifierLabels),
      if (rerankTemplate != null)
        'tokenizer.chat_template.rerank': _GgufValue.string(rerankTemplate),
      if (decisionTokens) ...{
        'tokenizer.ggml.seperator_token_id': _GgufValue.uint32(2),
        'tokenizer.ggml.mask_token_id': _GgufValue.uint32(0),
      },
    },
    tensors: {
      'token_embd.weight': _weights(random, [_embd, _tokens.length]),
      'token_embd_norm.weight': _ones([_embd]),
      'output_norm.weight': _ones([_embd]),
      'blk.0.attn_qkv.weight': _weights(random, [_embd, 3 * _embd]),
      'blk.0.attn_output.weight': _weights(random, [_embd, _embd]),
      'blk.0.ffn_up.weight': _weights(random, [_embd, 2 * _ff]),
      'blk.0.ffn_down.weight': _weights(random, [_ff, _embd]),
      'blk.0.ffn_norm.weight': _ones([_embd]),
      if (classifierLabels != null)
        'cls.output.weight': _weights(random, [_embd, classifierLabels.length]),
    },
  );
}

/// Writes a one-layer causal Llama GGUF with random F32 weights and a
/// byte-fallback SentencePiece vocabulary to [path].
///
/// llama.cpp creates a KV cache for this architecture. [poolingType] is the
/// raw `llama_pooling_type` value. [causalAttention] overrides the model's
/// default causal attention; null leaves the optional metadata key absent.
/// [eosTokenId] overrides the tokenizer default for special-token compatibility
/// tests. [architecture] also accepts `llada`, whose tensors share this layout and
/// whose runtime forces non-causal attention even with a true metadata value.
/// [uint32Metadata] adds keys the architecture loader ignores.
File writeSyntheticLlamaGguf(
  String path, {
  String architecture = 'llama',
  Map<String, int> uint32Metadata = const {},
  Map<String, String> stringMetadata = const {},
  int? eosTokenId,
  int? poolingType,
  bool? causalAttention,
  int contextLength = 1024,
  int seed = 0,
}) {
  final arch = architecture;
  final random = math.Random(seed);
  return _writeGguf(
    path,
    arch: arch,
    metadata: {
      if (eosTokenId != null)
        'tokenizer.ggml.eos_token_id': _GgufValue.uint32(eosTokenId),
      '$arch.context_length': _GgufValue.uint32(contextLength),
      '$arch.embedding_length': _GgufValue.uint32(_embd),
      '$arch.feed_forward_length': _GgufValue.uint32(_ff),
      '$arch.block_count': _GgufValue.uint32(1),
      '$arch.attention.head_count': _GgufValue.uint32(2),
      '$arch.attention.layer_norm_rms_epsilon': _GgufValue.float32(1e-5),
      if (causalAttention != null)
        '$arch.attention.causal': _GgufValue.boolean(causalAttention),
      if (poolingType != null)
        '$arch.pooling_type': _GgufValue.uint32(poolingType),
      for (final MapEntry(:key, :value) in uint32Metadata.entries)
        key: _GgufValue.uint32(value),
      for (final MapEntry(:key, :value) in stringMetadata.entries)
        key: _GgufValue.string(value),
    },
    tensors: {
      'token_embd.weight': _weights(random, [_embd, _tokens.length]),
      'output_norm.weight': _ones([_embd]),
      'blk.0.attn_norm.weight': _ones([_embd]),
      'blk.0.attn_q.weight': _weights(random, [_embd, _embd]),
      'blk.0.attn_k.weight': _weights(random, [_embd, _embd]),
      'blk.0.attn_v.weight': _weights(random, [_embd, _embd]),
      'blk.0.attn_output.weight': _weights(random, [_embd, _embd]),
      'blk.0.ffn_norm.weight': _ones([_embd]),
      'blk.0.ffn_gate.weight': _weights(random, [_embd, _ff]),
      'blk.0.ffn_up.weight': _weights(random, [_embd, _ff]),
      'blk.0.ffn_down.weight': _weights(random, [_ff, _embd]),
    },
  );
}

/// Writes a one-layer T5 encoder-only GGUF with random F32 weights and a
/// byte-fallback SentencePiece vocabulary to [path].
///
/// llama.cpp reports an encoder and no decoder for this architecture and
/// creates a KV cache for it. [poolingType] is the raw `llama_pooling_type`
/// value.
File writeSyntheticT5EncoderGguf(
  String path, {
  int? poolingType,
  int contextLength = 1024,
  int seed = 0,
}) {
  const arch = 't5encoder';
  const buckets = 32;
  final random = math.Random(seed);
  return _writeGguf(
    path,
    arch: arch,
    metadata: {
      '$arch.context_length': _GgufValue.uint32(contextLength),
      '$arch.embedding_length': _GgufValue.uint32(_embd),
      '$arch.feed_forward_length': _GgufValue.uint32(_ff),
      '$arch.block_count': _GgufValue.uint32(1),
      '$arch.attention.head_count': _GgufValue.uint32(2),
      '$arch.attention.layer_norm_rms_epsilon': _GgufValue.float32(1e-5),
      '$arch.attention.relative_buckets_count': _GgufValue.uint32(buckets),
      if (poolingType != null)
        '$arch.pooling_type': _GgufValue.uint32(poolingType),
    },
    tensors: {
      'token_embd.weight': _weights(random, [_embd, _tokens.length]),
      'enc.output_norm.weight': _ones([_embd]),
      'enc.blk.0.attn_norm.weight': _ones([_embd]),
      'enc.blk.0.attn_rel_b.weight': _weights(random, [2, buckets]),
      'enc.blk.0.attn_q.weight': _weights(random, [_embd, _embd]),
      'enc.blk.0.attn_k.weight': _weights(random, [_embd, _embd]),
      'enc.blk.0.attn_v.weight': _weights(random, [_embd, _embd]),
      'enc.blk.0.attn_o.weight': _weights(random, [_embd, _embd]),
      'enc.blk.0.ffn_norm.weight': _ones([_embd]),
      'enc.blk.0.ffn_up.weight': _weights(random, [_embd, _ff]),
      'enc.blk.0.ffn_down.weight': _weights(random, [_ff, _embd]),
    },
  );
}

/// Writes a one-layer T5 encoder-decoder GGUF with random F32 weights and a
/// byte-fallback SentencePiece vocabulary to [path].
///
/// llama.cpp reports both an encoder and a decoder for this architecture.
File writeSyntheticT5Gguf(String path, {int seed = 0}) {
  const arch = 't5';
  const buckets = 32;
  final random = math.Random(seed);
  (List<int>, List<double>) square() => _weights(random, [_embd, _embd]);
  return _writeGguf(
    path,
    arch: arch,
    metadata: {
      '$arch.context_length': _GgufValue.uint32(1024),
      '$arch.embedding_length': _GgufValue.uint32(_embd),
      '$arch.feed_forward_length': _GgufValue.uint32(_ff),
      '$arch.block_count': _GgufValue.uint32(1),
      '$arch.attention.head_count': _GgufValue.uint32(2),
      '$arch.attention.layer_norm_rms_epsilon': _GgufValue.float32(1e-5),
      '$arch.attention.relative_buckets_count': _GgufValue.uint32(buckets),
    },
    tensors: {
      'token_embd.weight': _weights(random, [_embd, _tokens.length]),
      'enc.output_norm.weight': _ones([_embd]),
      'enc.blk.0.attn_norm.weight': _ones([_embd]),
      'enc.blk.0.attn_rel_b.weight': _weights(random, [2, buckets]),
      'enc.blk.0.attn_q.weight': square(),
      'enc.blk.0.attn_k.weight': square(),
      'enc.blk.0.attn_v.weight': square(),
      'enc.blk.0.attn_o.weight': square(),
      'enc.blk.0.ffn_norm.weight': _ones([_embd]),
      'enc.blk.0.ffn_up.weight': _weights(random, [_embd, _ff]),
      'enc.blk.0.ffn_down.weight': _weights(random, [_ff, _embd]),
      'dec.output_norm.weight': _ones([_embd]),
      'dec.blk.0.attn_norm.weight': _ones([_embd]),
      'dec.blk.0.attn_rel_b.weight': _weights(random, [2, buckets]),
      'dec.blk.0.attn_q.weight': square(),
      'dec.blk.0.attn_k.weight': square(),
      'dec.blk.0.attn_v.weight': square(),
      'dec.blk.0.attn_o.weight': square(),
      'dec.blk.0.cross_attn_norm.weight': _ones([_embd]),
      'dec.blk.0.cross_attn_q.weight': square(),
      'dec.blk.0.cross_attn_k.weight': square(),
      'dec.blk.0.cross_attn_v.weight': square(),
      'dec.blk.0.cross_attn_o.weight': square(),
      'dec.blk.0.ffn_norm.weight': _ones([_embd]),
      'dec.blk.0.ffn_up.weight': _weights(random, [_embd, _ff]),
      'dec.blk.0.ffn_down.weight': _weights(random, [_ff, _embd]),
    },
  );
}

final _tokens = <String>[
  '<unk>',
  '<s>',
  '</s>',
  for (var byte = 0; byte < 256; byte++)
    '<0x${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}>',
];

(List<int>, List<double>) _weights(math.Random random, List<int> shape) => (
  shape,
  [
    for (var i = 0; i < shape.reduce((a, b) => a * b); i++)
      (random.nextDouble() - 0.5) * 0.2,
  ],
);

(List<int>, List<double>) _ones(List<int> shape) =>
    (shape, List<double>.filled(shape.reduce((a, b) => a * b), 1));

File _writeGguf(
  String path, {
  required String arch,
  required Map<String, _GgufValue> metadata,
  required Map<String, (List<int>, List<double>)> tensors,
}) {
  final allMetadata = <String, _GgufValue>{
    'general.architecture': _GgufValue.string(arch),
    ...metadata,
    'tokenizer.ggml.model': _GgufValue.string('llama'),
    'tokenizer.ggml.tokens': _GgufValue.strings(_tokens),
    'tokenizer.ggml.scores': _GgufValue.float32s(
      List<double>.filled(_tokens.length, 0),
    ),
    'tokenizer.ggml.token_type': _GgufValue.int32s([
      2,
      3,
      3,
      for (var byte = 0; byte < 256; byte++) 6,
    ]),
  };

  final out = BytesBuilder(copy: false);
  final header = _GgufBytes()
    ..raw('GGUF'.codeUnits)
    ..uint32(3)
    ..uint64(tensors.length)
    ..uint64(allMetadata.length);
  for (final MapEntry(:key, :value) in allMetadata.entries) {
    header.string(key);
    value.write(header);
  }
  var offset = 0;
  for (final MapEntry(key: name, value: (shape, values)) in tensors.entries) {
    header
      ..string(name)
      ..uint32(shape.length);
    shape.forEach(header.uint64);
    header
      ..uint32(0)
      ..uint64(offset);
    offset = _align(offset + values.length * 4);
  }
  out.add(header.bytes);
  out.add(Uint8List(_align(out.length) - out.length));
  for (final (_, values) in tensors.values) {
    final data = Float32List.fromList(values).buffer.asUint8List();
    out
      ..add(data)
      ..add(Uint8List(_align(data.length) - data.length));
  }
  return File(path)..writeAsBytesSync(out.takeBytes());
}

int _align(int value) => (value + _alignment - 1) ~/ _alignment * _alignment;

final class _GgufValue {
  _GgufValue(this.write);

  _GgufValue.uint32(int value)
    : this(
        (out) => out
          ..uint32(4)
          ..uint32(value),
      );

  _GgufValue.float32(double value)
    : this(
        (out) => out
          ..uint32(6)
          ..float32(value),
      );

  _GgufValue.boolean(bool value)
    : this(
        (out) => out
          ..uint32(7)
          ..raw([value ? 1 : 0]),
      );

  _GgufValue.string(String value)
    : this(
        (out) => out
          ..uint32(8)
          ..string(value),
      );

  _GgufValue.strings(List<String> values)
    : this((out) {
        out
          ..uint32(9)
          ..uint32(8)
          ..uint64(values.length);
        values.forEach(out.string);
      });

  _GgufValue.float32s(List<double> values)
    : this((out) {
        out
          ..uint32(9)
          ..uint32(6)
          ..uint64(values.length);
        values.forEach(out.float32);
      });

  _GgufValue.int32s(List<int> values)
    : this((out) {
        out
          ..uint32(9)
          ..uint32(5)
          ..uint64(values.length);
        values.forEach(out.int32);
      });

  final void Function(_GgufBytes out) write;
}

final class _GgufBytes {
  final _builder = BytesBuilder();
  final _scratch = ByteData(8);

  Uint8List get bytes => _builder.toBytes();

  void raw(List<int> bytes) => _builder.add(bytes);

  void uint32(int value) {
    _scratch.setUint32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void int32(int value) {
    _scratch.setInt32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void uint64(int value) {
    _scratch.setUint64(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 8));
  }

  void float32(double value) {
    _scratch.setFloat32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4));
  }

  void string(String value) {
    final bytes = utf8.encode(value);
    uint64(bytes.length);
    _builder.add(bytes);
  }
}
