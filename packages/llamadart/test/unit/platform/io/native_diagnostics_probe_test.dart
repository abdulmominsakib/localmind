@TestOn('vm')
library;

import 'dart:convert';

import 'package:llamadart/src/platform/io/native_diagnostics.dart';
import 'package:llamadart/src/platform/io/native_diagnostics_probe.dart';
import 'package:test/test.dart';

class FakeLibrary implements NativeDiagnosticLibrary {
  final List<String> calls = [];
  String? missing;
  int tts = 1;
  int callback = 2;
  int finish = 1;
  @override
  bool hasSymbol(String name) {
    calls.add('symbol:$name');
    return name != missing;
  }

  @override
  int marker(String name) {
    calls.add('marker:$name');
    return switch (name) {
      'llama_dart_tts_api_version' => tts,
      'stream_proxy_callback_abi_version' => callback,
      'stream_proxy_finish_reason_abi_version' => finish,
      _ => throw StateError('Unexpected native call: $name'),
    };
  }
}

void main() {
  const target = NativeDiagnosticTarget('/primary', '/wrapper', ['/companion']);
  test(
    'opens only declared files in order and calls only static ABI markers',
    () {
      for (final runtime in nativeDiagnosticRuntimes) {
        final library = FakeLibrary();
        final opened = <String>[];
        final phases = <String>[];
        final report = probeNativeDiagnostic(
          runtime,
          target,
          exists: (_) => true,
          open: (file) {
            opened.add(file);
            return library;
          },
          onPhase: phases.add,
        );
        expect(opened, ['/companion', '/primary', '/wrapper']);
        expect(report['code'], 'SURFACE_OBSERVED');
        expect(phases, ['open', 'symbols', 'abi', 'complete']);
        expect(
          library.calls.where((c) => c.startsWith('marker:')).toList(),
          switch (runtime) {
            'llama_cpp' => ['marker:llama_dart_tts_api_version'],
            'litert_lm' => [
              'marker:stream_proxy_callback_abi_version',
              'marker:stream_proxy_finish_reason_abi_version',
            ],
            _ => <String>[],
          },
        );
        expect(report['inference'], 'not_checked');
      }
    },
  );
  test(
    'missing files and symbols stop before marker/engine initialization',
    () {
      var opened = false;
      expect(
        probeNativeDiagnostic(
          'llama_cpp',
          target,
          exists: (_) => false,
          open: (_) {
            opened = true;
            return FakeLibrary();
          },
        )['code'],
        'ARTIFACT_MISSING',
      );
      expect(opened, isFalse);
      final library = FakeLibrary()..missing = 'llama_decode';
      expect(
        probeNativeDiagnostic(
          'llama_cpp',
          target,
          exists: (_) => true,
          open: (_) => library,
        )['code'],
        'SYMBOL_MISSING',
      );
      expect(library.calls.where((c) => c.startsWith('marker:')), isEmpty);
    },
  );
  test(
    'unknown marker versions fail their surface without inventing release identity',
    () {
      for (final runtime in ['llama_cpp', 'litert_lm']) {
        final library = FakeLibrary()
          ..tts = 999
          ..callback = 999;
        final report = probeNativeDiagnostic(
          runtime,
          target,
          exists: (_) => true,
          open: (_) => library,
        );
        expect(report['code'], 'ABI_UNKNOWN');
        expect(report['loaded_release'], 'unknown');
        expect(jsonEncode(report), isNot(contains('999')));
      }
    },
  );
  test(
    'loader diagnostics retain neither dependency names nor secret symbols',
    () {
      for (final (error, code) in [
        (
          'Library not loaded: /Users/private-user/PRIVATE_TOKEN.dylib',
          'DEPENDENCY_UNAVAILABLE',
        ),
        ('wrong ELF class: PRIVATE_TOKEN', 'BINARY_INCOMPATIBLE'),
        ('undefined symbol: PRIVATE_TOKEN', 'LOADER_FAILED'),
        ('https://private.invalid/?token=PRIVATE_TOKEN', 'LOADER_FAILED'),
      ]) {
        final result = probeNativeDiagnostic(
          'llama_cpp',
          target,
          exists: (_) => true,
          open: (_) => throw ArgumentError(error),
        );
        expect(result['code'], code);
        expect(jsonEncode(result), isNot(contains('PRIVATE_TOKEN')));
        expect(jsonEncode(result), isNot(contains('private-user')));
      }
    },
  );
  test('phase IPC failure is not mislabeled as a native loader failure', () {
    expect(
      () => probeNativeDiagnostic(
        'llama_cpp',
        target,
        exists: (_) => true,
        open: (_) => FakeLibrary(),
        onPhase: (_) => throw StateError('PRIVATE_DIAGNOSTIC_TOKEN'),
      ),
      throwsException,
    );
  });
}
