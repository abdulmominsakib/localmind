@TestOn('browser')
@Tags(<String>['local-only', 'e2e'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_embedding.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import 'multimodal_embedding_litert_inputs.dart';

// Exercises upstream directly because the production adapter fails closed until
// every input meets the native CPU parity gate. No production bypass is exposed.
void main() {
  test('pinned upstream WebGPU embeddings meet native CPU parity', () async {
    const origin = String.fromEnvironment(
      'LITERT_EMBEDDING_ORIGIN',
      defaultValue: 'http://127.0.0.1:5197',
    );
    final gpu = globalContext
        .getProperty<JSObject>('navigator'.toJS)
        .getProperty<JSObject?>('gpu'.toJS);
    expect(
      gpu,
      isNotNull,
      reason: 'Launch Chrome with --enable-unsafe-webgpu.',
    );
    final adapter = await gpu!
        .callMethod<JSPromise<JSObject?>>('requestAdapter'.toJS)
        .toDart;
    expect(adapter, isNotNull, reason: 'A real WebGPU adapter is required.');
    final info = adapter!.getProperty<JSObject>('info'.toJS);
    print(
      'adapter: ${info.getProperty<JSString>('vendor'.toJS).toDart} '
      '${info.getProperty<JSString>('architecture'.toJS).toDart}',
    );
    final loaded = Completer<void>();
    const callback = '__llamadartEmbeddingReferenceLoaded';
    globalContext.setProperty(callback.toJS, (() => loaded.complete()).toJS);
    final script = HTMLScriptElement()
      ..type = 'module'
      ..text =
          '''
import {EmbeddingEngine} from 'https://cdn.jsdelivr.net/npm/@litert-lm/core@0.19.0/+esm';
window.__llamadartEmbeddingReference = EmbeddingEngine;
window.$callback();
''';
    document.head!.append(script);
    addTearDown(() {
      script.remove();
      globalContext.delete(callback.toJS);
      globalContext.delete('__llamadartEmbeddingReference'.toJS);
    });
    await loaded.future.timeout(const Duration(seconds: 60));
    final settings = JSObject()
      ..setProperty('model'.toJS, '$origin/model.litertlm'.toJS)
      // Backend.GPU=4; conversation's GPU_ARTISAN=2 cannot run this engine.
      ..setProperty('backend'.toJS, 4.toJS)
      ..setProperty('visionBackend'.toJS, 3.toJS)
      ..setProperty('audioBackend'.toJS, 3.toJS)
      ..setProperty('maxInputLength'.toJS, 1024.toJS);
    final constructor = globalContext.getProperty<JSObject>(
      '__llamadartEmbeddingReference'.toJS,
    );
    late JSObject engine;
    try {
      engine = await constructor
          .callMethod<JSPromise<JSObject>>('create'.toJS, settings)
          .toDart;
    } catch (error) {
      print('Upstream engine creation failed: $error');
      rethrow;
    }
    addTearDown(
      () => engine.callMethod<JSPromise<JSAny?>>('delete'.toJS).toDart,
    );
    Future<List<double>> embed(LlamaEmbeddingInput input) async {
      final parts = prepareLiteRtLmEmbedding(input)
          .map<JSAny>((part) {
            if (part.type == 0) return utf8.decode(part.bytes).toJS;
            return JSObject()
              ..setProperty(
                'type'.toJS,
                (part.type == 1 ? 'image' : 'audio').toJS,
              )
              ..setProperty('data'.toJS, part.bytes.buffer.toJS);
          })
          .toList()
          .toJS;
      final options = JSObject()
        ..setProperty('normalize'.toJS, true.toJS)
        ..setProperty('inputOverflowStrategy'.toJS, 2.toJS);
      final response = await engine
          .callMethod<JSPromise<JSObject>>(
            'computeEmbedding'.toJS,
            parts,
            options,
          )
          .toDart;
      expect(response.getProperty<JSNumber>('numChunks'.toJS).toDartInt, 1);
      return response
          .getProperty<JSArray<JSNumber>>('embedding'.toJS)
          .toDart
          .map((v) => v.toDartDouble)
          .toList();
    }

    final vectors = <String, List<double>>{};
    for (final input in liteRtEmbeddingInputs().entries) {
      vectors[input.key] = await embed(input.value);
      expect(vectors[input.key], hasLength(768));
    }
    // Persist every vector before asserting so a failed gate retains all inputs.
    await window
        .fetch(
          '$origin/results'.toJS,
          RequestInit(method: 'POST', body: jsonEncode(vectors).toJS),
        )
        .toDart;
    final response = await window.fetch('$origin/native.json'.toJS).toDart;
    final native =
        jsonDecode((await response.text().toDart).toDart)
            as Map<String, dynamic>;
    final distances = <({double cosine, double relL2})>[];
    for (final entry in vectors.entries) {
      final distance = embeddingDistance(
        (native[entry.key] as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList(),
        entry.value,
      );
      distances.add(distance);
      print('${entry.key}: cosine=${distance.cosine}, relL2=${distance.relL2}');
    }
    for (final distance in distances) {
      expect(distance.cosine, greaterThanOrEqualTo(0.9998));
      expect(distance.relL2, lessThan(0.02));
    }
  });
}
