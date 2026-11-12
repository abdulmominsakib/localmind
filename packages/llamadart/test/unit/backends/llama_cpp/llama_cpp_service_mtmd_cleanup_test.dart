@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/backends/llama_cpp/exit_teardown_api.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:llamadart/src/core/models/chat/content_part.dart';
import 'package:test/test.dart';

import '../../../support/fake_mtmd.dart';

void main() {
  final owner = reflectClass(LlamaCppService).owner as LibraryMirror;
  Symbol private(String name) => MirrorSystem.getSymbol(name, owner);
  final sentinel = StateError('injected mtmd initialization failure');

  for (final failure in [
    'chunks',
    'image path',
    'image bytes',
    'audio path',
    'audio bytes',
    'audio samples',
  ]) {
    test('$failure failure releases scratch buffers and earlier bitmaps', () {
      final allocator = _RecordingAllocator();
      addTearDown(allocator.release);
      final calls = LlamaCppObjectCalls.upstream;
      final service = LlamaCppService(objectCalls: calls);
      final fake = FakeMtmd.install(service, tokens: const []);
      addTearDown(fake.dispose);
      final serviceMirror = reflect(service);
      final original = serviceMirror.getField(private('_mtmdFallbackApi'));
      final apiClass = original.type;
      final arguments = <Symbol, dynamic>{};
      for (final declaration
          in apiClass.declarations.values.whereType<VariableMirror>()) {
        if (!declaration.isStatic) {
          arguments[declaration.simpleName] = original
              .getField(declaration.simpleName)
              .reflectee;
        }
      }
      var chunksFreed = 0;
      var bitmapCalls = 0;
      Pointer<mtmd_bitmap> bitmap() {
        if (bitmapCalls++ == 1) throw sentinel;
        return Pointer.fromAddress(0x20);
      }

      arguments[#inputChunksInit] = () {
        if (failure == 'chunks') throw sentinel;
        return Pointer<mtmd_input_chunks>.fromAddress(0x10);
      };
      arguments[#inputChunksFree] = (Pointer<mtmd_input_chunks> chunks) {
        expect(chunks.address, 0x10);
        chunksFreed++;
      };
      arguments[#bitmapInitFromAudio] = (int _, Pointer<Float> _) => bitmap();
      mtmd_helper_bitmap_wrapper encoded() =>
          Struct.create<mtmd_helper_bitmap_wrapper>()..bitmap = bitmap();
      arguments[#helperBitmapInitFromFile] =
          (
            Pointer<mtmd_context> _,
            Pointer<Char> _,
            bool _,
            mtmd_helper_init_opt _,
          ) => encoded();
      arguments[#helperBitmapInitFromBuf] =
          (
            Pointer<mtmd_context> _,
            Pointer<UnsignedChar> _,
            int _,
            bool _,
            mtmd_helper_init_opt _,
          ) => encoded();
      serviceMirror.setField(
        private('_mtmdFallbackApi'),
        apiClass.newInstance(Symbol.empty, [], arguments).reflectee,
      );
      final contextClass =
          owner.declarations[private('_LlamaContextWrapper')] as ClassMirror;
      final context = contextClass.newInstance(Symbol.empty, [
        Pointer<llama_context>.fromAddress(0x40),
        null,
        calls,
      ]).reflectee;
      final LlamaContentPart part = switch (failure) {
        'image path' => LlamaImageContent(path: 'image.png'),
        'image bytes' => LlamaImageContent(bytes: Uint8List.fromList([1, 2])),
        'audio path' => LlamaAudioContent(path: 'audio.wav'),
        'audio bytes' => LlamaAudioContent(bytes: Uint8List.fromList([1, 2])),
        _ => LlamaAudioContent(samples: Float32List.fromList([0.5])),
      };
      expect(
        () => serviceMirror.invoke(
          private('_ingestMultimodalPrompt'),
          [
            FakeMtmd.projector,
            context,
            nullptr.cast<llama_vocab>(),
            '',
            <LlamaContentPart>[
              LlamaAudioContent(samples: Float32List(1)),
              part,
            ],
            Struct.create<llama_context_params>(),
            nullptr.cast<Int8>(),
          ],
          {#chatMediaMarker: null, #allocator: allocator},
        ),
        throwsA(same(sentinel)),
      );
      expect(
        allocator.live,
        isEmpty,
        reason:
            'Every scratch allocation must be freed on a throwing constructor.',
      );
      expect(chunksFreed, failure == 'chunks' ? 0 : 1);
      expect(fake.freedBitmaps, failure == 'chunks' ? isEmpty : [0x20]);
    });
  }
}

final class _RecordingAllocator implements Allocator {
  final Set<Pointer<NativeType>> live = {};

  @override
  Pointer<T> allocate<T extends NativeType>(int byteCount, {int? alignment}) {
    final pointer = calloc.allocate<T>(byteCount, alignment: alignment);
    live.add(pointer);
    return pointer;
  }

  @override
  void free(Pointer<NativeType> pointer) {
    expect(live.remove(pointer), isTrue, reason: 'No unowned or double frees.');
    calloc.free(pointer);
  }

  void release() {
    for (final pointer in live) {
      calloc.free(pointer);
    }
    live.clear();
  }
}
