import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

/// Exercises lifecycle through the public generic interface, retaining C.
Future<C> checkEngineLifecycle<C extends EngineCapabilities>(
  LlamadartEngine<C> engine,
) async {
  expect(engine.isDisposed, isFalse);
  final before = await engine.capabilities;
  final first = engine.dispose();
  expect(engine.isDisposed, isTrue);
  expect(engine.dispose(), same(first));
  final during = await engine.capabilities;
  expect(during.isSupported, isFalse);
  expect(during.unsupportedReason?.toLowerCase(), contains('disposed'));
  await first;
  expect(engine.dispose(), same(first));
  expect((await engine.capabilities).isSupported, isFalse);
  return before;
}
