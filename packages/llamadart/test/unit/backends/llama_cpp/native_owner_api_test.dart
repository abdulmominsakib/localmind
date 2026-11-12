@TestOn('vm')
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'package:llamadart/src/backends/llama_cpp/native_owner_api.dart';

void main() {
  test('absent owner API preserves old-artifact capability fallback', () {
    final requested = <String>[];
    expect(
      NativeOwnerApi.tryResolve(
        symbol: (name) {
          requested.add(name);
          throw ArgumentError('Missing $name');
        },
      ),
      isNull,
    );
    expect(requested, ['llama_dart_owner_api_version']);
  });

  test('unsupported owner version cannot admit creators', () {
    final version = NativeCallable<Uint32 Function()>.isolateLocal(
      () => 2,
      exceptionalReturn: 0,
    );
    addTearDown(version.close);
    final requested = <String>[];
    expect(
      NativeOwnerApi.tryResolve(
        symbol: (name) {
          requested.add(name);
          return version.nativeFunction;
        },
      ),
      isNull,
    );
    expect(requested, ['llama_dart_owner_api_version']);
  });

  const required = [
    'llama_dart_owner_create',
    'llama_dart_owner_activate',
    'llama_dart_owner_release',
    'llama_dart_owner_abandon',
    'llama_dart_owner_track',
    'llama_dart_owner_untrack',
    'llama_dart_owner_model_load_from_file',
    'llama_dart_owner_init_from_model',
    'llama_dart_owner_mtmd_init_from_file',
  ];
  for (final missing in required) {
    test('partial runtime missing $missing never yields a usable owner API', () {
      final version = NativeCallable<Uint32 Function()>.isolateLocal(
        () => 1,
        exceptionalReturn: 0,
      );
      addTearDown(version.close);
      final requested = <String>[];
      expect(
        NativeOwnerApi.tryResolve(
          symbol: (name) {
            requested.add(name);
            if (name == missing) throw ArgumentError('Missing $name');
            // Only version is invoked during resolution. Other addresses are
            // converted to callables but are never called by this rejected probe.
            return version.nativeFunction;
          },
        ),
        isNull,
      );
      expect(requested, contains(missing));
    });
  }

  test('a lookup defect is not misreported as an unsupported old artifact', () {
    expect(
      () => NativeOwnerApi.tryResolve(
        symbol: (_) {
          throw StateError('Resolver defect');
        },
      ),
      throwsStateError,
    );
  });
}
