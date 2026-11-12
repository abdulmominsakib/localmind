import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'safetensors_writer.dart';

/// A tensor of a [SyntheticDecisionHead].
final class SyntheticTensor {
  SyntheticTensor(this.shape, List<double> values) : values = List.of(values);

  final List<int> shape;
  final List<double> values;
}

/// Seeded random weights for every tensor of a Laya decision head of width
/// [d] with [layers] transformer layers.
final class SyntheticDecisionHead {
  SyntheticDecisionHead({
    required this.d,
    required this.layers,
    required int seed,
  }) : _random = math.Random(seed) {
    final f = 4 * d;
    tensors['type_emb.weight'] = _uniform([3, d], 0.5);
    for (var i = 0; i < layers; i++) {
      final p = 'head.layers.$i';
      tensors
        ..['$p.self_attn.in_proj_weight'] = _uniform([
          3 * d,
          d,
        ], 1 / math.sqrt(d))
        ..['$p.self_attn.in_proj_bias'] = _uniform([3 * d], 0.1)
        ..['$p.self_attn.out_proj.weight'] = _uniform([d, d], 1 / math.sqrt(d))
        ..['$p.self_attn.out_proj.bias'] = _uniform([d], 0.1)
        ..['$p.linear1.weight'] = _uniform([f, d], 1 / math.sqrt(d))
        ..['$p.linear1.bias'] = _uniform([f], 0.1)
        ..['$p.linear2.weight'] = _uniform([d, f], 1 / math.sqrt(f))
        ..['$p.linear2.bias'] = _uniform([d], 0.1)
        ..['$p.norm1.weight'] = _uniform([d], 0.2, 1)
        ..['$p.norm1.bias'] = _uniform([d], 0.1)
        ..['$p.norm2.weight'] = _uniform([d], 0.2, 1)
        ..['$p.norm2.bias'] = _uniform([d], 0.1);
    }
    tensors
      ..['scorer.0.weight'] = _uniform([d], 0.2, 1)
      ..['scorer.0.bias'] = _uniform([d], 0.1)
      ..['scorer.1.weight'] = _uniform([d, d], 1 / math.sqrt(d))
      ..['scorer.1.bias'] = _uniform([d], 0.1)
      ..['scorer.3.weight'] = _uniform([1, d], 1 / math.sqrt(d))
      ..['scorer.3.bias'] = _uniform([1], 0.1)
      ..['act_head.0.weight'] = _uniform([actHidden, d + 4], 0.4)
      ..['act_head.0.bias'] = _uniform([actHidden], 0.1)
      ..['act_head.2.weight'] = _uniform([actClasses, actHidden], 0.5)
      ..['act_head.2.bias'] = _uniform([actClasses], 0.1);
  }

  static const int actHidden = 8;
  static const int actClasses = 2;

  final int d;
  final int layers;
  final math.Random _random;
  final Map<String, SyntheticTensor> tensors = {};

  /// Random encoder output for [tokens] tokens.
  Float32List randomHidden(int tokens) => Float32List.fromList([
    for (var i = 0; i < tokens * d; i++) 2 * _random.nextDouble() - 1,
  ]);

  /// Writes [tensors] as an F32 safetensors file at [path].
  File write(String path) => writeSafetensors(path, {
    for (final MapEntry(key: name, value: tensor) in tensors.entries)
      name: TestTensor.f32(tensor.shape, tensor.values),
  });

  SyntheticTensor _uniform(List<int> shape, double scale, [double center = 0]) {
    final count = shape.fold(1, (a, b) => a * b);
    return SyntheticTensor(shape, [
      for (var i = 0; i < count; i++)
        _float(center + scale * (2 * _random.nextDouble() - 1)),
    ]);
  }
}

double _float(double value) => (Float32List(1)..[0] = value)[0];
