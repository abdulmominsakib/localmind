import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:llamadart/src/core/exceptions.dart';
import 'package:llamadart/src/core/image/image_generation_model.dart';
import 'package:llamadart/src/core/image/image_model_classifier.dart';

import '../../../support/image_model_headers.dart';

ImageModelFileReader _reader(Uint8List bytes, {List<int>? fetched}) =>
    (offset, length) async {
      final start = offset.clamp(0, bytes.length);
      final end = (offset + length).clamp(0, bytes.length);
      fetched?.add(end - start);
      return Uint8List.sublistView(bytes, start, end);
    };

/// A sparse GGUF of two `uint64` arrays: 4194304 items (32 MiB of zeros),
/// then [secondCount] items whose data ends the header 64 MiB minus 6 bytes
/// in at 4194294 items.
ImageModelFileReader _twoArrays(int secondCount) {
  final first = ggufHeader(metadata: {'a': const GgufArray(10, 4194304)})
    ..buffer.asByteData().setUint32(16, 2, Endian.little);
  final second = Uint8List.sublistView(
    ggufHeader(metadata: {'b': GgufArray(10, secondCount)}),
    24,
  );
  final secondOffset = first.length + 4194304 * 8;
  return (offset, length) async {
    final bytes = Uint8List(length);
    for (final (start, segment) in [(0, first), (secondOffset, second)]) {
      for (var i = 0; i < segment.length; i++) {
        final at = start + i - offset;
        if (at >= 0 && at < length) {
          bytes[at] = segment[i];
        }
      }
    }
    return bytes;
  };
}

Future<ImageModelFileClassification> _classify(Uint8List bytes) async =>
    classifyImageModelFile(await readImageModelFileHeader(_reader(bytes)));

Future<ImageModelAssignment> _assign(List<Object> files) =>
    assignImageModelRoles([
      for (final file in files)
        switch (file) {
          Uint8List bytes => ImageModelFileInput(read: _reader(bytes)),
          (Uint8List bytes, ImageModelRole role) => ImageModelFileInput(
            read: _reader(bytes),
            role: role,
          ),
          _ => throw ArgumentError.value(file),
        },
    ]);

Matcher _modelError(Object messageMatcher) => throwsA(
  isA<LlamaModelException>().having(
    (error) => error.message,
    'message',
    messageMatcher,
  ),
);

void main() {
  group('classifyImageModelFile', () {
    test('assigns each component its role from GGUF or safetensors '
        'headers', () async {
      final cases = <String, (Uint8List, ImageModelRole, int?)>{
        'SDXS checkpoint': (
          ImageModelHeaders.sdxsCheckpoint,
          ImageModelRole.checkpoint,
          4,
        ),
        'SD-Turbo checkpoint': (
          ImageModelHeaders.sdTurboCheckpoint,
          ImageModelRole.checkpoint,
          4,
        ),
        'SDXL checkpoint': (
          ImageModelHeaders.sdxlCheckpoint,
          ImageModelRole.checkpoint,
          4,
        ),
        'SD 3.5 diffusion': (
          ImageModelHeaders.sd35Diffusion,
          ImageModelRole.diffusionModel,
          16,
        ),
        'FLUX diffusion': (
          ImageModelHeaders.fluxDiffusion,
          ImageModelRole.diffusionModel,
          16,
        ),
        'Z-Image diffusion': (
          ImageModelHeaders.zImageDiffusion,
          ImageModelRole.diffusionModel,
          16,
        ),
        'FLUX ae': (ImageModelHeaders.fluxVae, ImageModelRole.vae, 16),
        'SDXL VAE': (ImageModelHeaders.sdxlVae, ImageModelRole.vae, 4),
        'TAESD': (ImageModelHeaders.taesd, ImageModelRole.taesd, 4),
        'TAEF1': (ImageModelHeaders.taef1, ImageModelRole.taesd, 16),
        'CLIP-L': (ImageModelHeaders.clipL, ImageModelRole.clipL, null),
        'CLIP-G': (ImageModelHeaders.clipG, ImageModelRole.clipG, null),
        'T5-XXL': (ImageModelHeaders.t5xxl, ImageModelRole.t5xxl, null),
        'Qwen3': (ImageModelHeaders.qwen3Llm, ImageModelRole.llm, null),
        'ControlNet': (
          ImageModelHeaders.controlNet,
          ImageModelRole.controlNet,
          null,
        ),
        'Diffusers ControlNet': (
          ImageModelHeaders.diffusersControlNet,
          ImageModelRole.controlNet,
          null,
        ),
      };
      for (final MapEntry(key: name, value: (bytes, role, channels))
          in cases.entries) {
        final classification = await _classify(bytes);
        expect(classification.kind, ImageModelFileKind.component, reason: name);
        expect(classification.role, role, reason: name);
        expect(classification.latentChannels, channels, reason: name);
      }
    });

    test('names what a non-component file is', () async {
      final cases = <String, (Uint8List, ImageModelFileKind)>{
        'LoRA': (ImageModelHeaders.lora, ImageModelFileKind.lora),
        'upscaler': (ImageModelHeaders.upscaler, ImageModelFileKind.upscaler),
        'mmproj': (ImageModelHeaders.mmproj, ImageModelFileKind.visionEncoder),
        'decoder-only TAESD': (
          ImageModelHeaders.decoderOnlyTaesd,
          ImageModelFileKind.decoderOnlyTaesd,
        ),
        'unknown': (ImageModelHeaders.unknown, ImageModelFileKind.unknown),
      };
      for (final MapEntry(key: name, value: (bytes, kind)) in cases.entries) {
        final classification = await _classify(bytes);
        expect(classification.kind, kind, reason: name);
        expect(classification.role, isNull, reason: name);
      }
    });

    test(
      'reads text-context width and hint channels for ControlNet admission',
      () async {
        final cases = <String, (Uint8List, int?, int?)>{
          'SD 1.x checkpoint': (ImageModelHeaders.sd15Checkpoint(), 768, null),
          'SD 2.x context checkpoint': (
            ImageModelHeaders.sd15Checkpoint(contextWidth: 1024),
            1024,
            null,
          ),
          'checkpoint without an attention key': (
            ImageModelHeaders.sdTurboCheckpoint,
            null,
            null,
          ),
          'original ControlNet': (ImageModelHeaders.sd15ControlNet(), 768, 3),
          'unprefixed ControlNet': (
            ImageModelHeaders.sd15ControlNet(prefix: ''),
            768,
            3,
          ),
          'GGUF ControlNet': (
            ImageModelHeaders.sd15ControlNet(gguf: true),
            768,
            3,
          ),
          'SD 2.x ControlNet': (
            ImageModelHeaders.sd15ControlNet(contextWidth: 1024),
            1024,
            3,
          ),
          'four-channel hint': (
            ImageModelHeaders.sd15ControlNet(hintChannels: 4),
            768,
            4,
          ),
          'ControlNet missing zero convolutions': (
            ImageModelHeaders.controlNet,
            null,
            null,
          ),
          'Diffusers ControlNet': (
            ImageModelHeaders.diffusersControlNet,
            null,
            null,
          ),
        };
        for (final MapEntry(key: name, value: (bytes, width, hint))
            in cases.entries) {
          final classification = await _classify(bytes);
          expect(classification.crossAttentionWidth, width, reason: name);
          expect(classification.controlHintChannels, hint, reason: name);
        }
      },
    );

    test('a checkpoint reports an embedded tiny autoencoder', () async {
      expect(
        (await _classify(
          ImageModelHeaders.sdxsCheckpoint,
        )).embedsTinyAutoencoder,
        isTrue,
      );
      expect(
        (await _classify(
          ImageModelHeaders.sdTurboCheckpoint,
        )).embedsTinyAutoencoder,
        isFalse,
      );
    });
  });

  group('readImageModelFileHeader', () {
    test('stops a language-model GGUF at general.architecture', () async {
      final fetched = <int>[];

      final header = await readImageModelFileHeader(
        _reader(ImageModelHeaders.qwen3Llm, fetched: fetched),
      );

      expect(header.stoppedAtArchitecture, isTrue);
      expect(header.architecture, 'qwen3');
      expect(header.tensors, isEmpty);
      expect(
        fetched.fold<int>(0, (sum, bytes) => sum + bytes),
        lessThan(ImageModelHeaders.qwen3Llm.length),
      );
    });

    test('reads every tensor of other GGUFs and of safetensors', () async {
      final gguf = await readImageModelFileHeader(
        _reader(ImageModelHeaders.fluxDiffusion),
      );
      expect(gguf.isGguf, isTrue);
      expect(gguf.tensors.map((t) => t.name), [
        'double_blocks.0.img_attn.qkv.weight',
        'img_in.weight',
        'final_layer.linear.bias',
      ]);
      expect(gguf.tensors[1].shape, [64, 3072]);

      final safetensors = await readImageModelFileHeader(
        _reader(
          safetensorsHeader(
            [
              ('decoder.conv_in.weight', [512, 16, 3, 3]),
            ],
            metadata: {'format': 'pt'},
            dataBytes: 32,
          ),
        ),
      );
      expect(safetensors.isGguf, isFalse);
      expect(safetensors.metadata, {'format': 'pt'});
      expect(safetensors.tensors.single.shape, [512, 16, 3, 3]);
    });

    test('rejects files that are neither GGUF nor safetensors, and truncated '
        'headers', () async {
      for (final bytes in [
        ImageModelHeaders.pickle,
        Uint8List(3),
        Uint8List.sublistView(ImageModelHeaders.fluxDiffusion, 0, 40),
        Uint8List.sublistView(ImageModelHeaders.fluxVae, 0, 20),
      ]) {
        await expectLater(
          readImageModelFileHeader(_reader(bytes)),
          throwsFormatException,
        );
      }
    });
  });

  group('header bounds', () {
    Future<Object?> read(Uint8List bytes, {List<int>? fetched}) async {
      try {
        return await readImageModelFileHeader(_reader(bytes, fetched: fetched));
      } on FormatException catch (error) {
        return error;
      }
    }

    test('accepts the largest counts it allows', () async {
      final tensors = await read(
        ggufHeader(
          tensors: [
            for (var i = 0; i < 65536; i++) ('t$i', [1]),
          ],
        ),
      );
      expect((tensors as ImageModelFileHeader).tensors, hasLength(65536));

      final keys = await read(
        ggufHeader(metadata: {for (var i = 0; i < 65536; i++) 'k$i': i}),
      );
      expect((keys as ImageModelFileHeader).metadata, hasLength(65536));

      final array = await read(
        ggufHeader(metadata: {'a': const GgufArray(0, 4194304)}),
      );
      expect(array, isA<ImageModelFileHeader>());

      final string = await read(ggufHeader(metadata: {'s': 'x' * 1048576}));
      expect(
        ((string as ImageModelFileHeader).metadata['s'] as String).length,
        1048576,
      );

      expect(
        await readImageModelFileHeader(_twoArrays(4194294)),
        isA<ImageModelFileHeader>(),
      );

      final json = '{"__metadata__":{"pad":"';
      final padding = (16 << 20) - json.length - 3;
      final safetensors = await read(
        Uint8List.fromList([
          ...(ByteData(
            8,
          )..setUint32(0, 16 << 20, Endian.little)).buffer.asUint8List(),
          ...'$json${'x' * padding}"}}'.codeUnits,
        ]),
      );
      expect(safetensors, isA<ImageModelFileHeader>());
    });

    test('rejects a count, string or header beyond its bound without reading '
        'it', () async {
      const count = 'Implausible GGUF header count.';
      final cases = <String, (Uint8List, String)>{
        'tensors': (
          ggufHeader(
            tensors: [
              ('t', [1]),
            ],
          )..buffer.asByteData().setUint32(8, 65537, Endian.little),
          count,
        ),
        'keys': (
          ggufHeader(metadata: {'k': 1})
            ..buffer.asByteData().setUint32(16, 65537, Endian.little),
          count,
        ),
        'array items': (
          ggufHeader(metadata: {'a': const GgufArray(0, 4194305)}),
          count,
        ),
        'string bytes': (
          ggufHeader(metadata: {'s': 'x'})
            ..buffer.asByteData().setUint32(37, 1048577, Endian.little),
          'Implausible GGUF string length.',
        ),
        'safetensors header': (
          Uint8List.fromList([
            ...(ByteData(8)..setUint32(0, (16 << 20) + 1, Endian.little)).buffer
                .asUint8List(),
            ...'{}'.codeUnits,
          ]),
          'Not a GGUF or safetensors file.',
        ),
      };
      for (final MapEntry(key: name, value: (bytes, message))
          in cases.entries) {
        final fetched = <int>[];
        final stopwatch = Stopwatch()..start();

        expect(
          await read(bytes, fetched: fetched),
          isA<FormatException>().having((e) => e.message, 'message', message),
          reason: name,
        );
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 1)),
          reason: name,
        );
        expect(
          fetched.fold<int>(0, (sum, length) => sum + length),
          lessThanOrEqualTo(bytes.length),
          reason: name,
        );
      }
    });

    test('rejects a header that would pass 64 MiB', () async {
      await expectLater(
        readImageModelFileHeader(_twoArrays(4194295)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Model file header is too large.',
          ),
        ),
      );
    });

    test('reads both halves of 64-bit values', () async {
      final header = await readImageModelFileHeader(
        _reader(ggufHeader(metadata: {'size': const GgufU64(0x100000005)})),
      );

      expect(header.metadata['size'], 0x100000005);
    });
  });

  group('readGgufMetadata', () {
    test('reads the key/value block without the tensor infos', () async {
      final header = ggufHeader(
        metadata: {'clip.audio.projector_type': 'qwen3a'},
        tensors: [
          ('a.weight', [4, 4]),
        ],
      );
      final metadataOnly = Uint8List.sublistView(
        header,
        0,
        header.length -
            ggufHeader(
              tensors: [
                ('a.weight', [4, 4]),
              ],
            ).length +
            24,
      );
      await expectLater(
        readImageModelFileHeader(_reader(metadataOnly)),
        throwsFormatException,
      );

      expect(await readGgufMetadata(_reader(metadataOnly), maxBytes: 1 << 20), {
        'clip.audio.projector_type': 'qwen3a',
      });
    });

    test('stops after the requested key', () async {
      final header = ggufHeader(
        metadata: {'clip.projector_type': 'qwen3a', 'later': 'value'},
      );
      final throughStopKey = Uint8List.sublistView(
        header,
        0,
        header.length - ggufHeader(metadata: {'later': 'value'}).length + 24,
      );

      expect(
        await readGgufMetadata(
          _reader(throughStopKey),
          maxBytes: 1 << 20,
          stopAt: 'clip.projector_type',
        ),
        {'clip.projector_type': 'qwen3a'},
      );
    });

    test('rejects metadata past maxBytes', () async {
      final bytes = ggufHeader(
        metadata: {
          'padding': const GgufArray(0, 2 << 20, itemBytes: 2 << 20),
          'clip.audio.projector_type': 'qwen3tts_spkenc',
        },
      );

      expect(
        (await readGgufMetadata(
          _reader(bytes),
          maxBytes: 64 << 20,
        ))['clip.audio.projector_type'],
        'qwen3tts_spkenc',
      );
      await expectLater(
        readGgufMetadata(_reader(bytes), maxBytes: 1 << 20),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Model file header is too large.',
          ),
        ),
      );
    });

    test('rejects a file that is not GGUF', () async {
      await expectLater(
        readGgufMetadata(
          _reader(
            safetensorsHeader([
              ('a', <int>[1]),
            ]),
          ),
          maxBytes: 1 << 20,
        ),
        throwsFormatException,
      );
    });
  });

  group('assignImageModelRoles', () {
    test(
      'tiling requires positive checkpoint and decoder header proof',
      () async {
        for (final (headers, expected) in [
          ([ImageModelHeaders.sdTurboCheckpoint], true),
          (
            [ImageModelHeaders.sdTurboCheckpoint, ImageModelHeaders.taesd],
            true,
          ),
          ([ImageModelHeaders.sdxsCheckpoint], false),
          ([(Uint8List(8), ImageModelRole.checkpoint)], false),
          (
            [
              ImageModelHeaders.sdTurboCheckpoint,
              (Uint8List(8), ImageModelRole.taesd),
            ],
            false,
          ),
          ([ImageModelHeaders.fluxDiffusion, ImageModelHeaders.fluxVae], false),
        ]) {
          expect((await _assign(headers)).vaeTilingDecoderVerified, expected);
        }
      },
    );

    test(
      'ControlNet admission requires SD 1.x checkpoint and ControlNet proof',
      () async {
        final checkpoint = ImageModelHeaders.sd15Checkpoint();
        final control = ImageModelHeaders.sd15ControlNet();
        for (final (name, headers, expected) in <(String, List<Object>, bool)>[
          ('SD 1.x pair', [checkpoint, control], true),
          ('order', [control, checkpoint], true),
          (
            'explicit agreeing role',
            [checkpoint, (control, ImageModelRole.controlNet)],
            true,
          ),
          (
            'GGUF ControlNet',
            [checkpoint, ImageModelHeaders.sd15ControlNet(gguf: true)],
            true,
          ),
          ('no ControlNet', [checkpoint], false),
          (
            'SD 2.x base',
            [ImageModelHeaders.sd15Checkpoint(contextWidth: 1024), control],
            false,
          ),
          (
            'SD 2.x ControlNet',
            [checkpoint, ImageModelHeaders.sd15ControlNet(contextWidth: 1024)],
            false,
          ),
          (
            'four-channel hint',
            [checkpoint, ImageModelHeaders.sd15ControlNet(hintChannels: 4)],
            false,
          ),
          (
            'Diffusers layout',
            [checkpoint, ImageModelHeaders.diffusersControlNet],
            false,
          ),
          (
            'explicit role without a header',
            [checkpoint, (Uint8List(8), ImageModelRole.controlNet)],
            false,
          ),
          (
            'explicit role over another layout',
            [checkpoint, (ImageModelHeaders.taesd, ImageModelRole.controlNet)],
            false,
          ),
          (
            'unknown checkpoint width',
            [ImageModelHeaders.sdTurboCheckpoint, control],
            false,
          ),
          (
            'tiny embedded decoder',
            [ImageModelHeaders.sdxsCheckpoint, control],
            false,
          ),
          (
            'extra component',
            [checkpoint, control, ImageModelHeaders.taesd],
            false,
          ),
          (
            'split diffusion model',
            [
              ImageModelHeaders.fluxDiffusion,
              ImageModelHeaders.fluxVae,
              control,
            ],
            false,
          ),
        ]) {
          final assignment = await _assign(headers);
          expect(assignment.controlNetRecipeVerified, expected, reason: name);
          if (expected) {
            expect(assignment.roles.keys, {
              ImageModelRole.checkpoint,
              ImageModelRole.controlNet,
            }, reason: name);
          }
        }
        await expectLater(
          _assign([checkpoint, control, control]),
          _modelError(contains('both controlNet files')),
        );
      },
    );

    test('FLUX.1 Kontext admission requires a FLUX guidance transformer with '
        'exactly the FLUX autoencoder, CLIP-L and T5-XXL', () async {
      final kontext = ImageModelHeaders.fluxKontextDiffusion;
      final ae = ImageModelHeaders.fluxVae;
      final clipL = ImageModelHeaders.clipL;
      final t5 = ImageModelHeaders.t5xxl;
      for (final (name, headers, expected) in <(String, List<Object>, bool)>[
        ('Kontext set', [kontext, ae, clipL, t5], true),
        ('order', [t5, clipL, ae, kontext], true),
        (
          'explicit agreeing role',
          [(kontext, ImageModelRole.diffusionModel), ae, clipL, t5],
          true,
        ),
        (
          'FLUX.1-schnell without a guidance embedder',
          [ImageModelHeaders.fluxDiffusion, ae, clipL, t5],
          false,
        ),
        (
          'FLUX.1-Fill patch input',
          [ImageModelHeaders.fluxFillDiffusion, ae, clipL, t5],
          false,
        ),
        (
          'explicit role without a header',
          [(Uint8List(8), ImageModelRole.diffusionModel), ae, clipL, t5],
          false,
        ),
        (
          'explicit role over another layout',
          [(t5, ImageModelRole.diffusionModel), ae, clipL],
          false,
        ),
        (
          'no FLUX double blocks',
          [
            ggufHeader(
              tensors: [
                ('transformer_blocks.0.attn.to_q.weight', [3072, 3072]),
                ('guidance_in.in_layer.weight', [256, 3072]),
                ('img_in.weight', [64, 3072]),
                ('final_layer.linear.bias', [64]),
              ],
            ),
            ae,
            clipL,
            t5,
          ],
          false,
        ),
        (
          'unknown transformer latent channels',
          [
            ggufHeader(
              tensors: [
                ('double_blocks.0.img_attn.qkv.weight', [3072, 9216]),
                ('guidance_in.in_layer.weight', [256, 3072]),
                ('img_in.weight', [64, 3072]),
                ('final_layer.linear.bias', [128]),
              ],
            ),
            ae,
            clipL,
            t5,
          ],
          false,
        ),
        ('no autoencoder', [kontext, clipL, t5], false),
        (
          'explicit VAE role without a header',
          [kontext, (Uint8List(8), ImageModelRole.vae), clipL, t5],
          false,
        ),
        (
          'CLIP-G in place of CLIP-L',
          [kontext, ae, ImageModelHeaders.clipG, t5],
          false,
        ),
        (
          'CLIP-G in place of T5-XXL',
          [kontext, ae, clipL, ImageModelHeaders.clipG],
          false,
        ),
        ('no CLIP-L', [kontext, ae, t5], false),
        ('no T5-XXL', [kontext, ae, clipL], false),
        (
          'tiny autoencoder in place of ae',
          [kontext, ImageModelHeaders.taef1, clipL, t5],
          false,
        ),
        (
          'extra component',
          [kontext, ae, clipL, t5, ImageModelHeaders.clipG],
          false,
        ),
        (
          'SD 3.5 transformer',
          [ImageModelHeaders.sd35Diffusion, ae, clipL, t5],
          false,
        ),
      ]) {
        expect(
          (await _assign(headers)).fluxKontextRecipeVerified,
          expected,
          reason: name,
        );
      }
    });

    test('assigns roles whatever the order of the files', () async {
      final assignment = await _assign([
        ImageModelHeaders.t5xxl,
        ImageModelHeaders.fluxVae,
        ImageModelHeaders.fluxDiffusion,
        ImageModelHeaders.clipL,
      ]);

      expect(assignment.roles, {
        ImageModelRole.t5xxl: 0,
        ImageModelRole.vae: 1,
        ImageModelRole.diffusionModel: 2,
        ImageModelRole.clipL: 3,
      });
      expect(assignment.decodesWithTinyAutoencoder, isFalse);
    });

    test('reports a tiny autoencoder from a taesd file or an embedded '
        'one', () async {
      expect(
        (await _assign([
          ImageModelHeaders.sdxsCheckpoint,
        ])).decodesWithTinyAutoencoder,
        isTrue,
      );
      expect(
        (await _assign([
          ImageModelHeaders.sdTurboCheckpoint,
        ])).decodesWithTinyAutoencoder,
        isFalse,
      );
      expect(
        (await _assign([
          ImageModelHeaders.taesd,
          ImageModelHeaders.sdTurboCheckpoint,
        ])).decodesWithTinyAutoencoder,
        isTrue,
      );
    });

    test('refuses non-component files, naming them by position', () async {
      final cases = <Uint8List, String>{
        ImageModelHeaders.lora: 'Component 1 is a LoRA adapter',
        ImageModelHeaders.upscaler: 'Component 1 is an upscaler',
        ImageModelHeaders.mmproj: 'Component 1 is a vision encoder',
        ImageModelHeaders.decoderOnlyTaesd:
            'Component 1 is a decoder-only tiny autoencoder',
        ImageModelHeaders.unknown:
            'Component 1 is not a known image-model file',
        ImageModelHeaders.pickle: 'Cannot detect the role of component 1',
      };
      for (final MapEntry(key: bytes, value: message) in cases.entries) {
        await expectLater(
          _assign([ImageModelHeaders.sdTurboCheckpoint, bytes]),
          _modelError(startsWith(message)),
          reason: message,
        );
      }
      await expectLater(
        _assign([ImageModelHeaders.unknown]),
        _modelError(
          allOf(
            startsWith('The main file is not a known image-model file'),
            contains('ImageModelComponent(source, role: ...)'),
          ),
        ),
      );
    });

    test('a read failure names the file by position only', () async {
      await expectLater(
        assignImageModelRoles([
          ImageModelFileInput(
            read: _reader(ImageModelHeaders.sdTurboCheckpoint),
          ),
          ImageModelFileInput(
            read: (offset, length) async =>
                throw StateError('cannot open /private/models/vae.gguf'),
          ),
        ]),
        _modelError('Cannot read the header of component 1.'),
      );
    });

    test('takes an explicit role for a file it cannot classify', () async {
      final assignment = await _assign([
        (ImageModelHeaders.pickle, ImageModelRole.checkpoint),
        ImageModelHeaders.taesd,
      ]);

      expect(assignment.roles, {
        ImageModelRole.checkpoint: 0,
        ImageModelRole.taesd: 1,
      });
    });

    test('an explicit role resolves files with the same layout', () async {
      await expectLater(
        _assign([
          ImageModelHeaders.sdTurboCheckpoint,
          ImageModelHeaders.taesd,
          ImageModelHeaders.taesd,
        ]),
        _modelError(
          'Component 1 and component 2 are both taesd files; pass one file '
          'per role.',
        ),
      );

      final assignment = await _assign([
        ImageModelHeaders.sdTurboCheckpoint,
        ImageModelHeaders.sdxlVae,
        (ImageModelHeaders.fluxVae, ImageModelRole.taesd),
      ]);
      expect(assignment.roles[ImageModelRole.taesd], 2);
    });

    test('needs exactly one source of diffusion weights', () async {
      await expectLater(
        _assign([ImageModelHeaders.clipL, ImageModelHeaders.fluxVae]),
        _modelError(contains('None of the image model files holds diffusion')),
      );
      await expectLater(
        _assign([
          ImageModelHeaders.sdTurboCheckpoint,
          ImageModelHeaders.fluxDiffusion,
        ]),
        _modelError(
          allOf(
            contains('both a checkpoint (the main file)'),
            contains('separate diffusion weights (component 1)'),
          ),
        ),
      );
    });

    test('refuses a decoder for other latent channels', () async {
      await expectLater(
        _assign([
          ImageModelHeaders.fluxDiffusion,
          ImageModelHeaders.taesd,
          ImageModelHeaders.clipL,
          ImageModelHeaders.t5xxl,
        ]),
        _modelError(
          'The taesd file (component 1) decodes 4-channel latents, but the '
          'diffusion weights (the main file) produce 16-channel latents. Use '
          'the decoder made for this model family.',
        ),
      );
      await expectLater(
        _assign([ImageModelHeaders.sdxlVae, ImageModelHeaders.sd35Diffusion]),
        _modelError(startsWith('The vae file (the main file) decodes 4')),
      );
      await expectLater(
        _assign([ImageModelHeaders.sdTurboCheckpoint, ImageModelHeaders.taef1]),
        _modelError(contains('16-channel latents')),
      );

      final inpainting = await _assign([
        ImageModelHeaders.inpaintingCheckpoint,
        ImageModelHeaders.sdxlVae,
      ]);
      expect(inpainting.roles[ImageModelRole.vae], 1);
      await expectLater(
        _assign([
          ImageModelHeaders.inpaintingCheckpoint,
          ImageModelHeaders.taef1,
        ]),
        _modelError(contains('produce 4-channel latents')),
      );

      final unknownChannels = await _assign([
        ImageModelHeaders.wideTransformer,
        ImageModelHeaders.taesd,
      ]);
      expect(unknownChannels.roles[ImageModelRole.taesd], 1);

      final matched = await _assign([
        ImageModelHeaders.zImageDiffusion,
        ImageModelHeaders.fluxVae,
        ImageModelHeaders.qwen3Llm,
      ]);
      expect(matched.roles.keys, [
        ImageModelRole.diffusionModel,
        ImageModelRole.vae,
        ImageModelRole.llm,
      ]);
    });

    test('checks the channels of a file whose explicit role its header '
        'agrees with', () async {
      await expectLater(
        _assign([
          ImageModelHeaders.fluxDiffusion,
          (ImageModelHeaders.taesd, ImageModelRole.taesd),
        ]),
        _modelError(contains('decodes 4-channel latents')),
      );
    });
  });
}
