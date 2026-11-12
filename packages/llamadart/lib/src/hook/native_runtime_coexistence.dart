/// Keeps llamadart's LiteRT-LM runtime out of builds that also bundle a
/// Flutter Edge AI engine, for `hook/build.dart`.
///
/// User-facing docs: `website/docs/platforms/native-build-hooks.md`.
library;

import 'dart:convert';
import 'dart:io';

import 'native_bundle_config.dart';

const String _edgeAiLlama = 'flutter_edge_ai_llama';
const String _edgeAiLiteRtLm = 'flutter_edge_ai_litertlm';
const String _liteRtLmCompanion = 'llamadart_litert_lm_flutter';

/// Applies the Flutter Edge AI defaults to [selectedRuntimes] and rejects
/// two owners of the LiteRT-LM native libraries.
///
/// The build hook is not told which application is being built, and its
/// output is shared by every package resolved into the same `.dart_tool/`:
/// one application, or all members of a pub workspace. So the decision covers
/// every root of [packageGraph] (`.dart_tool/package_graph.json`) that
/// depends on [hookPackage], with that root's dev dependencies, which
/// `dart run`, `dart test` and non-release Flutter builds bundle too.
///
/// When such a root also reaches `flutter_edge_ai_llama` or
/// `flutter_edge_ai_litertlm`, an implied `litert_lm` is removed with a
/// [warn]. `flutter_edge_ai_litertlm` bundles the same libraries, so
/// [explicitLiteRtLm], or `llamadart_litert_lm_flutter` on an Apple target,
/// throws a [StateError] next to it.
///
/// A missing or unreadable [packageGraph] keeps [selectedRuntimes] with a
/// [warn]. pub writes the file and the hook runner reads it before any hook
/// runs, so one this function cannot read comes from a toolchain it does not
/// know, where failing would break builds that have no such engine.
/// [dependency] receives [packageGraph] when it is read.
List<String> selectConsumerNativeRuntimes({
  required File? packageGraph,
  required String hookPackage,
  required List<String> selectedRuntimes,
  required bool explicitLiteRtLm,
  required bool isAppleTarget,
  required void Function(Uri uri) dependency,
  required void Function(String message) warn,
}) {
  if (!selectedRuntimes.contains(nativeRuntimeLiteRtLm) && !isAppleTarget) {
    return selectedRuntimes;
  }
  final graphPath = packageGraph?.path ?? '.dart_tool/package_graph.json';
  final define = 'hooks.user_defines.$hookPackage.$nativeRuntimesUserDefineKey';
  const pubspec = 'the application or pub workspace root pubspec.yaml';

  var problem = 'was not found';
  Set<String>? bundled;
  if (packageGraph != null && packageGraph.existsSync()) {
    try {
      dependency(packageGraph.uri);
      bundled = _packagesBundledWith(
        hookPackage,
        jsonDecode(packageGraph.readAsStringSync()),
      );
    } on FormatException {
      problem = 'is malformed';
    } on FileSystemException {
      problem = 'could not be read';
    }
  }
  if (bundled == null) {
    warn(
      'Cannot check for Flutter Edge AI LiteRT-LM conflicts: the resolved '
      'package graph $graphPath $problem. Keeping '
      '${selectedRuntimes.join(', ')}. If the build also uses $_edgeAiLlama '
      'or $_edgeAiLiteRtLm, set $define: [$nativeRuntimeLlamaCpp] in $pubspec '
      'and rerun pub get.',
    );
    return selectedRuntimes;
  }

  final selectsLiteRtLm =
      explicitLiteRtLm ||
      (isAppleTarget && bundled.contains(_liteRtLmCompanion));
  if (selectsLiteRtLm && bundled.contains(_edgeAiLiteRtLm)) {
    throw StateError(
      'Conflicting LiteRT-LM runtimes: $_edgeAiLiteRtLm owns the same native '
      'libraries as the $hookPackage LiteRT-LM runtime, and $graphPath '
      'resolves both into builds that share this hook output. Set $define: '
      '[$nativeRuntimeLlamaCpp] in $pubspec, remove $_liteRtLmCompanion if '
      'present, then rerun pub get and the build.',
    );
  }
  final engines = [_edgeAiLlama, _edgeAiLiteRtLm].where(bundled.contains);
  if (selectsLiteRtLm ||
      engines.isEmpty ||
      !selectedRuntimes.contains(nativeRuntimeLiteRtLm)) {
    return selectedRuntimes;
  }
  final recovery = bundled.contains(_edgeAiLiteRtLm)
      ? '$_edgeAiLiteRtLm owns the same native libraries, so both cannot be '
            'bundled.'
      : 'To keep it, name $nativeRuntimeLiteRtLm in $define in $pubspec.';
  warn(
    'Leaving the LiteRT-LM runtime out: ${engines.join(' and ')} resolved '
    'next to $hookPackage in $graphPath, and every package resolved there '
    'shares this hook output. $recovery',
  );
  return selectedRuntimes
      .where((runtime) => runtime != nativeRuntimeLiteRtLm)
      .toList(growable: false);
}

/// Every package some root of the decoded `package_graph.json` [graph] builds
/// together with [hookPackage]. Throws [FormatException] on another shape.
Set<String> _packagesBundledWith(String hookPackage, Object? graph) {
  if (graph case {
    'roots': final List<Object?> roots,
    'packages': final List<Object?> packages,
  }) {
    final dependencies = <String, List<Object?>>{};
    final devDependencies = <String, List<Object?>>{};
    for (final package in packages) {
      if (package case {
        'name': final String name,
        'dependencies': final List<Object?> direct,
      }) {
        dependencies[name] = direct;
        if (package['devDependencies'] case final List<Object?> dev) {
          devDependencies[name] = dev;
        }
      } else {
        throw const FormatException();
      }
    }
    final bundled = <String>{};
    for (final root in roots) {
      final closure = <Object?>{};
      final pending = [root, ...?devDependencies[root]];
      while (pending.isNotEmpty) {
        final name = pending.removeLast();
        if (closure.add(name)) pending.addAll(dependencies[name] ?? const []);
      }
      if (closure.contains(hookPackage)) {
        bundled.addAll(closure.whereType<String>());
      }
    }
    return bundled;
  }
  throw const FormatException();
}
