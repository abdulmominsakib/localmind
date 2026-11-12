import 'dart:convert';
import 'dart:typed_data';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/image_model_classifier.dart';
import 'package:llamadart/src/core/image/image_model_metal_preflight.dart';
import 'package:test/test.dart';

import '../../../support/image_model_headers.dart';

void main() {
  const tensor = ('model.diffusion_model.weight', <int>[1]);
  Future<void> validate(Uint8List bytes, {bool index = false}) =>
      validateImageModelMetalDtypes(
        (offset, length) async => Uint8List.sublistView(
          bytes,
          offset.clamp(0, bytes.length),
          (offset + length).clamp(0, bytes.length),
        ),
        name: 'the main file',
        isJsonIndex: index,
      );

  for (final dtype in ['F8_E4M3', 'F8_E5M2']) {
    test('refuses Safetensors $dtype before native loading', () async {
      await expectLater(
        validate(safetensorsHeader([tensor], dtype: dtype, dataBytes: 1)),
        throwsA(
          isA<LlamaUnsupportedException>().having(
            (e) => e.message,
            'reason',
            contains('FP8 image weights in the main file'),
          ),
        ),
      );
    });
  }
  for (final type in [43, 44]) {
    test(
      'refuses GGUF $type including language-model encoder tensors',
      () async {
        await expectLater(
          validate(
            ggufHeader(
              metadata: {'general.architecture': 'qwen3'},
              tensors: [tensor],
              tensorType: type,
            ),
          ),
          throwsA(isA<LlamaUnsupportedException>()),
        );
      },
    );
  }
  test(
    'does not infer FP8 from metadata, names or unsupported dtype strings',
    () async {
      for (final dtype in ['F16', 'F32', 'BF16', 'I8', 'unknown']) {
        await validate(
          safetensorsHeader(
            [
              ('FP8_tensor', [1]),
            ],
            dtype: dtype,
            metadata: {'format': 'FP8'},
          ),
        );
      }
      for (final type in [0, 1, 8, 30, 42, 45]) {
        await validate(ggufHeader(tensors: [tensor], tensorType: type));
      }
    },
  );
  test(
    'Torch and unknown containers retain native explicit-role loading',
    () async {
      for (final bytes in [
        Uint8List.fromList([0x50, 0x4b, 3, 4]),
        ImageModelHeaders.pickle,
        Uint8List.fromList(utf8.encode('unknown format')),
      ]) {
        await validate(bytes);
      }
    },
  );
  test(
    'bounds a claimed oversized Safetensors header before reading it',
    () async {
      final bytes =
          (ByteData(9)
                ..setUint32(
                  0,
                  maxImageModelSafetensorsHeaderBytes + 1,
                  Endian.little,
                )
                ..setUint8(8, 0x7b))
              .buffer
              .asUint8List();
      await expectLater(
        validate(bytes),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test(
    'truncated GGUF and malformed Safetensors cannot bypass inspection',
    () async {
      await expectLater(
        validate(Uint8List.fromList(ascii.encode('GGUF'))),
        throwsA(isA<LlamaUnsupportedException>()),
      );
      final missingDtype = safetensorsHeader([tensor]);
      final text = utf8
          .decode(missingDtype.sublist(8))
          .replaceAll('"F16"', 'null');
      final bytes = Uint8List.fromList([
        ...(ByteData(8)..setUint32(0, utf8.encode(text).length, Endian.little))
            .buffer
            .asUint8List(),
        ...utf8.encode(text),
      ]);
      await expectLater(
        validate(bytes),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test(
    'GGUF magic takes precedence over a JSON suffix, as in the native loader',
    () async {
      await validate(ggufHeader(tensors: [tensor]), index: true);
      await expectLater(
        validate(ggufHeader(tensors: [tensor], tensorType: 43), index: true),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test('does not forward uninspected JSON shard indexes to Metal', () async {
    await expectLater(
      validate(Uint8List(0), index: true),
      throwsA(isA<LlamaUnsupportedException>()),
    );
  });
  test('read errors cannot leak paths', () async {
    await expectLater(
      validateImageModelMetalDtypes(
        (_, _) async => throw Exception('/private/secret-model'),
        name: 'component 1',
        isJsonIndex: false,
      ),
      throwsA(
        isA<LlamaModelException>().having(
          (e) => e.toString(),
          'private path',
          isNot(contains('secret-model')),
        ),
      ),
    );
  });
  group('imageModelFp8AsF16ExtraBytes', () {
    Future<int> extra(Uint8List bytes) => imageModelFp8AsF16ExtraBytes(
      (offset, length) async => Uint8List.sublistView(
        bytes,
        offset.clamp(0, bytes.length),
        (offset + length).clamp(0, bytes.length),
      ),
    );
    const tensors = [
      ('model.diffusion_model.a.weight', <int>[2, 3]),
      ('model.diffusion_model.b.weight', <int>[4]),
    ];

    test('is one byte per FP8 element', () async {
      for (final dtype in ['F8_E4M3', 'F8_E5M2']) {
        expect(await extra(safetensorsHeader(tensors, dtype: dtype)), 10);
      }
      for (final type in [43, 44]) {
        expect(await extra(ggufHeader(tensors: tensors, tensorType: type)), 10);
      }
    });

    test('is 0 for other dtypes and unreadable headers', () async {
      expect(await extra(safetensorsHeader(tensors)), 0);
      expect(await extra(ggufHeader(tensors: tensors, tensorType: 1)), 0);
      expect(await extra(Uint8List.fromList([123, 125])), 0);
      expect(
        await imageModelFp8AsF16ExtraBytes((_, _) async => throw Exception()),
        0,
      );
    });
  });
}
