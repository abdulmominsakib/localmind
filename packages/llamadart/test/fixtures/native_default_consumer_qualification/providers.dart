import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
// This private observer needs the generated @Native declaration; the public
// conditional entrypoint defaults to FFI-free stubs during source analysis.
import 'package:llamadart/src/backends/llama_cpp/bindings.dart' as bindings;

import 'passive_modules.dart' as windows;

final class DlInfo extends Struct {
  external Pointer<Utf8> filename;
  external Pointer<Void> imageBase;
  external Pointer<Utf8> symbolName;
  external Pointer<Void> symbolAddress;
}

@Native<Size Function()>(
  assetId: 'package:llamadart/llamadart',
  symbol: 'ggml_backend_reg_count',
)
external int hookRegistryCount();

bool nativeName(String path) => RegExp(
  r'^(?:lib)?(?:llama(?:dart)?|ggml|mtmd)(?:[-_.].*)?\.(?:dll|dylib)$',
  caseSensitive: false,
).hasMatch(path.replaceAll(r'\', '/').split('/').last);

Map<String, Object?> owner(Pointer<Void> address) {
  if (address.address == 0) throw StateError('null symbol address');
  final process = DynamicLibrary.process();
  if (Platform.isWindows) {
    final lookup = process
        .lookupFunction<
          Int32 Function(Uint32, Pointer<Void>, Pointer<Pointer<Void>>),
          int Function(int, Pointer<Void>, Pointer<Pointer<Void>>)
        >('GetModuleHandleExW');
    final filename = process
        .lookupFunction<
          Uint32 Function(Pointer<Void>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Void>, Pointer<Utf16>, int)
        >('GetModuleFileNameW');
    final handle = calloc<Pointer<Void>>();
    final name = calloc<Uint16>(32768).cast<Utf16>();
    try {
      if (lookup(6, address, handle) == 0) {
        throw StateError('symbol owner absent');
      }
      final length = filename(handle.value, name, 32768);
      if (length == 0 || length >= 32768) throw StateError('owner path absent');
      return {
        'address': address.address,
        'ownerBase': handle.value.address,
        'ownerPath': name.toDartString(length: length),
      };
    } finally {
      calloc.free(handle);
      calloc.free(name);
    }
  }
  final lookup = process
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<DlInfo>),
        int Function(Pointer<Void>, Pointer<DlInfo>)
      >('dladdr');
  final info = calloc<DlInfo>();
  try {
    if (lookup(address, info) == 0 || info.ref.filename == nullptr) {
      throw StateError('dladdr owner absent');
    }
    return {
      'address': address.address,
      'ownerBase': info.ref.imageBase.address,
      'ownerPath': File(info.ref.filename.toDartString()).absolute.path,
    };
  } finally {
    calloc.free(info);
  }
}

Future<List<Map<String, Object?>>> macSnapshot(String checkpoint) async {
  final process = DynamicLibrary.process();
  final count = process.lookupFunction<Uint32 Function(), int Function()>(
    '_dyld_image_count',
  );
  final name = process
      .lookupFunction<
        Pointer<Utf8> Function(Uint32),
        Pointer<Utf8> Function(int)
      >('_dyld_get_image_name');
  final header = process
      .lookupFunction<
        Pointer<Void> Function(Uint32),
        Pointer<Void> Function(int)
      >('_dyld_get_image_header');
  final images = <(String, int)>[];
  final length = count();
  for (var index = 0; index < length; index++) {
    final pointer = name(index);
    if (pointer == nullptr) throw StateError('incomplete dyld map');
    final path = File(pointer.toDartString()).absolute.path;
    if (nativeName(path)) images.add((path, header(index).address));
  }
  final observations = <Map<String, Object?>>[];
  for (final image in images) {
    final bytes = File(image.$1).readAsBytesSync();
    // Opening only a path in the already-recorded resident map cannot select
    // a missing runtime. Address ownership remains independently checked.
    final library = DynamicLibrary.open(image.$1);
    final exports = <Map<String, Object?>>[];
    for (final symbol in [
      'ggml_backend_reg_count',
      'llama_model_load_from_file',
      'llama_dart_model_load_from_file',
      'llama_dart_speculative_need_embd_nextn',
    ]) {
      if (library.providesSymbol(symbol)) {
        final actual = owner(library.lookup<Void>(symbol));
        if (actual['ownerPath'] == image.$1) {
          exports.add({'symbol': symbol, ...actual});
        }
      }
    }
    final row = <String, Object?>{
      'checkpoint': checkpoint,
      'modulePath': image.$1,
      'moduleBase': image.$2,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
      'exports': exports,
    };
    observations.add(row);
    stdout.writeln('PASSIVE_MODULE ${jsonEncode(row)}');
  }
  await stdout.flush();
  return observations;
}

Future<Map<String, Object?>> observe() async {
  final before = Platform.isWindows
      ? await windows.snapshot('after-public-model-outcome')
      : await macSnapshot('after-public-model-outcome');
  final wrappers = before
      .where(
        (row) => RegExp(
          r'[/\\](?:lib)?llamadart(?:-windows-x64)?\.(?:dll|dylib)$',
          caseSensitive: false,
        ).hasMatch(row['modulePath']! as String),
      )
      .toList();
  if (wrappers.length != 1) {
    throw StateError('unique resident wrapper required');
  }
  final wrapper = wrappers.single;
  final library = DynamicLibrary.open(wrapper['modulePath']! as String);
  const nextn = 'llama_dart_speculative_need_embd_nextn';
  if (!library.providesSymbol(nextn)) throw StateError('retained nextn absent');
  final pointer = library.lookup<NativeFunction<Bool Function(Pointer<Void>)>>(
    nextn,
  );
  final nextnOwner = owner(pointer.cast());
  final query = <String, Object?>{
    'wrapperPath': wrapper['modulePath'],
    'wrapperSha256': wrapper['sha256'],
    'hasNextn': true,
    'hasLegacyQuery': library.providesSymbol(
      'llama_dart_speculative_need_embd',
    ),
    'nextnNullFalse': !pointer.asFunction<bool Function(Pointer<Void>)>()(
      nullptr,
    ),
    'nextnAddress': pointer.address,
    'nextnOwnerBase': nextnOwner['ownerBase'],
    'nextnOwnerPath': nextnOwner['ownerPath'],
    'nextnOwnerSha256': sha256
        .convert(File(nextnOwner['ownerPath']! as String).readAsBytesSync())
        .toString(),
    'probeAfterPublicOutcome': true,
  };
  if (Platform.isWindows) {
    await windows.registryIdentity(before, 'success');
  } else {
    final address = Native.addressOf<NativeFunction<Size Function()>>(
      hookRegistryCount,
    );
    if (before.length != 1 ||
        !(wrapper['modulePath']! as String).endsWith('/libllamadart.dylib')) {
      throw StateError('consolidated Apple image required');
    }
    final exports = wrapper['exports']! as List<Map<String, Object?>>;
    final registry = exports
        .where((row) => row['symbol'] == 'ggml_backend_reg_count')
        .toList();
    if (registry.length != 1) {
      throw StateError('self-owned registry export required');
    }
    final registryOwner = owner(address.cast());
    final modelAddress =
        Native.addressOf<
          NativeFunction<
            Pointer<bindings.llama_model> Function(
              Pointer<Char>,
              bindings.llama_model_params,
            )
          >
        >(bindings.llama_dart_model_load_from_file);
    final modelOwner = owner(modelAddress.cast());
    Map<String, Object?> hashedOwner(Map<String, Object?> actual) => {
      ...actual,
      'sha256': sha256
          .convert(File(actual['ownerPath']! as String).readAsBytesSync())
          .toString(),
    };
    final primaryMatches =
        registry.single['address'] == address.address &&
        registryOwner['ownerPath'] == wrapper['modulePath'] &&
        registryOwner['ownerBase'] == wrapper['moduleBase'];
    stdout.writeln(
      'REGISTRY_IDENTITY ${jsonEncode({
        'runtimeLayout': 'consolidated-apple',
        'observerAfterFirstPassiveSnapshot': true,
        'codeAssetResolutionAndGetterPotentiallyLoadingOrInitializing': true,
        'codeAssetId': 'package:llamadart/llamadart',
        'codeAssetAddress': address.address,
        'codeAssetOwner': hashedOwner(registryOwner),
        'codeAssetProvider': registry,
        'primaryRegistryExport': registry.single,
        'primaryRegistryImports': <Map<String, Object?>>[],
        'modelCodeAsset': {'symbol': 'llama_dart_model_load_from_file', 'assetId': 'package:llamadart/llamadart', ...hashedOwner(modelOwner)},
        'distinctRegistryProviderBasesBefore': 1,
        'primaryMatchesCodeAsset': primaryMatches,
        'noUnintendedDuplicateRegistry': before.length == 1,
        'registryCountAfterOutcome': hookRegistryCount(),
      })}',
    );
    await macSnapshot('after-registry-observation');
  }
  return query;
}
