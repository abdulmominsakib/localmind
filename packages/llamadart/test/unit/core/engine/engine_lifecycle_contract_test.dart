import 'dart:async';

import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

import '../../../../example/basic_app/bin/llamadart_engine_lifecycle_example.dart'
    as example;
import '../../../support/engine_lifecycle_contract.dart';
import 'engine_test.dart';

class _HeldDisposalBackend extends MockLlamaBackend {
  final disposed = Completer<void>();
  int disposalCalls = 0;

  @override
  Future<void> dispose() async {
    disposalCalls++;
    await disposed.future;
    await super.dispose();
  }
}

class _DisposalOrderBackend extends MockLlamaBackend {
  void Function()? onDispose;
  int disposalCalls = 0;

  @override
  Future<void> dispose() async {
    onDispose?.call();
    disposalCalls++;
    await super.dispose();
  }
}

void main() {
  test('mixed cleanup releases dependants before their backend', () async {
    final backend = _DisposalOrderBackend();
    final text = LlamaEngine(backend);
    final recognition = SpeechToTextEngine.attach(
      text,
      adapter: const Qwen3AsrAdapter(),
    );
    final synthesis = TextToSpeechEngine.attach(
      text,
      adapter: const Qwen3TtsAdapter(),
    );
    backend.onDispose = () {
      expect(recognition.isDisposed, isTrue);
      expect(synthesis.isDisposed, isTrue);
    };
    final owned = <LlamadartEngine<EngineCapabilities>>[
      text,
      recognition,
      synthesis,
    ];
    addTearDown(() => example.closeEngines(owned));
    for (final engine in owned) {
      expect(engine.isDisposed, isFalse);
      expect((await engine.capabilities).isSupported, isFalse);
    }
    await example.closeEngines(owned);
    expect(backend.disposalCalls, 1);
    for (final engine in owned) {
      expect(engine.isDisposed, isTrue);
    }
  });

  test('typed speech lifecycle retains its borrowed text engine', () async {
    final backend = MockLlamaBackend();
    final text = LlamaEngine(backend);
    final recognition = SpeechToTextEngine.attach(
      text,
      adapter: const Qwen3AsrAdapter(),
    );
    final synthesis = TextToSpeechEngine.attach(
      text,
      adapter: const Qwen3TtsAdapter(),
    );
    final owned = <LlamadartEngine<EngineCapabilities>>[
      text,
      recognition,
      synthesis,
    ];
    addTearDown(() => example.closeEngines(owned));
    final recognitionCaps = await checkEngineLifecycle(recognition);
    expect(recognitionCaps.isSupported, isFalse);
    expect(text.isDisposed, isFalse);
    final synthesisCaps = await checkEngineLifecycle(synthesis);
    expect(synthesisCaps.isSupported, isFalse);
    expect(text.isDisposed, isFalse);
    await example.closeEngines(owned);
    expect(text.isDisposed, isTrue);
    for (final engine in owned) {
      expect((await engine.capabilities).isSupported, isFalse);
    }
  });

  test(
    'generic cleanup awaits backend disposal and shares its pending future',
    () async {
      final backend = _HeldDisposalBackend();
      final concrete = LlamaEngine(backend);
      final LlamadartEngine<LlamaEngineCapabilities> engine = concrete;
      var finished = false;
      final closed = checkEngineLifecycle(engine).then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(engine.isDisposed, isTrue);
      expect(finished, isFalse);
      expect(backend.disposalCalls, 1);
      backend.disposed.complete();
      await closed;
      expect(finished, isTrue);
      expect(backend.disposalCalls, 1);
    },
  );
}
