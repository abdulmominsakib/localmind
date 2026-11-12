@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/hook/native_runtime_coexistence.dart';
import '../../../hook/build.dart' as build_hook;
import '../../support/hook_project_root.dart';
import '../../support/hooks_runner_layout.dart';

const _llama = 'flutter_edge_ai_llama';
const _owner = 'flutter_edge_ai_litertlm';
const _companion = 'llamadart_litert_lm_flutter';
const _both = ['llama_cpp', 'litert_lm'];
const _define = 'hooks.user_defines.llamadart.llamadart_native_runtimes';

void main() {
  final project = HookProjectRoot.create();
  tearDownAll(project.delete);
  late Directory scratch;
  late File graph;
  late List<String> warnings;
  late List<Uri> dependencies;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('runtime-owner-test-');
    graph = File.fromUri(scratch.uri.resolve('package_graph.json'));
    warnings = [];
    dependencies = [];
  });
  tearDown(() async => scratch.delete(recursive: true));

  void resolve(
    Map<String, List<String>> packages, {
    List<String> roots = const ['app'],
    Map<String, List<String>> devDependencies = const {},
  }) => graph.writeAsStringSync(
    jsonEncode({
      'roots': roots,
      'packages': [
        for (final MapEntry(key: name, value: direct) in packages.entries)
          {
            'name': name,
            'dependencies': direct,
            'devDependencies': ?devDependencies[name],
          },
      ],
    }),
  );

  List<String> check(
    List<String> runtimes, {
    bool explicit = false,
    bool apple = false,
    bool resolved = true,
  }) => selectConsumerNativeRuntimes(
    packageGraph: resolved ? graph : null,
    hookPackage: 'llamadart',
    selectedRuntimes: runtimes,
    explicitLiteRtLm: explicit,
    isAppleTarget: apple,
    dependency: dependencies.add,
    warn: warnings.add,
  );

  final throwsConflict = throwsA(
    isA<StateError>().having(
      (error) => error.message,
      'message',
      stringContainsInOrder([
        'Conflicting LiteRT-LM runtimes',
        _owner,
        '$_define: [llama_cpp]',
        _companion,
      ]),
    ),
  );

  test('an owner drops an implied LiteRT-LM and rejects a named one', () {
    resolve({
      'app': ['llamadart', _owner],
    });
    expect(check(_both), ['llama_cpp']);
    expect(warnings.single, stringContainsInOrder([_owner, graph.path]));
    expect(warnings.single, isNot(contains('To keep it')));
    expect(dependencies, [graph.uri]);
    expect(() => check(_both, explicit: true), throwsConflict);
    expect(() => check(['litert_lm'], explicit: true), throwsConflict);
  });

  test('a connector drops only an implied LiteRT-LM', () {
    resolve({
      'app': [_llama],
      _llama: ['llamadart'],
    });
    final all = ['llama_cpp', 'litert_lm', 'stable_diffusion'];
    expect(check(all), ['llama_cpp', 'stable_diffusion']);
    expect(all, ['llama_cpp', 'litert_lm', 'stable_diffusion']);
    expect(
      warnings.single,
      stringContainsInOrder([_llama, 'To keep it, name litert_lm in $_define']),
    );
    warnings.clear();
    expect(check(all, explicit: true), same(all));
    expect(warnings, isEmpty);
  });

  test('a build without LiteRT-LM off Apple never reads the graph', () {
    resolve({
      'app': ['llamadart', _owner, _companion],
    });
    final selected = ['llama_cpp'];
    expect(check(selected), same(selected));
    expect(dependencies, isEmpty);
    expect(warnings, isEmpty);
  });

  test('the Apple companion selects LiteRT-LM on Apple targets only', () {
    resolve({
      'app': ['llamadart', _owner, _companion],
    });
    for (final runtimes in [
      ['llama_cpp'],
      _both,
    ]) {
      expect(() => check(runtimes, apple: true), throwsConflict);
    }
    expect(check(_both), ['llama_cpp']);

    resolve({
      'app': [_llama, _companion],
      _llama: ['llamadart'],
    });
    expect(check(_both, apple: true), _both);
    expect(check(['litert_lm'], apple: true), ['litert_lm']);
    expect(check(_both), ['llama_cpp']);
  });

  test('every root that builds the hook package counts, and no other', () {
    resolve(
      {
        'workspace': [],
        'app': ['llamadart'],
        'other': [_owner],
        'tools': [_llama],
        _llama: [],
      },
      roots: ['workspace', 'app', 'other', 'tools'],
    );
    expect(check(_both), _both);
    expect(check(_both, explicit: true), _both);
    expect(warnings, isEmpty);

    resolve(
      {
        'workspace': [],
        'app': ['llamadart'],
        'other': ['helper'],
        'helper': ['llamadart', _owner],
      },
      roots: ['workspace', 'app', 'other'],
    );
    expect(check(_both), ['llama_cpp']);
    expect(() => check(_both, explicit: true), throwsConflict);
  });

  test('the hook package and an engine can themselves be roots', () {
    resolve({'llamadart': []}, roots: ['llamadart']);
    expect(check(_both), _both);
    resolve(
      {
        _llama: ['llamadart'],
      },
      roots: [_llama],
    );
    expect(check(_both), ['llama_cpp']);
  });

  test('dev dependencies count for the root that declares them only', () {
    resolve(
      {
        'app': ['llamadart'],
      },
      devDependencies: {
        'app': [_owner],
      },
    );
    expect(check(_both), ['llama_cpp']);
    expect(() => check(_both, explicit: true), throwsConflict);

    for (final roots in [
      ['app', 'other'],
      ['app'],
    ]) {
      resolve(
        {
          'app': ['llamadart', 'other'],
          'other': [],
        },
        roots: roots,
        devDependencies: {
          'other': [_owner],
        },
      );
      expect(check(_both), _both, reason: '$roots');
    }
  });

  test('a missing graph keeps the selection and says how to choose', () {
    for (final resolved in [false, true]) {
      warnings.clear();
      expect(check(_both, resolved: resolved), _both);
      expect(
        warnings.single,
        stringContainsInOrder([
          resolved ? graph.path : '.dart_tool/package_graph.json',
          'was not found',
          'Keeping llama_cpp, litert_lm',
          '$_define: [llama_cpp]',
        ]),
      );
    }
    expect(dependencies, isEmpty);
  });

  test('a malformed graph keeps the selection and names the file', () {
    final malformed = <Object>[
      '{"roots": ["app"], "packages": [ secret-token: broken',
      '[]',
      jsonEncode({'packages': <Object>[]}),
      jsonEncode({'roots': 'app', 'packages': <Object>[]}),
      jsonEncode({
        'roots': ['app'],
        'packages': {'app': <Object>[]},
      }),
      jsonEncode({
        'roots': ['app'],
        'packages': ['app'],
      }),
      jsonEncode({
        'roots': ['app'],
        'packages': [
          {
            'dependencies': [_owner],
          },
        ],
      }),
      jsonEncode({
        'roots': ['app'],
        'packages': [
          {'name': 'app', 'dependencies': _owner},
        ],
      }),
      [0xff, 0xfe, 0xfd],
    ];
    for (final content in malformed) {
      warnings.clear();
      content is String
          ? graph.writeAsStringSync(content)
          : graph.writeAsBytesSync(content as List<int>);
      expect(check(_both, explicit: true), _both, reason: '$content');
      expect(
        warnings.single,
        stringContainsInOrder([
          graph.path,
          content is String ? 'is malformed' : 'could not be read',
          '$_define: [llama_cpp]',
        ]),
        reason: '$content',
      );
      expect(warnings.single, isNot(contains('secret-token')));
    }
  });

  group('production hook', () {
    Future<void> expectConflict(
      HooksRunnerLayout layout, {
      required OS os,
      Object? runtimes,
    }) async {
      var emitted = false;
      await expectLater(
        project.testCodeBuildHook(
          mainMethod: (arguments) => layout.run(build_hook.main, arguments),
          targetOS: os,
          targetArchitecture: os == OS.linux || os == OS.windows
              ? Architecture.x64
              : Architecture.arm64,
          targetIOSSdk: os == OS.iOS ? IOSSdk.iPhoneOS : null,
          userDefines: layout.userDefines(
            runtimes == null ? null : {'llamadart_native_runtimes': runtimes},
          ),
          check: (_, _) => emitted = true,
        ),
        throwsA(
          predicate(
            (error) => '$error'.contains('Conflicting LiteRT-LM runtimes'),
          ),
        ),
      );
      expect(emitted, isFalse);
    }

    for (final os in [OS.linux, OS.windows, OS.android, OS.iOS, OS.macOS]) {
      test(
        'rejects a named LiteRT-LM beside a workspace owner on $os',
        () async {
          final layout = await flutterEdgeAiWorkspace();
          addTearDown(layout.delete);
          await expectConflict(layout, os: os, runtimes: _both);
        },
      );
    }

    test('rejects a named LiteRT-LM beside a standalone app owner', () async {
      final layout = await HooksRunnerLayout.create(
        roots: ['app'],
        dependencies: {
          'app': ['llamadart', _owner],
          _owner: [],
          'llamadart': [],
        },
      );
      addTearDown(layout.delete);
      await expectConflict(layout, os: OS.linux, runtimes: _both);
    });

    for (final runtimes in [
      null,
      ['llama_cpp'],
    ]) {
      test('rejects the Apple companion of a workspace member beside the '
          'owner, runtimes $runtimes', () async {
        final layout = await HooksRunnerLayout.create(
          roots: ['workspace', 'app'],
          dependencies: {
            'workspace': [],
            'app': ['flutter', _owner, _companion],
            _companion: ['llamadart'],
            'llamadart': [],
          },
          pubspec: 'name: workspace\nworkspace: [app]\n',
        );
        addTearDown(layout.delete);
        await expectConflict(layout, os: OS.iOS, runtimes: runtimes);
      });
    }

    test('a Flutter Apple app keeps its companion LiteRT-LM beside the '
        'connector and rejects it beside the owner', () async {
      Future<HooksRunnerLayout> app(String engine) async {
        final layout = await HooksRunnerLayout.create(
          roots: ['app'],
          dependencies: {
            'app': ['flutter', engine, _companion],
            engine: ['llamadart'],
            _companion: ['llamadart'],
            'llamadart': [],
          },
          pubspec:
              'name: app\n'
              'dependencies:\n'
              '  flutter:\n'
              '    sdk: flutter\n'
              '  $engine: any\n'
              '  $_companion: any\n',
        );
        addTearDown(layout.delete);
        return layout;
      }

      await expectConflict(await app(_owner), os: OS.iOS);
      final connector = await app(_llama);
      final run = await runCodeBuildHook(
        hookMain: build_hook.main,
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        targetIOSSdk: IOSSdk.iPhoneOS,
        layout: connector,
        project: project,
        userDefines: connector.userDefines(),
      );
      expect(run.assets, isEmpty);
      expect(run.dependencies, contains(connector.packageGraph.uri));
      expect(
        run.warnings.where((warning) => warning.contains('LiteRT-LM')),
        isEmpty,
      );
    });
  });
}
