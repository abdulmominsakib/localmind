import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../backends/litert_lm/litert_lm_runtime.dart';
import 'native_diagnostics.dart';

/// The macOS LiteRT-LM runtime that the build hook keeps in its own cache
/// under the llamadart root in [packageConfig] instead of declaring it as code
/// assets, found with the runtime's own cache resolution.
///
/// [packageConfig] is read like the manifest: a bounded regular file, never
/// through a link. `LLAMADART_LITERT_LM_LIB_DIR` is not applied: the setup
/// report flags overrides separately, and this target names only the hook
/// cache.
NativeDiagnosticTarget? nativeDiagnosticLiteRtLmHookCacheTarget(
  File packageConfig,
  String abi,
) {
  if (abi != Abi.macosArm64.toString()) return null;
  final String contents;
  try {
    contents = readNativeDiagnosticFile(packageConfig, 256 * 1024);
  } on Object {
    return null;
  }
  final roots = liteRtLmPackageRootsFromPackageConfig(
    packageConfig,
    contents: contents,
  );
  if (roots.isEmpty) return null;
  final directory = liteRtLmResolveRuntimeDirectoryForAbi(
    Abi.macosArm64,
    libDirOverride: null,
    executablePath: Platform.resolvedExecutable,
    searchRoots: () => roots.map(Directory.new),
    cApiV1: true,
  );
  if (directory == null) return null;
  final primary = liteRtLmPrimaryLibraryForAbi(Abi.macosArm64)!;
  String file(String name) =>
      path.normalize(path.join(directory.absolute.path, name));
  return NativeDiagnosticTarget(file(primary), file(primary), [
    for (final library in liteRtLmMacOsRequiredLibrariesForAbi(
      Abi.macosArm64,
      cApiV1: true,
    ))
      if (library != primary) file(library),
  ]);
}
