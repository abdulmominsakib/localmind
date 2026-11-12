import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

Future<void> emitPassiveSnapshot(
  List<Map<String, Object?>> observations,
) async {
  for (final observation in observations) {
    stdout.writeln('PASSIVE_MODULE ${jsonEncode(observation)}');
  }
  // A flush owns the sink until its future completes.
  await stdout.flush();
}

// Inspect existing handles only. A missing resident Windows API is a diagnostic
// failure, never permission to load another DLL or change the stock control.
Future<List<Map<String, Object?>>> snapshot(
  String checkpoint, {
  bool includeCounts = false,
}) async {
  final observations = <Map<String, Object?>>[];
  if (!checkpoint.startsWith('after-')) {
    throw StateError(
      'Observer FFI is allowed only after a recorded model outcome',
    );
  }
  final process = DynamicLibrary.process();
  final current = process
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetCurrentProcess',
      );
  final enumerate = process
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          Uint32,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Void>,
          Pointer<Pointer<Void>>,
          int,
          Pointer<Uint32>,
        )
      >('K32EnumProcessModules');
  final filename = process
      .lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Utf16>, Uint32),
        int Function(Pointer<Void>, Pointer<Utf16>, int)
      >('GetModuleFileNameW');
  final proc = process
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
      >('GetProcAddress');
  final owner = process
      .lookupFunction<
        Int32 Function(Uint32, Pointer<Void>, Pointer<Pointer<Void>>),
        int Function(int, Pointer<Void>, Pointer<Pointer<Void>>)
      >('GetModuleHandleExW');
  final handles = calloc<Pointer<Void>>(4096);
  final needed = calloc<Uint32>();
  final buffer = calloc<Uint16>(32768).cast<Utf16>();
  final own = calloc<Pointer<Void>>();
  String path(Pointer<Void> module) {
    final n = filename(module, buffer, 32768);
    if (n == 0 || n >= 32768) throw StateError('module path unavailable');
    return buffer.toDartString(length: n);
  }

  Map<String, Object?> address(Pointer<Void> pointer) {
    if (pointer.address == 0) return {'address': 0};
    if (owner(6, pointer, own) == 0) {
      throw StateError('address owner unavailable');
    }
    return {
      'address': pointer.address,
      'ownerBase': own.value.address,
      'ownerPath': path(own.value),
      'rva': pointer.address - own.value.address,
    };
  }

  try {
    if (enumerate(current(), handles, 4096 * sizeOf<Pointer<Void>>(), needed) ==
            0 ||
        needed.value > 4096 * sizeOf<Pointer<Void>>()) {
      throw StateError('module enumeration incomplete');
    }
    for (var i = 0; i < needed.value ~/ sizeOf<Pointer<Void>>(); i++) {
      final module = handles[i];
      final name = path(module);
      final bytes = File(name).readAsBytesSync();
      final disk = ByteData.sublistView(bytes);
      if (bytes.length < 64 || disk.getUint16(0, Endian.little) != 0x5a4d) {
        throw StateError('module has invalid MZ header');
      }
      final pe = disk.getUint32(0x3c, Endian.little);
      if (pe + 144 > bytes.length ||
          disk.getUint32(pe, Endian.little) != 0x4550 ||
          disk.getUint16(pe + 24, Endian.little) != 0x20b) {
        throw StateError('module has invalid PE64 header');
      }
      final exports = <Map<String, Object?>>[];
      for (final symbol in [
        'ggml_backend_reg_count',
        'ggml_backend_dev_count',
        'ggml_backend_reg_get',
        'ggml_backend_reg_name',
        'llama_model_load_from_file',
        'sd_dart_llama_model_load_from_file',
        'llama_dart_model_load_from_file',
        'exit',
      ]) {
        final encoded = symbol.toNativeUtf8();
        final pointer = proc(module, encoded);
        calloc.free(encoded);
        if (pointer.address == 0) continue;
        final row = <String, Object?>{'symbol': symbol, ...address(pointer)};
        if (includeCounts &&
            (symbol == 'ggml_backend_reg_count' ||
                symbol == 'ggml_backend_dev_count')) {
          row['count'] = pointer
              .cast<NativeFunction<Size Function()>>()
              .asFunction<int Function()>()();
        }
        exports.add(row);
      }
      final registryNames = <String>[];
      Pointer<Void> existingExport(String symbol) {
        final encoded = symbol.toNativeUtf8();
        try {
          return proc(module, encoded);
        } finally {
          calloc.free(encoded);
        }
      }

      final countAddress = existingExport('ggml_backend_reg_count');
      final getAddress = existingExport('ggml_backend_reg_get');
      final nameAddress = existingExport('ggml_backend_reg_name');
      if (includeCounts &&
          countAddress.address != 0 &&
          getAddress.address != 0 &&
          nameAddress.address != 0) {
        final count = countAddress
            .cast<NativeFunction<Size Function()>>()
            .asFunction<int Function()>()();
        if (count > 1024) throw StateError('unbounded registry count');
        final get = getAddress
            .cast<NativeFunction<Pointer<Void> Function(Size)>>()
            .asFunction<Pointer<Void> Function(int)>();
        final regName = nameAddress
            .cast<NativeFunction<Pointer<Utf8> Function(Pointer<Void>)>>()
            .asFunction<Pointer<Utf8> Function(Pointer<Void>)>();
        for (var r = 0; r < count; r++) {
          final reg = get(r);
          if (reg.address == 0) {
            throw StateError('registry disappeared during passive snapshot');
          }
          registryNames.add(regName(reg).toDartString());
        }
      }
      // Bound IAT reads to the already mapped image. This links a wrapper's
      // actual imported loader target to an owner without resolving/loading it.
      final imports = <Map<String, Object?>>[];
      if (name.toLowerCase().endsWith('llamadart.dll') ||
          name.toLowerCase().endsWith('llama.dll') ||
          name.toLowerCase().endsWith('ggml.dll') ||
          name.toLowerCase().endsWith('ggml-base.dll')) {
        final imageSize = disk.getUint32(pe + 24 + 56, Endian.little);
        final memory = ByteData.sublistView(
          module.cast<Uint8>().asTypedList(imageSize),
        );
        final importRva = memory.getUint32(pe + 24 + 112 + 8, Endian.little);
        String asciiAt(int rva) {
          final data = <int>[];
          while (rva < imageSize && data.length < 4096) {
            final c = memory.getUint8(rva++);
            if (c == 0) return ascii.decode(data);
            data.add(c);
          }
          throw StateError('invalid mapped import string');
        }

        if (importRva > 0) {
          for (var d = importRva; d + 20 <= imageSize; d += 20) {
            final original = memory.getUint32(d, Endian.little);
            final dll = memory.getUint32(d + 12, Endian.little);
            final first = memory.getUint32(d + 16, Endian.little);
            if (dll == 0) break;
            if (original == 0) {
              imports.add({
                'dll': asciiAt(dll),
                'unavailable': 'no original thunk',
              });
              continue;
            }
            for (
              var offset = 0;
              original + offset + 8 <= imageSize &&
                  first + offset + 8 <= imageSize;
              offset += 8
            ) {
              final thunk = memory.getUint64(original + offset, Endian.little);
              if (thunk == 0) break;
              if (thunk & 0x8000000000000000 != 0) continue;
              final symbol = asciiAt(thunk + 2);
              if (symbol.contains('ggml_backend_') ||
                  symbol.contains('llama_model_load')) {
                imports.add({
                  'dll': asciiAt(dll),
                  'symbol': symbol,
                  ...address(
                    Pointer<Void>.fromAddress(
                      memory.getUint64(first + offset, Endian.little),
                    ),
                  ),
                });
              }
            }
          }
        }
      }
      final observation = <String, Object?>{
        'checkpoint': checkpoint,
        'registryGettersCalled': includeCounts,
        'registryCountsPotentiallyInitializing': includeCounts,
        'observationScope':
            'post-outcome only; observer process lookup can first-touch OLE32; no pre-load state claim',
        'pid': pid,
        'moduleBase': module.address,
        'modulePath': name,
        'sha256': sha256.convert(bytes).toString(),
        'bytes': bytes.length,
        'machine': disk.getUint16(pe + 4, Endian.little),
        'exports': exports,
        'registryNames': registryNames,
        'imports': imports,
      };
      observations.add(observation);
    }
    await emitPassiveSnapshot(observations);
    return observations;
  } finally {
    calloc.free(handles);
    calloc.free(needed);
    calloc.free(buffer);
    calloc.free(own);
  }
}

@Native<Size Function()>(
  assetId: 'package:llamadart/ggml',
  symbol: 'ggml_backend_reg_count',
)
external int hookRegistryCount();

bool isPrimaryLlamaModule(String modulePath) =>
    modulePath.toLowerCase().endsWith(r'\llama.dll');

// First passive map is complete before this code-asset resolution or getter.
Future<void> registryIdentity(
  List<Map<String, Object?>> before,
  String outcome,
) async {
  final codeAsset = Native.addressOf<NativeFunction<Size Function()>>(
    hookRegistryCount,
  ).address;
  final providers = <Map<String, Object?>>[];
  final primary = <Map<String, Object?>>[];
  for (final module in before) {
    for (final export in module['exports']! as List<Map<String, Object?>>) {
      if (export['symbol'] == 'ggml_backend_reg_count') {
        providers.add({
          'modulePath': module['modulePath'],
          'sha256': module['sha256'],
          ...export,
        });
      }
    }
    if (isPrimaryLlamaModule(module['modulePath']! as String)) {
      for (final imported in module['imports']! as List<Map<String, Object?>>) {
        if (imported['symbol'] == 'ggml_backend_reg_count') {
          primary.add(imported);
        }
      }
    }
  }
  final matched = providers.where((p) => p['address'] == codeAsset).toList();
  final providerBases = providers.map((p) => p['ownerBase']).toSet();
  final matches =
      matched.length == 1 &&
      primary.length == 1 &&
      primary.single['address'] == codeAsset &&
      primary.single['ownerBase'] == matched.single['ownerBase'];
  final count = hookRegistryCount();
  print(
    'REGISTRY_IDENTITY ${jsonEncode({'outcome': outcome, 'observerAfterFirstPassiveSnapshot': true, 'codeAssetResolutionAndGetterPotentiallyLoadingOrInitializing': true, 'codeAssetId': 'package:llamadart/ggml', 'codeAssetAddress': codeAsset, 'codeAssetProvider': matched, 'primaryRegistryImports': primary, 'providersBeforeCodeAssetObservation': providers, 'distinctRegistryProviderBasesBefore': providerBases.length, 'primaryMatchesCodeAsset': matches, 'noUnintendedDuplicateRegistry': providerBases.length == 1, 'registryCountAfterOutcome': count})}',
  );
  await snapshot('after-registry-observation', includeCounts: true);
}
