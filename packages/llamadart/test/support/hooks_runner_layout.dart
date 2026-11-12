import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'hook_project_root.dart';

/// A pub resolution laid out the way `package:hooks_runner` hands it to a
/// build hook.
///
/// The runner keeps hook output in the `.dart_tool/` that holds
/// `package_config.json` and `package_graph.json`: `dartToolHooksRunner` is
/// `<.dart_tool>/hooks_runner/` (hooks_runner 1.5.0
/// `lib/src/package_layout/package_layout.dart:113-123`) and the shared output
/// directory is `shared/<package>/build/` below it
/// (`lib/src/build_runner/build_runner.dart:425-427`). A pub workspace has one
/// such `.dart_tool/`, at the workspace root, for all of its members.
class HooksRunnerLayout {
  HooksRunnerLayout._(this.root);

  /// The application, or the pub workspace root.
  final Directory root;

  /// The pubspec the runner reads `hooks.user_defines` from.
  File get pubspec => File.fromUri(root.uri.resolve('pubspec.yaml'));

  /// The resolved graph pub writes next to `package_config.json`.
  File get packageGraph =>
      File.fromUri(root.uri.resolve('.dart_tool/package_graph.json'));

  /// Creates a resolution whose [roots] are the application, or every pub
  /// workspace member including the workspace root. pub records
  /// [devDependencies] for roots only.
  static Future<HooksRunnerLayout> create({
    required List<String> roots,
    required Map<String, List<String>> dependencies,
    Map<String, List<String>> devDependencies = const {},
    String pubspec = 'name: app\n',
  }) async {
    final temp = await Directory.systemTemp.createTemp('hooks-runner-layout-');
    final layout = HooksRunnerLayout._(
      Directory(await temp.resolveSymbolicLinks()),
    );
    await layout.pubspec.writeAsString(pubspec);
    await layout.packageGraph.parent.create();
    await layout.packageGraph.writeAsString(
      jsonEncode({
        'roots': roots,
        'packages': [
          for (final MapEntry(key: name, value: direct) in dependencies.entries)
            {
              'name': name,
              'version': '1.0.0',
              'dependencies': direct,
              if (roots.contains(name))
                'devDependencies': devDependencies[name] ?? const <String>[],
            },
        ],
        'configVersion': 1,
      }),
    );
    return layout;
  }

  /// Runs [hookMain] with the shared output directory the runner assigns.
  Future<void> run(
    FutureOr<void> Function(List<String> arguments) hookMain,
    List<String> arguments,
  ) async {
    final input = File(arguments.single.substring('--config='.length));
    final json = jsonDecode(await input.readAsString()) as Map<String, dynamic>;
    final shared = Directory.fromUri(
      root.uri.resolve(
        '.dart_tool/hooks_runner/shared/${json['package_name']}/build/',
      ),
    );
    await shared.create(recursive: true);
    json['out_dir_shared'] = shared.path;
    await input.writeAsString(jsonEncode(json));
    await hookMain(arguments);
  }

  /// User defines as the runner passes them: read from [pubspec], and without
  /// a source when it defines none for the package
  /// (`lib/src/build_runner/build_runner.dart:1223-1232`).
  PackageUserDefines userDefines([Map<String, Object?>? defines]) =>
      PackageUserDefines(
        workspacePubspec: defines == null
            ? null
            : PackageUserDefinesSource(defines: defines, basePath: pubspec.uri),
      );

  /// Removes the resolution.
  Future<void> delete() => root.delete(recursive: true);
}

/// The shape of the `DenisovAV/flutter_edge_ai` repository: a workspace root
/// that depends on no engine, and members that do.
Future<HooksRunnerLayout> flutterEdgeAiWorkspace() => HooksRunnerLayout.create(
  roots: [
    'workspace',
    'app',
    'flutter_edge_ai_llama',
    'flutter_edge_ai_litertlm',
  ],
  dependencies: {
    'workspace': [],
    'app': ['flutter_edge_ai_llama', 'flutter_edge_ai_litertlm'],
    'flutter_edge_ai_llama': ['llamadart'],
    'flutter_edge_ai_litertlm': [],
    'llamadart': [],
    'melos': [],
  },
  devDependencies: {
    'workspace': ['melos'],
  },
  pubspec:
      'name: workspace\n'
      'workspace: [app, flutter_edge_ai_llama, flutter_edge_ai_litertlm]\n'
      'dev_dependencies:\n'
      '  melos: any\n',
);

/// A workspace in which no package is a Flutter Edge AI engine.
Future<HooksRunnerLayout> workspaceWithoutFlutterEdgeAi() =>
    HooksRunnerLayout.create(
      roots: ['workspace', 'app', 'other'],
      dependencies: {
        'workspace': [],
        'app': ['llamadart'],
        'other': ['llamadart'],
        'llamadart': [],
      },
      pubspec: 'name: workspace\nworkspace: [app, other]\n',
    );

/// What one hook run reported: code asset ids mapped to their file names,
/// hook dependencies, and warnings logged.
typedef HookRun = ({
  Map<String, String> assets,
  List<Uri> dependencies,
  List<String> warnings,
});

/// Runs [hookMain] for one target inside [layout] when given, with the package
/// root at [project].
Future<HookRun> runCodeBuildHook({
  required FutureOr<void> Function(List<String> arguments) hookMain,
  required OS targetOS,
  required Architecture targetArchitecture,
  IOSSdk? targetIOSSdk,
  required HookProjectRoot project,
  HooksRunnerLayout? layout,
  PackageUserDefines? userDefines,
}) async {
  final warnings = <String>[];
  final subscription = Logger.root.onRecord.listen((record) {
    if (record.level >= Level.WARNING) warnings.add(record.message);
  });
  late final Map<String, String> assets;
  late final List<Uri> dependencies;
  try {
    await (project.testCodeBuildHook)(
      mainMethod: layout == null
          ? hookMain
          : (arguments) => layout.run(hookMain, arguments),
      targetOS: targetOS,
      targetArchitecture: targetArchitecture,
      targetIOSSdk: targetIOSSdk,
      userDefines: userDefines,
      check: (_, output) {
        assets = {
          for (final asset
              in output.assets.encodedAssets
                  .where((asset) => asset.isCodeAsset)
                  .map((asset) => asset.asCodeAsset))
            asset.id: path.basename(asset.file?.toFilePath() ?? ''),
        };
        dependencies = output.dependencies;
      },
    );
  } finally {
    await subscription.cancel();
  }
  return (assets: assets, dependencies: dependencies, warnings: warnings);
}

/// Expects a target's emitted assets to follow the resolved graph for
/// LiteRT-LM only: a workspace without Flutter Edge AI emits what a build with
/// no resolved graph does, and [flutterEdgeAiWorkspace] drops exactly
/// [liteRtLmLibraries].
Future<void> expectOnlyLiteRtLmFollowsResolvedGraph({
  required FutureOr<void> Function(List<String> arguments) hookMain,
  required OS targetOS,
  required Architecture targetArchitecture,
  required List<String> liteRtLmLibraries,
  required HookProjectRoot project,
}) async {
  final plain = await workspaceWithoutFlutterEdgeAi();
  addTearDown(plain.delete);
  final edgeAi = await flutterEdgeAiWorkspace();
  addTearDown(edgeAi.delete);
  Future<HookRun> run([HooksRunnerLayout? layout]) => runCodeBuildHook(
    hookMain: hookMain,
    targetOS: targetOS,
    targetArchitecture: targetArchitecture,
    layout: layout,
    project: project,
    userDefines: layout?.userDefines(),
  );

  final unresolved = await run();
  expect(unresolved.assets.values, containsAll(liteRtLmLibraries));
  final withoutEdgeAi = await run(plain);
  expect(withoutEdgeAi.assets, unresolved.assets);
  expect(
    withoutEdgeAi.warnings,
    unresolved.warnings.where((warning) => !warning.contains('Edge AI')),
  );
  expect((await run(edgeAi)).assets, {
    for (final MapEntry(key: id, value: name) in unresolved.assets.entries)
      if (!liteRtLmLibraries.contains(name)) id: name,
  });
}
