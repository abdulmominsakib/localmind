import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:code_assets/code_assets.dart' as code_assets;
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;

import 'hook_core_version.dart';

/// A throwaway package root for the build hook.
///
/// The hook caches bundles under `<package root>/.dart_tool/llamadart`, and
/// `testCodeBuildHook` takes the package root from [Directory.current]. Hook
/// tests that built in this checkout would leave their fake bundles in the
/// cache that real builds reuse, so they build here instead.
class HookProjectRoot {
  HookProjectRoot._(this._coreVersion, this._root);

  /// Describes a root holding only the `pubspec.yaml` the hook reads, declaring
  /// [coreVersion] or, when `null`, this checkout's core version.
  ///
  /// Only the path is chosen here. The directory appears on first use of
  /// [directory] or a build, so a test file whose tests are all filtered out
  /// leaves nothing behind. Paths are handed out before the directory exists,
  /// so creating it claims the name exclusively and fails on a collision
  /// rather than sharing a root.
  factory HookProjectRoot.create({String? coreVersion}) {
    final temp = Directory.systemTemp.resolveSymbolicLinksSync();
    final random = Random.secure();
    final suffix = List.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(36),
    ).join();
    return HookProjectRoot._(
      coreVersion,
      Directory(path.join(temp, 'hook_project_$suffix')),
    );
  }

  final String? _coreVersion;
  final Directory _root;
  bool _created = false;

  /// The package root, and the working directory the hook sees.
  Directory get directory {
    if (!_created) {
      File(path.join(_root.path, 'pubspec.yaml'))
        ..createSync(recursive: true, exclusive: true)
        ..writeAsStringSync(
          'name: llamadart\n'
          'version: ${_coreVersion ?? readCheckoutCoreVersion()}\n',
        );
      _created = true;
    }
    return _root;
  }

  /// The absolute path of [relative] below the package root.
  String resolve(String relative) => path.join(_root.path, relative);

  /// Runs [body] with [Directory.current] at the package root.
  Future<T> run<T>(Future<T> Function() body) =>
      IOOverrides.runZoned(body, getCurrentDirectory: () => directory);

  /// Removes the package root if it was ever created.
  void delete() {
    if (_root.existsSync()) _root.deleteSync(recursive: true);
    _created = false;
  }

  /// [code_assets.testCodeBuildHook] with its package root at [directory].
  Future<void> testCodeBuildHook({
    required FutureOr<void> Function(List<String> arguments) mainMethod,
    required FutureOr<void> Function(BuildInput, BuildOutput) check,
    code_assets.Architecture? targetArchitecture,
    code_assets.OS? targetOS,
    code_assets.IOSSdk? targetIOSSdk = code_assets.IOSSdk.iPhoneOS,
    int? targetAndroidNdkApi = 30,
    PackageUserDefines? userDefines,
  }) => run(
    () => code_assets.testCodeBuildHook(
      mainMethod: mainMethod,
      check: check,
      targetArchitecture: targetArchitecture,
      targetOS: targetOS,
      targetIOSSdk: targetIOSSdk,
      targetAndroidNdkApi: targetAndroidNdkApi,
      userDefines: userDefines,
    ),
  );
}
