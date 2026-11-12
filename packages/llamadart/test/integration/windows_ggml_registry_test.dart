@TestOn('windows')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:mirrors';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/llama_cpp_service.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

@Native<Size Function()>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_reg_count',
)
external int _assetRegistryCount();

void main() {
  test('an external module directory does not open another ggml registry', () {
    final directory = Directory.systemTemp.createTempSync('ggml-registry-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final nativeDirectory =
        LlamaCppService.resolveWindowsBackendModuleDirectory(
          resolvedExecutablePath: Platform.resolvedExecutable,
          currentDirectoryPath: Directory.current.path,
          environment: const {},
        )!;
    for (final name in ['ggml.dll', 'ggml-base.dll']) {
      File(
        path.join(nativeDirectory, name),
      ).copySync(path.join(directory.path, name));
    }
    expect(File(path.join(directory.path, 'ggml.dll')).existsSync(), isTrue);
    LlamaCppService().initializeBackend();
    final service = LlamaCppService();
    final mirror = reflect(service);
    final library = mirror.type.owner as LibraryMirror;
    Symbol private(String name) => MirrorSystem.getSymbol(name, library);
    mirror.setField(private('_backendModuleDirectory'), directory.path);
    mirror.invoke(private('_resolveGgmlFallbackFunctions'), const []);
    final count =
        mirror.getField(private('_ggmlBackendRegCountFallback')).reflectee
            as int Function();
    expect(count(), greaterThan(0));
    expect(count(), _assetRegistryCount());

    // GetModuleHandleW observes existing mappings without loading the copy.
    final getModuleHandle = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf16>),
          Pointer<Void> Function(Pointer<Utf16>)
        >('GetModuleHandleW');
    final externalGgml = path.join(directory.path, 'ggml.dll').toNativeUtf16();
    try {
      expect(
        getModuleHandle(externalGgml),
        nullptr,
        reason: 'backend overrides must reuse the hook registry',
      );
    } finally {
      malloc.free(externalGgml);
    }
  });
}
