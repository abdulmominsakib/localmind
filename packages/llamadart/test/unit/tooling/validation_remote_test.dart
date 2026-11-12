@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamadart/src/hook/native_bundle_config.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The root test uses the canonical private report policy without resolving the
// independent package; the command boundary remains a model-free spy.
// ignore: avoid_relative_lib_imports
import '../../../packages/llamadart_validation/lib/src/report.dart';
import '../../../tool/testing/validation/bundle.dart';
import '../../../tool/testing/validation/collect.dart';
import '../../../tool/testing/validation/process.dart';
import '../../../tool/testing/validation/remote.dart';
import '../../../tool/testing/validation/runtime_bundle.dart';

class PreparedReporterSpy {
  PreparedReporterSpy(Directory scratch)
    : repository = Directory(p.join(scratch.path, 'prepared-reporter')) {
    final package = Directory(
      p.join(repository.path, 'packages/llamadart_validation'),
    );
    Directory(p.join(package.path, 'lib')).createSync(recursive: true);
    File(p.join(package.path, '.dart_tool/package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'llamadart_validation',
              'rootUri': '../',
              'packageUri': 'lib/',
            },
          ],
        }),
      );
  }

  final Directory repository;
  int calls = 0;

  Future<CommandResult> execute(
    String executable,
    List<String> args, {
    String? directory,
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    calls++;
    final package = p.join(repository.path, 'packages/llamadart_validation');
    expect(executable, Platform.resolvedExecutable);
    expect(directory, package);
    expect(
      args.first,
      '--packages=${p.join(package, '.dart_tool/package_config.json')}',
    );
    expect(args[1], 'bin/report.dart');
    expect(args, isNot(contains('pub')));
    expect(args, isNot(contains('run')));
    expect(
      args.length == 3 || (args.length == 5 && args[3] == '--native-log'),
      true,
    );
    final output = Directory(args[2]);
    final report = ValidationReport.parse(
      File(p.join(output.path, 'events.jsonl')).readAsStringSync(),
      nativeLog: args.length == 5 ? File(args[4]).readAsStringSync() : null,
    );
    File(
      p.join(output.path, 'results.json'),
    ).writeAsStringSync(jsonEncode(report.toJson()));
    return CommandResult(report.qualified ? 0 : 1, '', '');
  }
}

class OfflineOnlyProvider implements RemoteProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Offline replay called provider: ${invocation.memberName}',
  );
}

class FakeProvider implements RemoteProvider {
  int starts = 0;
  Completer<void>? pausePreflight;
  bool preflightFails = false;
  bool uncertainStart = false;
  bool collectionFails = false;
  bool cleanupVerified = true;
  bool successful = true;
  Map<String, dynamic>? statusOverride;
  bool checkpointBeforeFailure = false;
  void Function(RemotePlan)? onStart;
  final List<String> calls = [];
  final List<Object> statusErrors = [];
  Map<String, dynamic>? cleanupRemote;
  @override
  Future<Map<String, dynamic>> identify(
    RemotePlan plan,
    String remoteId,
  ) async {
    calls.add('identify');
    if (remoteId != 'matrix-one') throw StateError('Wrong identity');
    return {'matrix_id': remoteId};
  }

  @override
  Future<void> preflight(RemotePlan plan) async {
    calls.add('preflight');
    await pausePreflight?.future;
    if (preflightFails) throw StateError('quota unavailable');
  }

  @override
  Future<Map<String, dynamic>> start(
    RemotePlan plan,
    void Function(Map<String, dynamic>) checkpoint,
  ) async {
    calls.add('start');
    onStart?.call(plan);
    starts++;
    final remote = <String, dynamic>{'matrix_id': 'matrix-one'};
    if (checkpointBeforeFailure) checkpoint(remote);
    if (uncertainStart) throw TimeoutException('Lost response');
    checkpoint(remote);
    return remote;
  }

  @override
  Future<Map<String, dynamic>> status(
    RemotePlan plan,
    Map<String, dynamic> remote,
  ) async {
    calls.add('status');
    if (statusErrors.isNotEmpty) throw statusErrors.removeAt(0);
    if (statusOverride != null) return statusOverride!;
    return {
      'terminal': true,
      'state': 'FINISHED',
      'test_exit_code': successful ? 0 : 1,
      'matrix': {'outcomeSummary': successful ? 'SUCCESS' : 'FAILURE'},
    };
  }

  @override
  Future<void> collect(
    RemotePlan plan,
    Map<String, dynamic> remote,
    Directory output,
  ) async {
    calls.add('collect');
    if (collectionFails) throw StateError('retrieval interrupted');
  }

  @override
  Future<Map<String, dynamic>> cleanup(
    RemotePlan plan,
    Map<String, dynamic> remote,
  ) async {
    calls.add('cleanup');
    cleanupRemote = remote;
    return {'verified': cleanupVerified && remote.isNotEmpty};
  }
}

class MatrixProvider extends GcloudProvider {
  MatrixProvider(this.value, {super.execute});
  final Map<String, dynamic> value;
  @override
  Future<Map<String, dynamic>> matrix(
    RemotePlan plan,
    String id, {
    bool cancel = false,
  }) async {
    if (cancel) throw StateError('Read-only identity check must not cancel');
    return value;
  }
}

void main() {
  test('desktop validation hook selects all advertised x64 backends', () {
    final yaml =
        loadYaml(
              File(
                'packages/llamadart_validation/pubspec.yaml',
              ).readAsStringSync(),
            )
            as Map;
    final raw =
        yaml['hooks']['user_defines']['llamadart'][nativeBackendUserDefineKey];
    for (final target in ['linux-x64', 'windows-x64']) {
      expect(
        parseRequestedBackends(bundle: target, rawUserConfig: raw),
        containsAll(['cpu', 'vulkan', 'cuda']),
      );
    }
  });

  test(
    'desktop payload guard rejects absent CUDA and accepts versioned modules',
    () {
      final root = Directory.systemTemp.createTempSync('validation-backends-');
      addTearDown(() => root.deleteSync(recursive: true));
      final libraries = Directory(p.join(root.path, 'lib'))..createSync();
      for (final target in [Abi.linuxX64, Abi.windowsX64]) {
        for (final file in libraries.listSync()) {
          file.deleteSync();
        }
        String name(String backend) => target == Abi.linuxX64
            ? 'libggml-$backend.so.0'
            : 'ggml-$backend.dll';
        for (final backend in ['cpu', 'vulkan']) {
          File(
            p.join(libraries.path, name(backend)),
          ).writeAsStringSync('fixture');
        }
        expect(
          () => requireDesktopBackendModules(root, abi: target),
          throwsStateError,
        );
        File(p.join(libraries.path, name('cuda'))).writeAsStringSync('fixture');
        expect(
          () => requireDesktopBackendModules(root, abi: target),
          returnsNormally,
        );
      }
      expect(
        () => requireDesktopBackendModules(root, abi: Abi.macosArm64),
        returnsNormally,
      );
    },
  );

  test(
    'desktop builder refuses to seal a CPU and Vulkan only payload',
    () async {
      final root = Directory.systemTemp.createTempSync('validation-build-');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final path in [
        '.flutter-version',
        'hook/build.dart',
        'lib/src/hook/native_release_pins.dart',
        'scripts/fetch_webgpu_bridge_assets.sh',
        'packages/llamadart_validation/assets/profiles/tiny-gguf-cpu.json',
      ]) {
        final target = File(p.join(root.path, path));
        target.parent.createSync(recursive: true);
        File(path).copySync(target.path);
      }
      final output = Directory(p.join(root.path, 'output'));
      var builds = 0;
      await expectLater(
        buildValidationBundle(
          root.path,
          'desktop',
          output.path,
          execute: (binary, args, {directory, timeout, environment}) async {
            if (binary == 'git') {
              return CommandResult(
                0,
                args.first == 'rev-parse' ? 'a' * 40 : '',
                '',
              );
            }
            if (binary == 'flutter' && args.first == '--version') {
              return CommandResult(
                0,
                jsonEncode({
                  'frameworkVersion': File(
                    '.flutter-version',
                  ).readAsStringSync().trim(),
                  'dartSdkVersion': Platform.version.split(' ').first,
                }),
                '',
              );
            }
            if (args.first == 'pub') return const CommandResult(0, '', '');
            if (args.first != 'build') {
              throw StateError('Unexpected command after backend guard');
            }
            builds++;
            final destination = args[args.indexOf('-o') + 1];
            final name = args.contains('bin/run.dart') ? 'run' : 'report';
            final executable = File(
              p.join(
                destination,
                'bundle',
                'bin',
                Platform.isWindows ? '$name.exe' : name,
              ),
            );
            executable.parent.createSync(recursive: true);
            executable.writeAsStringSync('executable fixture');
            for (final backend in ['cpu', 'vulkan']) {
              final library = File(
                p.join(
                  destination,
                  'bundle',
                  'lib',
                  Platform.isWindows
                      ? 'ggml-$backend.dll'
                      : 'libggml-$backend.so.0',
                ),
              );
              library.parent.createSync(recursive: true);
              library.writeAsStringSync('library fixture');
            }
            return const CommandResult(0, '', '');
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'missing backend',
            contains('missing backend modules: cuda'),
          ),
        ),
      );
      expect(builds, 2);
      expect(output.existsSync(), false);
    },
    skip: ![Abi.linuxX64, Abi.windowsX64].contains(Abi.current())
        ? 'Runs against the production host ABI on Linux/Windows x64 CI'
        : false,
  );

  test(
    'Windows arm64 keeps GGUF builds without requiring a LiteRT archive',
    () async {
      expect(standaloneLiteRtTarget(Abi.windowsArm64), isNull);
      expect(standaloneLiteRtTarget(Abi.macosX64), isNull);
      expect(standaloneLiteRtTarget(Abi.macosArm64), 'macos-arm64');
      expect(standaloneLiteRtTarget(Abi.windowsX64), 'windows-x64');
      expect(standaloneLiteRtTarget(Abi.linuxArm64), 'linux-arm64');
      final scratch = Directory.systemTemp.createTempSync('validation-arm64-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final identity = <String, dynamic>{'profile': 'tiny-gguf-cpu'};
      await bundleLiteRtRuntime(
        'missing-checkout',
        scratch,
        scratch,
        identity,
        abi: Abi.windowsArm64,
        execute:
            (executable, arguments, {directory, timeout, environment}) async =>
                throw StateError('No extraction should run'),
      );
      expect(identity['litert_runtime_supported'], false);
      expect(scratch.listSync(), isEmpty);
      await expectLater(
        bundleLiteRtRuntime('missing-checkout', scratch, scratch, {
          'profile': 'chat-litert-cpu',
        }, abi: Abi.windowsArm64),
        throwsUnsupportedError,
      );
      final macOsX64 = <String, dynamic>{'profile': 'tiny-gguf-cpu'};
      await bundleLiteRtRuntime(
        'missing-checkout',
        scratch,
        scratch,
        macOsX64,
        abi: Abi.macosX64,
        execute:
            (executable, arguments, {directory, timeout, environment}) async =>
                throw StateError('No extraction should run'),
      );
      expect(macOsX64['litert_runtime_supported'], false);
      expect(
        macOsX64['litert_runtime_unavailable_reason'],
        'No pinned LiteRT artifact for macOS x64; GGUF only',
      );
      await expectLater(
        bundleLiteRtRuntime('missing-checkout', scratch, scratch, {
          'profile': 'chat-litert-cpu',
        }, abi: Abi.macosX64),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            'LiteRT profiles are unavailable on macOS x64',
          ),
        ),
      );
    },
  );
  test(
    'standalone LiteRT archive inventory matches every supported desktop hook',
    () {
      final hook = File(
        'lib/src/hook/native_release_pins.dart',
      ).readAsStringSync();
      for (final target in [
        'macos-arm64',
        'linux-arm64',
        'linux-x64',
        'windows-x64',
      ]) {
        final spec = liteRtArchiveSpec(hook, target);
        expect(spec.checksum, matches(r'^[a-f0-9]{64}$'));
        expect(spec.libraries, isNotEmpty);
        expect(spec.libraries.any((name) => name.contains('LiteRtLm')), true);
      }
      expect(() => liteRtArchiveSpec(hook, 'windows-arm64'), throwsStateError);
      expect(() => liteRtArchiveSpec(hook, 'macos-x64'), throwsStateError);
      expect(
        () => liteRtArchiveSpec(
          hook.replaceAll('sha256:', 'unverified:'),
          'macos-arm64',
        ),
        throwsStateError,
      );
    },
  );
  late Directory scratch;
  late Directory bundle;
  late Directory runs;
  final now = DateTime.utc(2026, 9, 17, 12);
  setUp(() async {
    scratch = Directory.systemTemp.createTempSync('validation-remote-test-');
    bundle = Directory(p.join(scratch.path, 'bundle'))..createSync();
    runs = Directory(p.join(scratch.path, 'runs'));
    File(p.join(bundle.path, 'app.apk')).writeAsStringSync('app');
    File(p.join(bundle.path, 'test.apk')).writeAsStringSync('test');
    File(
      'packages/llamadart_validation/assets/profiles/tiny-gguf-cpu.json',
    ).copySync(p.join(bundle.path, 'profile.json'));
    await writeBundleManifest(bundle, {
      'target': 'android',
      'profile': 'tiny-gguf-cpu',
      'source_dirty': false,
    });
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  test('reassess CLI rejects unsafe run IDs before creating output', () async {
    final output = Directory(p.join(scratch.path, 'unsafe-reassessment'));
    final result = await Process.run(Platform.resolvedExecutable, <String>[
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      File('tool/testing/validation.dart').absolute.path,
      'reassess',
      '--run-id',
      '../unsafe',
      '--out',
      output.path,
    ], workingDirectory: Directory.current.path);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('Invalid run ID'));
    expect(
      FileSystemEntity.typeSync(output.path),
      FileSystemEntityType.notFound,
    );
  });

  RemotePlan plan({
    String id = 'qa-one',
    String target = 'firebase-android',
    String profile = 'tiny-gguf-cpu',
  }) => RemotePlan({
    'schema_version': 1,
    'run_id': id,
    'target': target,
    'project': 'test-project',
    'account': 'tester@example.com',
    'profile': profile,
    'bundle': bundle.path,
    'bundle_sha256': sha256
        .convert(
          File(p.join(bundle.path, 'bundle-manifest.json')).readAsBytesSync(),
        )
        .toString(),
    'settings': {
      'device_model': 'test-device',
      'device_version': '35',
      'zone': 'us-central1-a',
      'machine_type': 'g2-standard-4',
      'network': 'validation',
      'iap_tag': 'validation-ssh',
      'image': 'projects/test-project/global/images/pinned',
      'gpu_ready_image': true,
      'driver_version': '550',
      'quota': {
        'verified_at': now.toIso8601String(),
        'remaining_physical': 1,
        'evidence': 'checked console',
      },
      'credit': {
        'verified_at': now.toIso8601String(),
        'evidence': 'checked billing console',
        'applicable': true,
        'available_usd': 20,
        'maximum_run_usd': 3,
        'expires_at': now.add(const Duration(days: 2)).toIso8601String(),
      },
    },
  });
  RemoteController controller(FakeProvider provider, {bool pass = true}) =>
      RemoteController(
        runs,
        provider,
        now: () => now,
        delay: (_) async {},
        assess: (_, _) async => pass,
      );

  group('iOS XCTest native log', () {
    const fixtures = 'packages/llamadart_validation/test/fixtures/ios_xctest';
    String read(String name) =>
        File('$fixtures/$name').readAsStringSync().replaceAll('\r\n', '\n');
    final console = read('decision-gguf-metal.xcodebuild_output.txt');
    final journal = read('decision-gguf-metal.events.jsonl');
    final native = read('decision-gguf-metal.native.txt');
    final chat = read('chat-gguf-metal.xcodebuild_output.txt');
    const stray = 'load_tensors: offloaded 1/29 layers to GPU\n';

    test('is the lines between the records that match the journal', () {
      expect(boundConsoleNativeLog(console, journal), native);
      expect(boundConsoleNativeLog('$stray$console$stray', journal), native);
      expect(
        boundConsoleNativeLog(
          chat,
          [
            for (final line in LineSplitter.split(chat))
              if (line.startsWith('LLAMADART_VALIDATION '))
                line.substring('LLAMADART_VALIDATION '.length),
          ].join('\n'),
        ),
        allOf(
          contains('offloaded 25/25 layers'),
          isNot(contains('LLAMADART_VALIDATION')),
          isNot(contains('RunnerTests')),
        ),
      );
    });

    test('is unbound when the records differ from the journal', () {
      final lines = LineSplitter.split(console).toList();
      final markers = [
        for (var i = 0; i < lines.length; i++)
          if (lines[i].startsWith('LLAMADART_VALIDATION ')) i,
      ];
      for (final (name, text) in [
        ('another run first', '$chat$console'),
        ('another run last', '$console$chat'),
        ('missing record', (lines..removeAt(markers[3])).join('\n')),
        ('no records', native),
      ]) {
        expect(boundConsoleNativeLog(text, journal), isNull, reason: name);
      }
      expect(boundConsoleNativeLog(console, ''), isNull);
    });

    test('reaches the reporter only from one bound source', () async {
      File(
        'packages/llamadart_validation/assets/profiles/decision-gguf-metal.json',
      ).copySync(p.join(bundle.path, 'profile.json'));
      Future<String?> collect(Map<String, String> files) async {
        final run = Directory(p.join(scratch.path, 'collected-ios'));
        if (run.existsSync()) run.deleteSync(recursive: true);
        for (final MapEntry(:key, :value) in files.entries) {
          File(p.join(run.path, key))
            ..createSync(recursive: true)
            ..writeAsStringSync(value);
        }
        String? log;
        try {
          await assessCollectedRun(
            Directory.current.path,
            plan(target: 'firebase-ios', profile: 'decision-gguf-metal'),
            run,
            execute:
                (
                  executable,
                  arguments, {
                  directory,
                  timeout,
                  environment,
                }) async {
                  final index = arguments.indexOf('--native-log');
                  if (index >= 0) {
                    log = File(arguments[index + 1]).readAsStringSync();
                  }
                  return const CommandResult(0, '', '');
                },
          );
        } on ValidationAssessmentFailure catch (error) {
          expect('$error', contains('wrote no results.json'));
        }
        return log;
      }

      const device = 'remote-results/qa-one/iphone16pro-18.3-en-portrait';
      const attachment = 'xctest-attachments-0/events.jsonl';
      expect(
        await collect({
          '$device/xcodebuild_output.log': console,
          attachment: journal,
        }),
        native,
      );
      expect(
        await collect({'$device/xcodebuild_output.log': '$chat$console'}),
        isNull,
      );
      expect(
        await collect({
          '$device/xcodebuild_output.log': '$chat$console',
          attachment: journal,
        }),
        isNull,
      );
      expect(
        await collect({
          '$device/xcodebuild_output.log': console,
          '$device/stderr.log': stray,
          attachment: journal,
        }),
        isNull,
      );
      expect(
        await collect({'$device/stderr.log': stray, attachment: journal}),
        stray,
      );
    });
  });

  group('Firebase Android device log', () {
    const fixtures =
        'packages/llamadart_validation/test/fixtures/android_logcat';
    const sha =
        '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c';
    const mention = 'shared validation: gemma4-litert-gpu';
    String read(String name) =>
        File('$fixtures/$name').readAsStringSync().replaceAll('\r\n', '\n');
    final logcat = read('pixel9pro-gemma4-litert-gpu.logcat.txt');
    final journal = read('pixel9pro-gemma4-litert-gpu.events.jsonl');
    final galaxy = read('galaxys24-gemma4-litert-gpu.logcat.txt');
    final galaxyJournal = read('galaxys24-gemma4-litert-gpu.events.jsonl');
    final cpu = read('pixel9pro-chat-litert-cpu.logcat.txt');

    Future<String?> bind(String logcat, String journal) => boundLogcatNativeLog(
      Stream.fromIterable(LineSplitter.split(logcat)),
      journal,
    );
    String lines(String text, bool Function(String) keep) =>
        LineSplitter.split(text).where(keep).map((line) => '$line\n').join();
    String process(String text, String pid) {
      final all = LineSplitter.split(text).toList();
      final start = all.indexWhere(
        (line) => line.contains(' I flutter : 00:00 +0: $mention'),
      );
      return all
          .skip(start)
          .where((line) => line.split(RegExp(' +')).elementAtOrNull(2) == pid)
          .map((line) => '$line\n')
          .join();
    }

    String manifest(void Function(Map<String, dynamic>) edit) {
      final records = LineSplitter.split(journal).toList();
      final first = jsonDecode(records.first) as Map<String, dynamic>;
      edit(first);
      return [jsonEncode(first), ...records.skip(1)].join('\n');
    }

    test('is the app process from its test start record onward', () async {
      for (final (text, events, pid, adapter) in [
        (logcat, journal, '22950', 'Mali-G715'),
        (galaxy, galaxyJournal, '27418', 'Adreno (TM) 750'),
      ]) {
        final bound = await bind(text, events);
        expect(bound, process(text, pid));
        expect('Selected adapter: $adapter'.allMatches(bound!), hasLength(3));
        expect(bound, isNot(contains('ActivityManager')));
        expect(text, contains('ActivityManager'));
        // Lines the process logged before the test started belong to no run.
        expect(bound, isNot(contains('TestRunner: run started')));
        expect(text, contains(' $pid '));
        expect(text, contains('TestRunner: run started'));
      }
      // Another process cannot add or contradict evidence.
      final stray =
          '10-13 02:44:28.010   999   999 I native  : I0000 '
          '00:00:1791884668.010531     999 environment.cc:532] Selected '
          'adapter: SwiftShader, arch=, vendor=, backend=Vulkan, '
          'adapterType=CPU\n'
          '10-13 02:44:28.011   999   999 I flutter : Model x loaded from '
          '/data/files/validation/models/${'a' * 64}/x\n'
          '10-13 02:30:00.000   999   999 I native  : I0000 '
          '00:00:1000000000.000000     999 engine.cc:1] old\n';
      expect(await bind('$logcat$stray', journal), process(logcat, '22950'));
      expect(await bind('$stray$logcat', journal), process(logcat, '22950'));
    });

    test('is unbound unless exactly one run of the profile wrote it', () async {
      final start = LineSplitter.split(
        logcat,
      ).singleWhere((line) => line.endsWith('+0: $mention'));
      final first = RegExp(r'00:00:(\d+)\.(\d{6}) ').firstMatch(logcat)!;
      final firstStamp = DateTime.fromMicrosecondsSinceEpoch(
        int.parse(first[1]!) * 1000000 + int.parse(first[2]!),
        isUtc: true,
      );
      String at(Duration offset) => manifest(
        (m) => m['started_at'] = firstStamp.add(offset).toIso8601String(),
      );
      expect(await bind(logcat, at(Duration.zero)), isNotNull);
      for (final (name, text, events) in [
        ('two start records', '$logcat$start\n', journal),
        (
          'a second process started the same test',
          '$logcat${start.replaceFirst(' 22950 22950 ', '   999   999 ')}\n',
          journal,
        ),
        (
          'another process mentions the test',
          '${logcat}10-13 02:45:35.431   999   999 I TestRunner: started: '
              '$mention(com.example.MainActivityTest)\n',
          journal,
        ),
        (
          'a mention before the start record',
          '10-13 02:37:11.000 22950 23050 I TestRunner: started: '
              '$mention(com.example.MainActivityTest)\n$logcat',
          journal,
        ),
        (
          'the process also ran another profile',
          '${logcat}10-13 02:45:35.431 22950 23050 I TestRunner: started: '
              '$mention-long(com.example.MainActivityTest)\n',
          journal,
        ),
        ('a mention outside a device log record', '$logcat$mention\n', journal),
        ('no start record', lines(logcat, (line) => line != start), journal),
        (
          'the start record is another process',
          logcat.replaceFirst(
            start,
            start.replaceFirst(' 22950 22950 ', '   999   999 '),
          ),
          journal,
        ),
        (
          'only another process ran the test',
          lines(
            logcat,
            (line) => !line.contains(mention) || line == start,
          ).replaceFirst(
            start,
            start.replaceFirst(' 22950 22950 ', '   999   999 '),
          ),
          journal,
        ),
        ('another profile ran', cpu, journal),
        (
          'only another profile started',
          lines(
            logcat,
            (line) => !line.contains(mention) || line == start,
          ).replaceFirst(
            start,
            start.replaceFirst(mention, 'shared validation: other'),
          ),
          journal,
        ),
        (
          'a model from another directory',
          logcat.replaceAll(sha, 'a' * 64),
          journal,
        ),
        (
          'one load from another directory',
          logcat.replaceFirst('models/$sha/', 'models/${'a' * 64}/'),
          journal,
        ),
        (
          'the journal locks another model',
          logcat,
          manifest(
            (m) => ((m['profile'] as Map)['model'] as Map)['sha256'] = 'a' * 64,
          ),
        ),
        (
          'a model outside the validation cache',
          logcat.replaceFirst('/validation/models/$sha/', '/models/'),
          journal,
        ),
        (
          'no model load',
          lines(logcat, (line) => !line.contains(' loaded from ')),
          journal,
        ),
        (
          'a native line one microsecond early',
          logcat,
          at(const Duration(microseconds: 1)),
        ),
        ('native lines a day early', logcat, at(const Duration(days: 1))),
        (
          'no epoch timestamp',
          lines(
            logcat,
            (line) => !RegExp(r' [IWEF]0000 00:00:\d').hasMatch(line),
          ),
          journal,
        ),
        (
          'a local start time',
          logcat,
          manifest((m) => m['started_at'] = '2026-10-13T02:44:27.686436'),
        ),
        ('no start time', logcat, manifest((m) => m.remove('started_at'))),
        (
          'a first record that is not a manifest',
          logcat,
          manifest((m) => m['type'] = 'case'),
        ),
        ('an untyped first record', logcat, manifest((m) => m.remove('type'))),
        (
          'an iOS journal',
          logcat,
          manifest((m) => (m['environment'] as Map)['platform'] = 'ios'),
        ),
        (
          'a CPU journal',
          logcat,
          manifest((m) => (m['profile'] as Map)['backend'] = 'cpu'),
        ),
        (
          'a GGUF journal',
          logcat,
          manifest((m) => (m['profile'] as Map)['runtime'] = 'gguf'),
        ),
        ('no journal', logcat, ''),
        ('no device log', '', journal),
      ]) {
        expect(await bind(text, events), isNull, reason: name);
      }
    });

    test('is bound to the run at both ends of its time', () async {
      const window = 10 * 1000000;
      const skew = 100 * 1000;
      const month = 30 * 24 * 3600 * 1000000;
      final stamp = RegExp(r' [IWEF]0000 00:00:(\d+)\.(\d{6}) ');
      DateTime logged(String line) => DateTime.parse(
        '2026-${line.substring(0, 5)}T${line.substring(6, 18)}Z',
      );
      // The epoch time of the test start record and of the first native line.
      (int, int) times(String text) {
        final entries = LineSplitter.split(text).toList();
        final began = entries.singleWhere(
          (line) => line.endsWith('+0: $mention'),
        );
        final native = entries.firstWhere(stamp.hasMatch);
        final epoch = stamp.firstMatch(native)!;
        final first = int.parse(epoch[1]!) * 1000000 + int.parse(epoch[2]!);
        return (
          first - logged(native).difference(logged(began)).inMicroseconds,
          first,
        );
      }

      (int, int) identity(String events) {
        final first = jsonDecode(LineSplitter.split(events).first) as Map;
        return (
          int.parse((first['run_id'] as String).substring(4)),
          DateTime.parse(first['started_at'] as String).microsecondsSinceEpoch,
        );
      }

      for (final (text, events) in [
        (logcat, journal),
        (galaxy, galaxyJournal),
      ]) {
        final (testStart, firstStamp) = times(text);
        final (minted, started) = identity(events);
        expect(minted - testStart, inInclusiveRange(300000, 400000));
        expect(firstStamp - started, inInclusiveRange(100000, 200000));
      }
      final (testStart, firstStamp) = times(logcat);
      final (minted, started) = identity(journal);
      final (galaxyMinted, galaxyStarted) = identity(galaxyJournal);
      String run({Object? id, int? at}) => manifest((m) {
        if (id != null) m['run_id'] = id is int ? 'app-$id' : id;
        if (at != null) {
          m['started_at'] = DateTime.fromMicrosecondsSinceEpoch(
            at,
            isUtc: true,
          ).toIso8601String();
        }
      });
      // The start record relogged just before the first load, so that only
      // the order of the run id and the start time is left to decide.
      final began = LineSplitter.split(
        logcat,
      ).singleWhere((line) => line.endsWith('+0: $mention'));
      final late = logcat.replaceFirst(
        began,
        began.replaceFirst('02:37:12.167', '02:44:27.500'),
      );
      expect(late, isNot(logcat));

      for (final (name, text, events) in [
        ('the recorded journal', logcat, journal),
        ('a run id at the window', logcat, run(id: testStart + window)),
        ('a run id at the clock slack', logcat, run(id: testStart - skew)),
        ('a start time at the window', logcat, run(at: firstStamp - window)),
        ('a start time at the first native line', logcat, run(at: firstStamp)),
        ('a run id at the start time', late, run(id: started)),
      ]) {
        expect(await bind(text, events), isNotNull, reason: name);
      }
      for (final (name, text, events) in [
        ('the journal of the other device run', galaxy, journal),
        ('the device log of the other device run', logcat, galaxyJournal),
        ('the other run under this run id', galaxy, run(at: galaxyStarted)),
        ('the other run under this start time', galaxy, run(id: galaxyMinted)),
        (
          'a journal dated 30 days earlier',
          logcat,
          run(id: minted - month, at: started - month),
        ),
        ('a start time 30 days earlier', logcat, run(at: started - month)),
        ('a run id 30 days earlier', logcat, run(id: minted - month)),
        ('the run id of the other device run', logcat, run(id: galaxyMinted)),
        ('a run id past the window', logcat, run(id: testStart + window + 1)),
        (
          'a run id before the start record',
          logcat,
          run(id: testStart - skew - 1),
        ),
        (
          'a start time before the window',
          logcat,
          run(at: firstStamp - window - 1),
        ),
        ('a run id after the start time', late, run(id: started + 1)),
        ('a run id that is not a time', logcat, run(id: 'app-1')),
        ('a run id with another prefix', logcat, run(id: 'qa-$minted')),
        ('a run id with a suffix', logcat, run(id: 'app-$minted-2')),
        ('a longer run id', logcat, run(id: 'app-${minted}0')),
        ('a zero-padded run id', logcat, run(id: 'app-000$minted')),
        ('a numeric run id', logcat, manifest((m) => m['run_id'] = minted)),
        ('no run id', logcat, manifest((m) => m.remove('run_id'))),
      ]) {
        expect(await bind(text, events), isNull, reason: name);
      }
    });

    test('measures the time since the test start without a year', () async {
      // A run whose first native line is logged at `loaded` and stamped
      // `first`, with a run id minted `mintedBefore` that line.
      Future<String?> synthetic(
        String began,
        String loaded,
        DateTime first, {
        required Duration mintedBefore,
      }) {
        final events = manifest((m) {
          m['started_at'] = first
              .subtract(const Duration(milliseconds: 100))
              .toIso8601String();
          m['run_id'] =
              'app-${first.subtract(mintedBefore).microsecondsSinceEpoch}';
        });
        final epoch = first.microsecondsSinceEpoch;
        return bind(
          '$began 100 100 I flutter : 00:00 +0: $mention\n'
          '$loaded 100 100 I flutter : Model m loaded from '
          '/data/files/validation/models/$sha/m\n'
          '$loaded 100 101 W native  : W0000 00:00:${epoch ~/ 1000000}.'
          '${'${epoch % 1000000}'.padLeft(6, '0')}     101 engine.cc:1] x\n',
          events,
        );
      }

      const elapsed = Duration(seconds: 5);
      const day = Duration(days: 1);
      for (final (name, began, loaded, first, since) in [
        // The device is seven hours behind UTC.
        (
          'the same day',
          '10-13 02:44:22.829',
          '10-13 02:44:27.829',
          DateTime.utc(2026, 10, 13, 9, 44, 27, 829),
          elapsed,
        ),
        (
          'across New Year',
          '12-31 23:59:57.000',
          '01-01 00:00:02.000',
          DateTime.utc(2027, 1, 1, 7, 0, 2),
          elapsed,
        ),
        // The device is nine hours ahead of UTC, which is still last year.
        (
          'across New Year ahead of UTC',
          '12-31 23:59:57.000',
          '01-01 00:00:02.000',
          DateTime.utc(2026, 12, 31, 15, 0, 2),
          elapsed,
        ),
        (
          'into March',
          '02-28 23:59:57.000',
          '03-01 00:00:02.000',
          DateTime.utc(2027, 3, 1, 7, 0, 2),
          elapsed,
        ),
        (
          'into March of a leap year',
          '02-28 23:59:57.000',
          '03-01 00:00:02.000',
          DateTime.utc(2028, 3, 1, 7, 0, 2),
          elapsed + day,
        ),
        // The device clock moves from eight to seven hours behind UTC.
        (
          'across the start of daylight saving time',
          '03-08 01:59:57.000',
          '03-08 03:00:02.000',
          DateTime.utc(2026, 3, 8, 10, 0, 2),
          elapsed,
        ),
        (
          'across the end of daylight saving time',
          '11-01 01:59:57.000',
          '11-01 01:00:02.000',
          DateTime.utc(2026, 11, 1, 9, 0, 2),
          elapsed,
        ),
        // A half-hour change, as on Lord Howe Island.
        (
          'across a half-hour daylight saving change',
          '10-04 01:59:57.000',
          '10-04 02:30:02.000',
          DateTime.utc(2026, 10, 3, 15, 30, 2),
          elapsed,
        ),
      ]) {
        expect(
          await synthetic(began, loaded, first, mintedBefore: since),
          isNotNull,
          reason: name,
        );
        for (final other in [since + day, since - day, since + elapsed * 3]) {
          expect(
            await synthetic(began, loaded, first, mintedBefore: other),
            isNull,
            reason: '$name, minted $other before the first native line',
          );
        }
      }
      // Only a daylight saving change explains a jump in the device clock.
      for (final (began, loaded, first) in [
        (
          '03-08 01:59:57.000',
          '03-08 03:30:02.000',
          DateTime.utc(2026, 3, 8, 10, 0, 2),
        ),
        (
          '03-08 01:59:57.000',
          '03-08 04:00:02.000',
          DateTime.utc(2026, 3, 8, 10, 0, 2),
        ),
        (
          '11-01 01:59:57.000',
          '11-01 00:00:02.000',
          DateTime.utc(2026, 11, 1, 9, 0, 2),
        ),
      ]) {
        expect(
          await synthetic(began, loaded, first, mintedBefore: elapsed),
          isNull,
          reason: 'a clock jump from $began to $loaded',
        );
      }
    });

    test('keeps no service URL wherever the process logs it', () async {
      for (final text in [logcat, galaxy, cpu]) {
        expect(text, isNot(contains('://')));
        expect(text, isNot(contains('VM service')));
      }
      final began = LineSplitter.split(
        logcat,
      ).singleWhere((line) => line.endsWith('+0: $mention'));
      const prefix = '10-13 02:37:12.500 22950 23091';
      const url = 'http://127.0.0.1:33441/fixtureAuthCode=/';
      Future<String?> after(String record) =>
          bind(logcat.replaceFirst('$began\n', '$began\n$record\n'), journal);
      expect(
        await after('$prefix I flutter : Running on the device'),
        contains('$began\n$prefix I flutter : Running on the device\n'),
      );

      // The announcement is printed by another thread, so it can follow the
      // start record.
      for (final announcement in [
        '$prefix I flutter : The Dart VM service is listening on $url',
        '$prefix I flutter : Dart VM service is listening on $url',
        '$prefix I flutter : The Dart VM service is listening on '
            'http://0.0.0.0:8181/fixtureAuthCode=/',
      ]) {
        expect(
          await after(announcement),
          process(logcat, '22950'),
          reason: announcement,
        );
        expect(
          await bind('$logcat$announcement\n', journal),
          process(logcat, '22950'),
          reason: announcement,
        );
      }
      // Any other line with such a URL could lose more than the URL, so the
      // log is left unbound instead of being edited.
      for (final record in [
        '$prefix E native  : Falling back to CPU $url',
        '$prefix I flutter : The Dart VM service is listening on $url '
            'Falling back to CPU',
        '$prefix I native  : The Dart VM service is listening on $url',
        '$prefix I flutter : Falling back to CPU. The Dart VM service is '
            'listening on $url',
        '$prefix I flutter : The Flutter DevTools debugger and profiler on '
            'Pixel 9 Pro is available at: http://10.0.0.2:9101?uri=x',
        '$prefix I flutter : The Dart VM service is listening on '
            'http://0.0.0.0:8181/fixtureAuthCode=/ too',
        // A marker in the dropped URL token must still be seen.
        '$prefix I flutter : The Dart VM service is listening on '
            'http://127.0.0.1:33441/VK_ERROR_DEVICE_LOST/',
        '$prefix I flutter : connecting ws://127.0.0.1:33441/fixtureAuthCode=',
        '$prefix I flutter : connecting http://localhost:33441/fixtureAuthCode',
        '$prefix I flutter : connecting http://[::1]:33441/fixtureAuthCode=/',
        '$prefix I flutter : connecting http://127.0.0.1/fixtureAuthCode=/',
        // Loopback, unspecified and other IP-literal hosts in any spelling.
        for (final host in [
          '0.0.0.0',
          'LOCALHOST',
          'localhost.',
          'dev.localhost',
          '127.1',
          '2130706433',
          '0x7f000001',
          '0177.0.0.1',
          '10.0.2.15',
          '[0:0:0:0:0:0:0:1]',
          '[::ffff:127.0.0.1]',
          'user@127.0.0.1',
        ])
          '$prefix I flutter : connecting http://$host:33441/fixtureAuthCode=/',
        '$prefix I flutter : connecting HTTP://Localhost/fixtureAuthCode=/',
        '$prefix I flutter : connecting ws://127.0.0.1?fixtureAuthCode=',
        // Only the whole message of the `flutter` record is an announcement.
        '$prefix I native  : flutter : The Dart VM service is listening on '
            '$url',
      ]) {
        expect(await after(record), isNull, reason: record);
      }
      // Another process is not this run's log.
      expect(
        await after(
          '10-13 02:37:12.500   999   999 I flutter : The Dart VM service is '
          'listening on $url',
        ),
        process(logcat, '22950'),
      );
    });

    test('reads only whole threadtime records', () async {
      final began = LineSplitter.split(
        logcat,
      ).singleWhere((line) => line.endsWith('+0: $mention'));
      expect(
        await bind(logcat.replaceFirst('$began\n', 'x $began\n'), journal),
        isNull,
      );
    });

    test('is unbound when the process logged more than the limit', () async {
      final native = LineSplitter.split(
        logcat,
      ).firstWhere((line) => line.contains('Creating LiteRT environment'));
      Stream<String> padded(int repeats, [String? last]) async* {
        yield* Stream.fromIterable(LineSplitter.split(logcat));
        for (var i = 0; i < repeats; i++) {
          yield native;
        }
        if (last != null) yield last;
      }

      final perLine = native.length + 1;
      final room = 8 * 1024 * 1024 - process(logcat, '22950').length;
      expect(
        await boundLogcatNativeLog(padded(room ~/ perLine), journal),
        isNotNull,
      );
      expect(
        await boundLogcatNativeLog(padded(room ~/ perLine + 1), journal),
        isNull,
      );
      // A dropped service announcement counts toward the limit too.
      final announcement =
          '10-13 02:45:35.500 22950 23091 I flutter : The Dart VM service is '
          'listening on http://127.0.0.1:33441/${'a' * perLine}=/';
      expect(
        await boundLogcatNativeLog(padded(0, announcement), journal),
        process(logcat, '22950'),
      );
      expect(
        await boundLogcatNativeLog(
          padded(room ~/ perLine, announcement),
          journal,
        ),
        isNull,
      );
    });

    test('reaches the reporter only when no other capture exists', () async {
      File(
        'packages/llamadart_validation/assets/profiles/gemma4-litert-gpu.json',
      ).copySync(p.join(bundle.path, 'profile.json'));
      const device = 'remote-results/qa-one/caiman-35-en-portrait';
      Future<String?> collect(
        Map<String, String> files, {
        String target = 'firebase-android',
        int? logcatBytes,
      }) async {
        final run = Directory(p.join(scratch.path, 'collected-android'));
        if (run.existsSync()) run.deleteSync(recursive: true);
        for (final MapEntry(:key, :value) in files.entries) {
          File(p.join(run.path, key))
            ..createSync(recursive: true)
            ..writeAsStringSync(value);
        }
        if (logcatBytes != null) {
          // Lines of no device-log shape, which binding skips.
          final padded = File(
            p.join(run.path, '$device/logcat'),
          ).openSync(mode: FileMode.append);
          final filler = List.filled(1 << 16, 0x78)..last = 0x0a;
          for (
            var left = logcatBytes - padded.lengthSync();
            left > 0;
            left -= filler.length
          ) {
            padded.writeFromSync(
              filler,
              filler.length - (left < filler.length ? left : filler.length),
            );
          }
          padded.closeSync();
          expect(File(padded.path).lengthSync(), logcatBytes);
        }
        String? log;
        try {
          await assessCollectedRun(
            Directory.current.path,
            plan(target: target, profile: 'gemma4-litert-gpu'),
            run,
            execute:
                (
                  executable,
                  arguments, {
                  directory,
                  timeout,
                  environment,
                }) async {
                  final index = arguments.indexOf('--native-log');
                  if (index >= 0) {
                    log = File(arguments[index + 1]).readAsStringSync();
                  }
                  return const CommandResult(0, '', '');
                },
          );
        } on ValidationAssessmentFailure catch (error) {
          expect('$error', contains('wrote no results.json'));
        }
        return log;
      }

      const pulled =
          '$device/artifacts/sdcard/Android/data/app/files/validation/runs/'
          'app-1/events.jsonl';
      const stray = 'Selected adapter: stray\n';
      const limit = 128 * 1024 * 1024;
      final bound = process(logcat, '22950');
      expect(await collect({'$device/logcat': logcat, pulled: journal}), bound);
      expect(await collect({pulled: journal}), isNull);
      expect(
        await collect({
          '$device/logcat': logcat,
          pulled: journal,
        }, logcatBytes: limit),
        bound,
      );
      expect(
        await collect({
          '$device/logcat': logcat,
          pulled: journal,
        }, logcatBytes: limit + 1),
        isNull,
      );
      for (final (name, files) in [
        (
          'two device logs',
          {
            '$device/logcat': logcat,
            'remote-results/qa-one/other-35-en-portrait/logcat': logcat,
            pulled: journal,
          },
        ),
        (
          'a device log of another run',
          {'$device/logcat': logcat.replaceAll(sha, 'a' * 64), pulled: journal},
        ),
        (
          'the device log of the other device run',
          {'$device/logcat': galaxy, pulled: journal},
        ),
        (
          'a device log outside the pulled results',
          {'xctest-attachments-0/logcat': logcat, pulled: journal},
        ),
        (
          'an unbound console capture',
          {
            '$device/logcat': logcat,
            '$device/xcodebuild_output.log': stray,
            pulled: journal,
          },
        ),
        (
          'two stderr captures',
          {
            '$device/logcat': logcat,
            '$device/stderr.log': stray,
            '$device/other/stderr.log': stray,
            pulled: journal,
          },
        ),
      ]) {
        expect(await collect(files), isNull, reason: name);
      }
      expect(
        await collect({
          '$device/logcat': logcat,
          pulled: journal,
        }, target: 'firebase-ios'),
        isNull,
      );
      // A stderr capture keeps deciding, exactly as without a device log.
      expect(
        await collect({
          '$device/logcat': logcat,
          '$device/stderr.log': stray,
          pulled: journal,
        }),
        stray,
      );
    });

    test(
      'offline replay uses only the prepared reporter and preserves saved bytes',
      () async {
        final first = jsonDecode(LineSplitter.split(journal).first) as Map;
        final profile = first['profile'] as Map;
        File(
          p.join(bundle.path, 'profile.json'),
        ).writeAsStringSync(jsonEncode(profile));
        await writeBundleManifest(bundle, {
          'target': 'android',
          'profile': 'gemma4-litert-gpu',
          ...Map<String, dynamic>.from(first['environment'] as Map),
        });
        final saved = Directory(p.join(runs.path, 'qa-one'));
        final raw =
            File(p.join(saved.path, 'remote-results/device/events.jsonl'))
              ..createSync(recursive: true)
              ..writeAsStringSync(journal);
        final deviceLog = File(
          p.join(saved.path, 'remote-results/device/logcat'),
        )..writeAsStringSync(logcat);
        final oldReport = File(p.join(saved.path, 'report/native.log'))
          ..createSync(recursive: true)
          ..writeAsStringSync('old derived capture');
        final state = <String, dynamic>{
          'plan': plan(profile: 'gemma4-litert-gpu').json,
          'remote': {
            'state': 'FINISHED',
            'matrix': {'outcomeSummary': 'SUCCESS'},
          },
          'collection': 'COMPLETE',
          'cleanup': 'VERIFIED',
          'error': null,
        };
        final orchestration = File(p.join(saved.path, 'orchestration.json'))
          ..writeAsStringSync(jsonEncode(state));
        final before = [
          raw,
          deviceLog,
          oldReport,
          orchestration,
        ].map((f) => f.readAsStringSync()).toList();
        final reporter = PreparedReporterSpy(scratch);
        Future<Map<String, dynamic>> replay(String name) =>
            RemoteController(runs, OfflineOnlyProvider()).reassess(
              'qa-one',
              Directory(p.join(scratch.path, name)),
              replay: (saved, output) => reassessSavedRun(
                reporter.repository.path,
                saved,
                output,
                execute: reporter.execute,
              ),
            );
        final a = await replay('offline-a');
        final b = await replay('offline-b');
        expect(a, b);
        expect(a['assertions_passed'], true);
        expect(a['qualified'], true);
        expect(reporter.calls, 2);
        expect(
          [
            raw,
            deviceLog,
            oldReport,
            orchestration,
          ].map((f) => f.readAsStringSync()).toList(),
          before,
        );
        await expectLater(replay('offline-a'), throwsStateError);
        for (final entry in <String, Object?>{
          'cleanup': 'UNKNOWN',
          'collection': 'INCOMPLETE',
          'error': 'historical failure',
        }.entries) {
          final changed = {...state, entry.key: entry.value};
          orchestration.writeAsStringSync(jsonEncode(changed));
          expect((await replay('offline-${entry.key}'))['qualified'], false);
        }
        orchestration.writeAsStringSync(
          jsonEncode({
            ...state,
            'remote': {'state': 'RUNNING'},
          }),
        );
        expect((await replay('offline-provider'))['qualified'], false);
        // The old positive derived capture is never reused when binding fails.
        deviceLog.writeAsStringSync(galaxy);
        expect((await replay('offline-unbound'))['assertions_passed'], false);
        expect(
          File(
            p.join(scratch.path, 'offline-unbound/report/native.log'),
          ).existsSync(),
          false,
        );
        deviceLog.writeAsStringSync(
          logcat.replaceFirst('Mali-G715', 'Mali-G715 Falling back to CPU'),
        );
        expect((await replay('offline-marker'))['assertions_passed'], false);
        deviceLog.writeAsStringSync(logcat.replaceAll(sha, 'a' * 64));
        expect(
          (await replay('offline-missing-binding'))['assertions_passed'],
          false,
        );
        deviceLog.writeAsStringSync(logcat);
        final shifted = Map<String, dynamic>.from(first)
          ..['started_at'] = DateTime.parse(
            first['started_at'] as String,
          ).add(const Duration(days: 30)).toUtc().toIso8601String();
        raw.writeAsStringSync(
          [
            jsonEncode(shifted),
            ...LineSplitter.split(journal).skip(1),
          ].join('\n'),
        );
        expect(
          (await replay('offline-log-window'))['assertions_passed'],
          false,
        );
        raw.writeAsStringSync(
          journal.replaceAll('gemma4-litert-gpu', 'wrong-profile'),
        );
        final prior = reporter.calls;
        expect((await replay('offline-profile'))['assertions_passed'], false);
        expect(reporter.calls, prior);
        raw.writeAsStringSync(journal);
        final other = File(
          p.join(saved.path, 'remote-results/device/other.jsonl'),
        )..writeAsStringSync('$journal\n{"type":"other"}\n');
        expect((await replay('offline-conflict'))['assertions_passed'], false);
        other.deleteSync();
        final badRepository = Directory(p.join(scratch.path, 'unprepared'))
          ..createSync();
        await expectLater(
          reassessSavedRun(
            badRepository.path,
            saved,
            Directory(p.join(scratch.path, 'offline-no-deps')),
            execute: reporter.execute,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'prerequisite',
              contains('prepared dependencies'),
            ),
          ),
        );
        expect(reporter.calls, prior);
        orchestration.writeAsStringSync(
          jsonEncode({
            ...state,
            'plan': {...state['plan'] as Map, 'profile': 'wrong-profile'},
          }),
        );
        await expectLater(replay('offline-plan-profile'), throwsStateError);
        orchestration.writeAsStringSync(jsonEncode({...state}..remove('plan')));
        await expectLater(replay('offline-no-plan'), throwsA(isA<TypeError>()));
        expect(reporter.calls, prior);
        orchestration.writeAsStringSync(jsonEncode(state));
        File(p.join(bundle.path, 'app.apk')).writeAsStringSync('changed');
        await expectLater(
          replay('offline-changed-bundle'),
          throwsFormatException,
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('leaves no earlier native log when a run is reassessed', () async {
      File(
        'packages/llamadart_validation/assets/profiles/gemma4-litert-gpu.json',
      ).copySync(p.join(bundle.path, 'profile.json'));
      final run = Directory(p.join(scratch.path, 'reassessed-android'));
      final device = p.join(run.path, 'remote-results', 'qa-one', 'caiman');
      File(p.join(device, 'artifacts/validation/runs/app-1/events.jsonl'))
        ..createSync(recursive: true)
        ..writeAsStringSync(journal);
      final deviceLog = File(p.join(device, 'logcat'))
        ..writeAsStringSync(logcat);
      final retained = File(p.join(run.path, 'report', 'native.log'));
      Future<String?> assess() async {
        String? log;
        try {
          await assessCollectedRun(
            Directory.current.path,
            plan(target: 'firebase-android', profile: 'gemma4-litert-gpu'),
            run,
            execute:
                (
                  executable,
                  arguments, {
                  directory,
                  timeout,
                  environment,
                }) async {
                  final index = arguments.indexOf('--native-log');
                  if (index >= 0) log = arguments[index + 1];
                  return const CommandResult(0, '', '');
                },
          );
        } on ValidationAssessmentFailure catch (error) {
          expect('$error', contains('wrote no results.json'));
        }
        return log;
      }

      expect(await assess(), retained.path);
      expect(retained.readAsStringSync(), process(logcat, '22950'));
      deviceLog.writeAsStringSync(galaxy);
      expect(await assess(), isNull);
      expect(retained.existsSync(), isFalse);

      deviceLog.writeAsStringSync(logcat);
      expect(await assess(), retained.path);
      File(p.join(device, 'artifacts/validation/runs/app-2/events.jsonl'))
        ..createSync(recursive: true)
        ..writeAsStringSync('$journal\n{"type":"other"}\n');
      expect(await assess(), isNull);
      expect(retained.existsSync(), isFalse);
      File(
        p.join(device, 'artifacts/validation/runs/app-2/events.jsonl'),
      ).deleteSync();

      expect(await assess(), retained.path);
      final stderr = File(p.join(device, 'stderr.log'))
        ..writeAsStringSync('Selected adapter: stray\n');
      expect(await assess(), stderr.path);
      expect(retained.existsSync(), isFalse);
    });
  });

  test(
    'offline GCE replay rejects wrong OS and ABI before reporter execution',
    () async {
      const fixture =
          'packages/llamadart_validation/test/fixtures/windows_native_log';
      final lines = LineSplitter.split(
        File('$fixture/tiny.events.jsonl').readAsStringSync(),
      ).toList();
      final first = jsonDecode(lines.first) as Map<String, dynamic>;
      final environment = Map<String, dynamic>.from(
        first['environment'] as Map,
      );
      File(p.join(bundle.path, 'assets/profiles/tiny-gguf-cuda.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(first['profile']));
      final saved = Directory(p.join(runs.path, 'qa-one'));
      final raw = File(p.join(saved.path, 'remote-results/device/events.jsonl'))
        ..createSync(recursive: true);
      final native = File(
        '$fixture/tiny.native.txt',
      ).copySync(p.join(saved.path, 'remote-results/device/stderr.log'));
      final originalReport = File(p.join(saved.path, 'report/results.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('historical report');
      final orchestration = File(p.join(saved.path, 'orchestration.json'));
      final reporter = PreparedReporterSpy(scratch);
      for (final variant in [
        (
          'matching-windows',
          'gce-windows-cuda',
          'windows',
          'windows_x64',
          true,
        ),
        ('wrong-os', 'gce-windows-cuda', 'linux', 'windows_x64', false),
        ('wrong-abi', 'gce-windows-cuda', 'windows', 'linux_x64', false),
        (
          'relabeled-linux-plan',
          'gce-linux-cuda',
          'windows',
          'windows_x64',
          false,
        ),
      ]) {
        await writeBundleManifest(bundle, {
          ...environment,
          'target': 'desktop',
          'build_os': variant.$3,
          'build_abi': variant.$4,
        });
        final savedPlan = plan(target: variant.$2, profile: 'tiny-gguf-cuda');
        first['environment'] = {
          ...environment,
          'runtime_bundle_sha256': savedPlan.json['bundle_sha256'],
        };
        raw.writeAsStringSync([jsonEncode(first), ...lines.skip(1)].join('\n'));
        orchestration.writeAsStringSync(
          jsonEncode({
            'plan': savedPlan.json,
            'remote': {'terminal': true, 'test_exit_code': 0},
            'collection': 'COMPLETE',
            'cleanup': 'VERIFIED',
          }),
        );
        final inputs = [
          raw,
          native,
          originalReport,
          orchestration,
          File(p.join(bundle.path, 'bundle-manifest.json')),
        ];
        final before = inputs.map((file) => file.readAsBytesSync()).toList();
        final output = Directory(p.join(scratch.path, variant.$1));
        final callsBefore = reporter.calls;
        final replay = RemoteController(runs, OfflineOnlyProvider()).reassess(
          'qa-one',
          output,
          replay: (saved, output) => reassessSavedRun(
            reporter.repository.path,
            saved,
            output,
            execute: reporter.execute,
          ),
        );
        if (variant.$5) {
          expect((await replay)['qualified'], true, reason: variant.$1);
          expect(reporter.calls, callsBefore + 1);
        } else {
          await expectLater(
            replay,
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'binding',
                'GCE requires a matching x64 OS bundle',
              ),
            ),
            reason: variant.$1,
          );
          expect(reporter.calls, callsBefore, reason: variant.$1);
          expect(output.existsSync(), false, reason: variant.$1);
        }
        expect(
          inputs.map((file) => file.readAsBytesSync()).toList(),
          before,
          reason:
              '${variant.$1} must preserve raw, historical and bundle evidence',
        );
      }
      for (final target in ['gce-windows-cuda', 'gce-linux-cuda']) {
        final windows = target == 'gce-windows-cuda';
        expect(
          () => requireRemoteBundleTarget(plan(target: target), {
            'target': 'desktop',
            'build_os': windows ? 'windows' : 'linux',
            'build_abi': windows ? 'windows_x64' : 'linux_x64',
          }),
          returnsNormally,
        );
      }
    },
  );

  test(
    'collected qualification binds every uploaded runtime identity',
    () async {
      final identity = <String, dynamic>{
        'source_commit': 'a' * 40,
        'source_dirty': false,
        'hook_sha256': 'b' * 64,
        'native_tag': 'v0.4.0',
        'litert_tag': '0.17.0-6',
        'bridge_tag': 'fixture-bridge',
      };
      await writeBundleManifest(bundle, {'target': 'android', ...identity});
      final profile = jsonDecode(
        File(p.join(bundle.path, 'profile.json')).readAsStringSync(),
      );
      final run = Directory(p.join(scratch.path, 'collected'))..createSync();
      final pulled = Directory(p.join(run.path, 'remote-results'))
        ..createSync();
      File(
        p.join(pulled.path, 'events.jsonl'),
      ).writeAsStringSync(jsonEncode({'type': 'manifest', 'profile': profile}));
      Future<bool> assess(Map<String, dynamic> bound) => assessCollectedRun(
        Directory.current.path,
        plan(),
        run,
        execute:
            (executable, arguments, {directory, timeout, environment}) async {
              if (arguments.first == 'pub') {
                return const CommandResult(0, '', '');
              }
              expect(arguments, contains('bin/report.dart'));
              File(p.join(arguments[2], 'results.json')).writeAsStringSync(
                jsonEncode({
                  'manifest': {'environment': bound, 'profile': profile},
                  'summary': {'qualified': true},
                }),
              );
              return const CommandResult(0, '', '');
            },
      );
      expect(await assess(identity), true);
      for (final key in identity.keys) {
        expect(
          await assess({
            ...identity,
            key: key == 'source_dirty' ? true : 'different',
          }),
          false,
          reason: key,
        );
        expect(await assess({...identity}..remove(key)), false, reason: key);
      }
    },
  );

  group('collected qualification report step', () {
    late Directory run;
    late String package;
    late Map<String, Object?> profile;
    final calls = <String>[];

    setUp(() {
      profile = jsonDecode(
        File(p.join(bundle.path, 'profile.json')).readAsStringSync(),
      );
      run = Directory(p.join(scratch.path, 'collected'));
      File(p.join(run.path, 'remote-results', 'events.jsonl'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({'type': 'manifest', 'profile': profile}),
        );
      package = p.join(scratch.path, 'packages/llamadart_validation');
      calls.clear();
    });

    Future<bool> assess({
      CommandResult pubGet = const CommandResult(0, '', ''),
      CommandResult report = const CommandResult(0, '', ''),
      bool? qualified,
    }) => assessCollectedRun(
      scratch.path,
      plan(),
      run,
      execute:
          (executable, arguments, {directory, timeout, environment}) async {
            expect(directory, package);
            calls.add(arguments.take(2).join(' '));
            if (arguments.first == 'pub') return pubGet;
            if (qualified != null) {
              File(p.join(arguments[2], 'results.json')).writeAsStringSync(
                jsonEncode({
                  'manifest': {'environment': {}, 'profile': profile},
                  'summary': {'qualified': qualified},
                }),
              );
            }
            return report;
          },
    );

    Matcher failure(List<Object> parts) => throwsA(
      isA<ValidationAssessmentFailure>().having(
        (error) => error.message,
        'message',
        allOf(parts.map(contains).toList()),
      ),
    );

    test('resolves the validation package before the report', () async {
      expect(await assess(qualified: true), false);
      expect(calls, ['pub get', 'run bin/report.dart']);
    });

    test('names a failed pub get with its exit code and stderr', () async {
      await expectLater(
        assess(pubGet: const CommandResult(69, '', 'Could not resolve x')),
        failure(['`dart pub get`', 'exited 69', 'Could not resolve x']),
      );
      expect(calls, ['pub get']);
    });

    test(
      'names a report that wrote no results, with a redacted tail',
      () async {
        final stderr = [
          for (var i = 0; i < 30; i++) 'line $i',
          "Error: Couldn't resolve the package 'llamadart_validation'",
          'at /Users/someone/secret-dir/run/report/events.jsonl',
          'fetching https://example.com/model?token=abc123',
          'download from https://signed.example?sig=4f2e failed',
          'Authorization: Bearer abc123',
          r'C:\Users\someone\secret-dir\run.log',
        ].join('\n');
        final report = assess(report: CommandResult(254, '', stderr));
        await expectLater(
          report,
          failure([
            '`dart run bin/report.dart`',
            'exited 254',
            'wrote no results.json',
            "Couldn't resolve the package",
          ]),
        );
        final message = await report.then<String>(
          (_) => fail('The report step must fail'),
          onError: (Object error) => '$error',
        );
        for (final hidden in [
          'someone',
          'secret-dir',
          'abc123',
          'signed.example',
          'line 10',
        ]) {
          expect(message, isNot(contains(hidden)), reason: hidden);
        }
        expect(message, contains('line 29'));
      },
    );

    test('accepts exit 1 only for an unqualified report', () async {
      expect(
        await assess(report: const CommandResult(1, '', ''), qualified: false),
        false,
      );
      await expectLater(
        assess(report: const CommandResult(1, '', 'boom'), qualified: true),
        failure(['exited 1', 'boom']),
      );
      await expectLater(
        assess(report: const CommandResult(255, '', ''), qualified: false),
        failure(['exited 255']),
      );
    });

    test('ignores results.json left by an earlier report', () async {
      File(p.join(run.path, 'report', 'results.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'manifest': {'environment': {}, 'profile': profile},
            'summary': {'qualified': false},
          }),
        );
      await expectLater(
        assess(report: const CommandResult(1, '', '')),
        failure(['exited 1', 'wrote no results.json']),
      );
    });
  });

  test(
    'a failed report step becomes the run error until a clean recollect',
    () async {
      var reportFails = true;
      final control = RemoteController(
        runs,
        FakeProvider(),
        now: () => now,
        delay: (_) async {},
        assess: (_, _) async {
          if (reportFails) {
            throw const ValidationAssessmentFailure(
              'Validation report step `dart run bin/report.dart` exited 254',
            );
          }
          return true;
        },
      );
      final failed = await control.run(plan());
      expect(failed['phase'], 'FAILED');
      expect(failed['qualified'], false);
      expect(failed['error'], contains('`dart run bin/report.dart`'));
      final summary = jsonDecode(
        File(
          p.join(runs.path, 'qa-one', 'remote-summary.json'),
        ).readAsStringSync(),
      );
      expect(summary['error'], contains('exited 254'));

      reportFails = false;
      final recollected = await control.recover('qa-one', 'collect');
      expect(recollected['error'], isNull);
      expect(recollected['qualified'], true);
    },
  );

  test(
    'source provenance rejects local pub overrides before reading Git',
    () async {
      File(
        p.join(scratch.path, 'pubspec_overrides.yaml'),
      ).writeAsStringSync('dependency_overrides: {}');
      await expectLater(
        readValidationProvenance(
          scratch.path,
          execute:
              (
                executable,
                arguments, {
                directory,
                timeout,
                environment,
              }) async => throw StateError('Git must not run'),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'reason',
            contains('local pub overrides'),
          ),
        ),
      );
    },
  );

  RemotePlan blazePlan({String id = 'qa-one', String funding = 'credit'}) {
    final json =
        jsonDecode(jsonEncode(plan(id: id).json)) as Map<String, dynamic>;
    final settings = json['settings'] as Map;
    settings['billing_mode'] = 'blaze';
    settings['billing_account'] = '123456-ABCDEF-123456';
    settings['budget'] = {
      'verified_at': now.toIso8601String(),
      'evidence': 'operator checked authorization and current gross pricing',
      'window_start': now.toIso8601String(),
      'expires_at': now.add(const Duration(hours: 4)).toIso8601String(),
      'maximum_run_usd': 2,
      'maximum_total_usd': 6,
      'funding': funding,
    };
    return RemotePlan(json);
  }

  RemotePlan decimalBudgetPlan({
    String id = 'qa-one',
    required num perRun,
    required num total,
  }) {
    final json =
        jsonDecode(
              jsonEncode(blazePlan(id: id, funding: 'approved_charges').json),
            )
            as Map<String, dynamic>;
    json['settings']['test_timeout_minutes'] = 1;
    json['settings']['budget']['maximum_run_usd'] = perRun;
    json['settings']['budget']['maximum_total_usd'] = total;
    return RemotePlan(json);
  }

  test('Blaze reserves decimal USD without binary cent rounding', () {
    for (final (amount, cents) in <(num, int)>[
      (1.10, 110),
      (0.07, 7),
      (0.29, 29),
      (1, 100),
      (2.001, 201),
      (1.1000000000000003, 111),
      (1e-7, 1),
    ]) {
      expect(
        decimalBudgetPlan(perRun: amount, total: 3).reservedUsdCents,
        cents,
        reason: 'USD $amount',
      );
    }
  });

  test('Blaze rejects a reservation that cannot fit in its journal', () async {
    final provider = FakeProvider();
    final result = await controller(
      provider,
    ).run(decimalBudgetPlan(perRun: 1e18, total: 1e19));
    expect(result['phase'], 'PREFLIGHT_FAILED');
    expect(
      () => decimalBudgetPlan(perRun: 1e18, total: 1e19).reservedUsdCents,
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'reason',
          contains('supported integer range'),
        ),
      ),
    );
    expect(provider.starts, 0);
  });

  test(
    'Blaze accepts two decimal reservations exactly at the batch cap',
    () async {
      final provider = FakeProvider();
      final control = controller(provider);
      for (var i = 0; i < 2; i++) {
        final result = await control.run(
          decimalBudgetPlan(id: 'qa-decimal-$i', perRun: 1.10, total: 2.20),
        );
        expect(result['phase'], 'COMPLETE');
        expect(result['reserved_usd_cents'], 110);
      }
      final rejected = await control.run(
        decimalBudgetPlan(id: 'qa-decimal-over', perRun: 0.10, total: 2.20),
      );
      expect(rejected['phase'], 'PREFLIGHT_FAILED');
      expect(provider.starts, 2);
    },
  );

  test(
    'Blaze rounds a fractional-cent total down without shrinking cents',
    () async {
      final provider = FakeProvider();
      final control = controller(provider);
      expect(
        (await control.run(
          decimalBudgetPlan(perRun: 0.29, total: 0.29),
        ))['phase'],
        'COMPLETE',
      );
      expect(
        (await control.run(
          decimalBudgetPlan(id: 'qa-fraction-over', perRun: 0.10, total: 0.389),
        ))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.starts, 1);
    },
  );

  test('Blaze rejects invalid USD inputs before provider calls', () async {
    final provider = FakeProvider();
    final control = controller(provider);
    var index = 0;
    for (final (field, value) in <(String, Object)>[
      ('maximum_run_usd', '1.10'),
      ('maximum_total_usd', '2.20'),
      ('maximum_run_usd', 0),
      ('maximum_total_usd', -1),
    ]) {
      final json =
          jsonDecode(jsonEncode(blazePlan(id: 'qa-invalid-${index++}').json))
              as Map<String, dynamic>;
      json['settings']['budget'][field] = value;
      expect(
        (await control.run(RemotePlan(json)))['phase'],
        'PREFLIGHT_FAILED',
      );
    }
    for (final (field, value) in <(String, double)>[
      ('maximum_run_usd', double.nan),
      ('maximum_total_usd', double.infinity),
    ]) {
      final json =
          jsonDecode(jsonEncode(blazePlan().json)) as Map<String, dynamic>;
      json['settings']['budget'][field] = value;
      expect(() => RemotePlan(json).validateBudget(now), throwsStateError);
    }
    expect(provider.calls, isEmpty);
  });

  test(
    'Blaze retains earlier integer reservations without recomputing USD',
    () async {
      final provider = FakeProvider();
      final control = controller(provider);
      await control.run(decimalBudgetPlan(perRun: 1.10, total: 2.20));
      final file = File(p.join(runs.path, 'qa-one', 'orchestration.json'));
      final previous = jsonDecode(file.readAsStringSync()) as Map;
      for (final cents in [111, 0x7fffffffffffffff]) {
        previous['reserved_usd_cents'] = cents;
        file.writeAsStringSync(jsonEncode(previous));
        expect(
          (await control.run(
            decimalBudgetPlan(id: 'qa-two-$cents', perRun: 1.10, total: 2.20),
          ))['phase'],
          'PREFLIGHT_FAILED',
          reason: 'Keep prior reservation $cents without integer overflow',
        );
      }
      expect(provider.starts, 1);
    },
  );

  test('billing mode is explicit and live account must match', () async {
    Map<String, dynamic> billing = {'billingEnabled': false};
    final provider = GcloudProvider(
      execute: (binary, args, {directory, timeout, environment}) async =>
          CommandResult(
            0,
            jsonEncode(
              args.first == 'billing'
                  ? billing
                  : [
                      {
                        'id': 'test-device',
                        'form': 'PHYSICAL',
                        'supportedVersionIds': ['35'],
                      },
                    ],
            ),
            '',
          ),
    );
    await provider.preflight(plan());
    await expectLater(provider.preflight(blazePlan()), throwsStateError);
    billing = {
      'billingEnabled': true,
      'billingAccountName': 'billingAccounts/123456-ABCDEF-123456',
    };
    await provider.preflight(blazePlan());
    await expectLater(provider.preflight(plan()), throwsStateError);
    billing['billingAccountName'] = 'billingAccounts/654321-ABCDEF-123456';
    await expectLater(provider.preflight(blazePlan()), throwsStateError);
  });

  test('Blaze rejects missing, stale, underpriced or unauthorized budgets', () {
    for (final edit in <void Function(Map)>[
      (s) => s.remove('budget'),
      (s) => s['budget']['funding'] = 'assumed_credit',
      (s) => s['budget']['maximum_run_usd'] = 1,
      (s) => s['budget']['maximum_total_usd'] = 1,
      (s) => s['budget']['maximum_total_usd'] = double.nan,
      (s) => s['budget']['maximum_run_usd'] = double.infinity,
      (s) => s['budget']['window_start'] = now
          .add(const Duration(minutes: 1))
          .toIso8601String(),
      (s) => s['budget']['expires_at'] = now
          .add(const Duration(minutes: 59))
          .toIso8601String(),
      (s) => s['budget']['expires_at'] = now
          .add(const Duration(days: 2))
          .toIso8601String(),
      (s) => s['budget']['verified_at'] = now
          .subtract(const Duration(minutes: 16))
          .toIso8601String(),
      (s) => s['credit']['applicable'] = false,
      (s) => s['credit']['available_usd'] = 11.99,
      (s) => s['quota']['remaining_physical'] = 0,
    ]) {
      final json =
          jsonDecode(jsonEncode(blazePlan().json)) as Map<String, dynamic>;
      edit(json['settings'] as Map);
      expect(() => RemotePlan(json).validateBudget(now), throwsStateError);
    }
    blazePlan().validateBudget(now);
    final paid =
        jsonDecode(jsonEncode(blazePlan(funding: 'approved_charges').json))
            as Map<String, dynamic>;
    (paid['settings'] as Map).remove('credit');
    RemotePlan(paid).validateBudget(now);
    for (final edit in <void Function(Map)>[
      (s) => s['billing_mode'] = 'Blaze',
      (s) => s.remove('billing_account'),
      (s) => s['billing_account'] = 'another-account',
    ]) {
      final json =
          jsonDecode(jsonEncode(blazePlan().json)) as Map<String, dynamic>;
      edit(json['settings'] as Map);
      expect(() => RemotePlan(json), throwsFormatException);
    }
  });

  test(
    'Blaze reserves gross cost across runs and keeps Spark count guard',
    () async {
      final provider = FakeProvider();
      final control = controller(provider);
      for (var i = 0; i < 4; i++) {
        expect(
          (await control.run(plan(id: 'qa-spark-$i')))['phase'],
          'COMPLETE',
        );
      }
      expect(
        (await control.run(plan(id: 'qa-spark-five')))['phase'],
        'PREFLIGHT_FAILED',
      );
      for (var i = 0; i < 3; i++) {
        final result = await control.run(blazePlan(id: 'qa-blaze-$i'));
        expect(result['phase'], 'COMPLETE');
        expect(result['reserved_usd_cents'], 200);
      }
      expect(
        (await control.run(blazePlan(id: 'qa-blaze-four')))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.starts, 7);
    },
  );

  test(
    'Blaze failed dispatch keeps reservation but preflight does not spend it',
    () async {
      final provider = FakeProvider()..preflightFails = true;
      final control = controller(provider);
      await control.run(blazePlan(id: 'qa-preflight'));
      provider.preflightFails = false;
      provider.uncertainStart = true;
      provider.checkpointBeforeFailure = true;
      for (var i = 0; i < 3; i++) {
        final result = await control.run(blazePlan(id: 'qa-failed-$i'));
        expect(result['cleanup'], 'VERIFIED');
        expect(result['dispatched_at'], isNotNull);
      }
      expect(
        (await control.run(blazePlan(id: 'qa-no-budget')))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.starts, 3);
    },
  );

  test(
    'Blaze persists its rounded reservation before provider mutation',
    () async {
      final json =
          jsonDecode(jsonEncode(blazePlan().json)) as Map<String, dynamic>;
      json['settings']['budget']['maximum_run_usd'] = 2.001;
      final provider = FakeProvider()
        ..onStart = (selected) {
          final saved =
              jsonDecode(
                    File(
                      p.join(runs.path, selected.runId, 'orchestration.json'),
                    ).readAsStringSync(),
                  )
                  as Map;
          expect(saved['phase'], 'SUBMITTING');
          expect(saved['reserved_usd_cents'], 201);
          expect(saved['dispatched_at'], isNotNull);
        };
      expect(
        (await controller(provider).run(RemotePlan(json)))['phase'],
        'COMPLETE',
      );
      expect(provider.starts, 1);
    },
  );

  test(
    'Blaze refuses a prior dispatch whose cost cannot be reconciled',
    () async {
      final provider = FakeProvider();
      final control = controller(provider);
      await control.run(blazePlan());
      final file = File(p.join(runs.path, 'qa-one', 'orchestration.json'));
      final previous = jsonDecode(file.readAsStringSync()) as Map;
      previous.remove('reserved_usd_cents');
      file.writeAsStringSync(jsonEncode(previous));
      expect(
        (await control.run(blazePlan(id: 'qa-two')))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.starts, 1);
    },
  );

  test('Blaze rechecks receipt freshness after slow preflight', () async {
    var current = now;
    final gate = Completer<void>();
    final provider = FakeProvider()..pausePreflight = gate;
    final control = RemoteController(runs, provider, now: () => current);
    final pending = control.run(blazePlan());
    current = now.add(const Duration(minutes: 16));
    gate.complete();
    expect((await pending)['phase'], 'PREFLIGHT_FAILED');
    expect(provider.starts, 0);
  });

  test(
    'Blaze free allowance supports bounded runs without assuming credit',
    () async {
      final json =
          jsonDecode(jsonEncode(blazePlan(funding: 'free_allowance').json))
              as Map<String, dynamic>;
      final settings = json['settings'] as Map;
      settings.remove('credit');
      settings['test_timeout_minutes'] = 10;
      settings['free_allowance'] = {
        'verified_at': now.toIso8601String(),
        'evidence':
            'all project test process durations checked, rounded per execution',
        'remaining_physical_minutes': 19,
      };
      final provider = FakeProvider();
      final control = controller(provider);
      final result = await control.run(RemotePlan(json));
      expect(result['phase'], 'COMPLETE');
      expect(result['reserved_physical_minutes'], 11);
      json['run_id'] = 'qa-two';
      expect(
        (await control.run(RemotePlan(json)))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.starts, 1);
      for (final edit in <void Function(Map)>[
        (s) => s.remove('free_allowance'),
        (s) => s['free_allowance']['remaining_physical_minutes'] = 10,
        (s) => s['free_allowance']['remaining_physical_minutes'] = 31,
        (s) => s['free_allowance']['remaining_physical_minutes'] = 19.5,
        (s) => s['free_allowance']['verified_at'] = now
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        (s) => s['free_allowance']['verified_at'] = now
            .subtract(const Duration(minutes: 16))
            .toIso8601String(),
      ]) {
        final invalid = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
        edit(invalid['settings'] as Map);
        expect(() => RemotePlan(invalid).validateBudget(now), throwsStateError);
      }
      for (final minutes in [0, 21, 10.5]) {
        settings['test_timeout_minutes'] = minutes;
        expect(() => RemotePlan(json), throwsFormatException);
      }
    },
  );

  test(
    'concurrent same-ID runs submit once and preserve the journal',
    () async {
      final gate = Completer<void>();
      final provider = FakeProvider()..pausePreflight = gate;
      final first = controller(provider).run(plan());
      try {
        await expectLater(controller(provider).run(plan()), throwsStateError);
      } finally {
        gate.complete();
      }
      await first;
      final file = File(p.join(runs.path, 'qa-one', 'orchestration.json'));
      final before = file.readAsStringSync();
      await expectLater(controller(provider).run(plan()), throwsStateError);
      expect(file.readAsStringSync(), before);
      expect(provider.starts, 1);
    },
  );

  test(
    'lost submission can reconcile and clean up without resubmitting',
    () async {
      final provider = FakeProvider()..uncertainStart = true;
      final control = controller(provider);
      final initial = await control.run(plan());
      expect(initial['cleanup'], 'UNKNOWN');
      final identified = await control.recover(
        'qa-one',
        'reconcile',
        remoteId: 'matrix-one',
      );
      expect((identified['remote'] as Map)['matrix_id'], 'matrix-one');
      expect(identified['qualified'], false);
      expect(identified['error'], isNotNull);
      final clean = await control.recover('qa-one', 'cleanup');
      expect(clean['cleanup'], 'VERIFIED');
      expect(provider.starts, 1);
      await expectLater(
        control.recover('qa-one', 'reconcile', remoteId: 'unrelated'),
        throwsStateError,
      );
      expect(provider.calls.where((call) => call == 'identify'), hasLength(1));
    },
  );

  test(
    'Firebase identity recovery verifies project, ID and unique run label',
    () async {
      Map<String, dynamic> fixture() => {
        'projectId': 'test-project',
        'testMatrixId': 'matrix-one',
        'clientInfo': {
          'clientInfoDetails': [
            {'key': 'matrixLabel', 'value': 'qa-one'},
          ],
        },
      };
      expect(
        (await MatrixProvider(
          fixture(),
        ).identify(plan(), 'matrix-one'))['matrix_id'],
        'matrix-one',
      );
      for (final invalid in [
        fixture()..['projectId'] = 'another-project',
        fixture()..['testMatrixId'] = 'another-matrix',
        fixture()
          ..['clientInfo'] = {
            'clientInfoDetails': [
              {'key': 'matrixLabel', 'value': 'another-run'},
            ],
          },
        fixture()..['clientInfo'] = {'clientInfoDetails': []},
      ]) {
        await expectLater(
          MatrixProvider(invalid).identify(plan(), 'matrix-one'),
          throwsStateError,
        );
      }
    },
  );

  test(
    'Firebase async URL receipts recover an owned Android or iOS matrix',
    () async {
      for (final target in ['firebase-android', 'firebase-ios']) {
        for (final timeoutMinutes in [10, 20]) {
          final calls = <List<String>>[];
          final checkpoints = <Map<String, dynamic>>[];
          final provider = MatrixProvider(
            {
              'projectId': 'test-project',
              'testMatrixId': 'matrix-one',
              'clientInfo': {
                'clientInfoDetails': [
                  {'key': 'matrixLabel', 'value': 'qa-one'},
                ],
              },
            },
            execute: (binary, args, {directory, timeout, environment}) async {
              calls.add(args);
              return CommandResult(
                0,
                jsonEncode(
                  'https://console.firebase.google.com/project/test-project/testlab/histories/history/matrices/execution',
                ),
                'Uploading test files...\nTest [matrix-one] has been created in the Google Cloud.\n',
              );
            },
          );
          final selected =
              jsonDecode(jsonEncode(plan(target: target).json))
                  as Map<String, dynamic>;
          selected['settings']['test_timeout_minutes'] = timeoutMinutes;
          final remote = await provider.start(
            RemotePlan(selected),
            checkpoints.add,
          );
          expect(remote['matrix_id'], 'matrix-one');
          expect(checkpoints.first, {'submission_candidate_id': 'matrix-one'});
          expect(checkpoints.last['matrix_id'], 'matrix-one');
          expect(calls, hasLength(1));
          expect(calls.single, contains('--async'));
          expect(calls.single, contains('--num-flaky-test-attempts=0'));
          expect(calls.single, contains('--timeout=${timeoutMinutes}m'));
          expect(
            calls.single.where((arg) => arg.startsWith('--device=')),
            hasLength(1),
          );
        }
      }
    },
  );

  test(
    'Firebase submission rejects ambiguous receipts and foreign ownership',
    () async {
      for (final receipt in [
        '',
        'Test [matrix-one] has been created in the Google Cloud.\nTest [matrix-two] has been created in the Google Cloud.\n',
        'Test [matrix-one] has been created in the Google Cloud.\n',
      ]) {
        final checkpoints = <Map<String, dynamic>>[];
        final provider = MatrixProvider(
          {
            'projectId': 'another-project',
            'testMatrixId': 'matrix-one',
            'clientInfo': {
              'clientInfoDetails': [
                {'key': 'matrixLabel', 'value': 'qa-one'},
              ],
            },
          },
          execute: (binary, args, {directory, timeout, environment}) async =>
              CommandResult(
                0,
                jsonEncode('https://console.firebase.google.com/'),
                receipt,
              ),
        );
        await expectLater(
          provider.start(plan(), checkpoints.add),
          throwsStateError,
        );
        expect(
          checkpoints.where((value) => value.containsKey('matrix_id')),
          isEmpty,
        );
      }
    },
  );

  test(
    'Firebase saves verified identity when gcloud fails after creation',
    () async {
      final checkpoints = <Map<String, dynamic>>[];
      final provider = MatrixProvider(
        {
          'projectId': 'test-project',
          'testMatrixId': 'matrix-one',
          'clientInfo': {
            'clientInfoDetails': [
              {'key': 'matrixLabel', 'value': 'qa-one'},
            ],
          },
        },
        execute: (binary, args, {directory, timeout, environment}) async =>
            const CommandResult(
              1,
              '',
              'Test [matrix-one] has been created in the Google Cloud.\n',
            ),
      );
      await expectLater(
        provider.start(plan(), checkpoints.add),
        throwsStateError,
      );
      expect(checkpoints.last['matrix_id'], 'matrix-one');
    },
  );

  test(
    'NPU bundles are blocked before provider preflight or submission',
    () async {
      const id = 'npu-qualcomm-sm8650';
      File(
        'packages/llamadart_validation/assets/profiles/$id.json',
      ).copySync(p.join(bundle.path, 'profile.json'));
      await writeBundleManifest(bundle, {
        'target': 'android',
        'profile': id,
        'source_dirty': false,
      });
      final provider = FakeProvider();
      final controller = RemoteController(runs, provider, now: () => now);
      final result = await controller.run(plan(profile: id));
      expect(result['qualified'], isNot(true));
      expect(result['error'], contains('StateError'));
      expect(provider.calls, isEmpty);
      expect(provider.starts, 0);
    },
  );

  test(
    'command host source fixtures preserve receipts and failure cleanup',
    () async {
      final result = await executeCommand('python3', <String>[
        'test/unit/tooling/validation_process_host_test.py',
      ], timeout: const Duration(seconds: 30));
      expect(result.code, 0, reason: result.error);
      expect(result.error, contains('OK'));
    },
    skip: Platform.isWindows ? 'The host fixtures are POSIX-only.' : false,
  );

  test('optional command receipt records only the returned host ID', () async {
    final receipts = <int>[];
    final result = await executeCommand(
      Platform.isWindows ? 'python' : 'python3',
      const <String>['-c', 'print("receipt fixture")'],
      onProcessStarted: receipts.add,
    );
    expect(receipts, hasLength(1));
    expect(receipts.single, greaterThan(0));
    expect(result.code, 0);
    expect(result.output.trim(), 'receipt fixture');
  });

  test('failed command receipt remains failed and retires its host', () async {
    int? hostId;
    final failure = FileSystemException('fixture publication failed');
    await expectLater(
      executeCommand(
        Platform.isWindows ? 'python' : 'python3',
        const <String>['-c', 'import time; time.sleep(10)'],
        onProcessStarted: (processId) {
          hostId = processId;
          throw failure;
        },
      ),
      throwsA(same(failure)),
    );
    expect(hostId, greaterThan(0));
    if (Platform.isWindows) {
      Future<String> tasks(int processId) async {
        final observed = await Process.run('tasklist', <String>[
          '/FI',
          'PID eq $processId',
          '/FO',
          'CSV',
          '/NH',
        ]);
        expect(observed.exitCode, 0);
        return observed.stdout.toString();
      }

      expect(await tasks(pid), contains('"$pid"'));
      expect(await tasks(hostId!), isNot(contains('"$hostId"')));
    } else {
      final observed = await Process.run('ps', <String>[
        '-p',
        '$hostId',
        '-o',
        'pid=',
      ]);
      expect(observed.stdout.toString().trim(), isEmpty);
      expect(observed.exitCode, 1);
    }
  });

  test('a failed command receipt releases the command pipes', () async {
    final result = await _runDartFixture(scratch, r'''
Future<void> main() async {
  Future<void> failReceipt() async {
    try {
      await executeCommand(
        'python3',
        const <String>['-c', 'print("pipe fixture")'],
        onProcessStarted: (_) => throw const FormatException('receipt'),
      );
    } on FormatException {
      return;
    }
    throw StateError('Receipt failure was not reported');
  }

  int openDescriptors() => Platform.isLinux
      ? Directory('/proc/self/fd').listSync(followLinks: false).length
      : (Process.runSync('lsof', <String>['-p', '$pid']).stdout as String)
            .split('\n')
            .length;

  await failReceipt();
  final before = openDescriptors();
  for (var i = 0; i < 10; i++) {
    await failReceipt();
  }
  print(openDescriptors() - before);
}
''');
    expect(result.exitCode, 0, reason: '${result.stderr}');
    // Each unreleased command leaves its stdout and stderr pipes open.
    expect(int.parse(result.stdout.toString().trim()), lessThan(10));
  }, skip: Platform.isWindows ? 'Counts POSIX file descriptors.' : false);

  test(
    'a receipt that outlasts the command deadline fails a clean exit',
    () async {
      final host = File(p.join(scratch.path, 'clean-host.py'))
        ..writeAsStringSync('print("clean")\n');
      await expectLater(
        runZoned(
          () => executeCommand(
            Platform.isWindows ? 'python' : 'python3',
            const <String>[],
            // The Dart deadline is this timeout plus ten seconds: 100 ms.
            timeout: const Duration(milliseconds: -9900),
            processHostEntryPath: host.path,
            onProcessStarted: (_) => sleep(const Duration(milliseconds: 300)),
          ),
          zoneSpecification: ZoneSpecification(
            // Hold back the timeout timer so the clean exit is observed first;
            // zero-duration timers schedule I/O events.
            createTimer: (self, parent, zone, duration, callback) =>
                parent.createTimer(
                  zone,
                  duration > Duration.zero ? const Duration(days: 1) : duration,
                  callback,
                ),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('a literal host entry needs no checked-in host', () async {
    final result = await _runDartFixture(
      scratch,
      '''
Future<void> main(List<String> arguments) async {
  final result = await executeCommand(
    arguments[0],
    const <String>['-c', 'print("literal host")'],
    timeout: const Duration(seconds: 5),
    processHostEntryPath: arguments[1],
  );
  stdout.write(result.output);
  exitCode = result.code;
}
''',
      arguments: <String>[
        Platform.isWindows ? 'python' : 'python3',
        File('tool/testing/validation/process_host.py').absolute.path,
      ],
      workingDirectory: scratch.path,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(result.stdout.toString().trim(), 'literal host');
  });

  test('default command host retains output and exit status', () async {
    final newline = Platform.isWindows ? '\r\n' : '\n';
    final binary = Platform.isWindows ? 'python' : 'python3';
    const arguments = <String>[
      '-c',
      'import sys; print("out"); print("err", file=sys.stderr); sys.exit(17)',
    ];
    final defaultResult = await executeCommand(
      binary,
      arguments,
      timeout: const Duration(seconds: 5),
    );
    final explicitResult = await executeCommand(
      binary,
      arguments,
      timeout: const Duration(seconds: 5),
      processHostEntryPath: File(
        'tool/testing/validation/process_host.py',
      ).absolute.path,
    );
    expect(defaultResult.code, 17);
    expect(defaultResult.output, 'out$newline');
    expect(defaultResult.error, 'err$newline');
    expect(explicitResult.code, defaultResult.code);
    expect(explicitResult.output, defaultResult.output);
    expect(explicitResult.error, defaultResult.error);
  });

  test('command environment adds to the inherited environment', () async {
    final result = await executeCommand(
      Platform.isWindows ? 'python' : 'python3',
      const <String>[
        '-c',
        'import os; '
            'print(os.environ.get("LLAMADART_COMMAND_FIXTURE")); '
            'print(os.environ.get("PATH") == os.environ.get("PARENT_PATH"))',
      ],
      timeout: const Duration(seconds: 5),
      environment: <String, String>{
        'LLAMADART_COMMAND_FIXTURE': 'passed',
        'PARENT_PATH': Platform.environment['PATH']!,
      },
    );
    expect(result.code, 0, reason: result.error);
    expect(const LineSplitter().convert(result.output), <String>[
      'passed',
      'True',
    ]);
  });

  test('literal host entry binds its maintained direct-child callback', () async {
    final newline = Platform.isWindows ? '\r\n' : '\n';
    final wrapper = File(p.join(scratch.path, 'private-host.py'));
    final receipt = File(p.join(scratch.path, 'child-receipt.json'));
    _writeReceiptHostEntry(wrapper, receipt);
    final returnedHostIds = <int>[];
    final result = await executeCommand(
      Platform.isWindows ? 'python' : 'python3',
      const <String>[
        '-c',
        'import sys; print("out"); print("err", file=sys.stderr); sys.exit(17)',
      ],
      timeout: const Duration(seconds: 5),
      processHostEntryPath: wrapper.path,
      onProcessStarted: returnedHostIds.add,
    );
    expect(result.code, 17);
    expect(result.output, 'out$newline');
    expect(result.error, 'err$newline');
    expect(returnedHostIds, hasLength(1));
    final recorded = jsonDecode(receipt.readAsStringSync()) as Map;
    expect(recorded.keys, unorderedEquals(<String>['host_pid', 'child_pid']));
    expect(recorded['host_pid'], returnedHostIds.single);
    expect(recorded['child_pid'], greaterThan(0));
    expect(recorded['child_pid'], isNot(returnedHostIds.single));
  });

  test(
    'private host receipt failure stays failed and retires its child',
    () async {
      final wrapper = File(p.join(scratch.path, 'failing-private-host.py'));
      final observed = File(p.join(scratch.path, 'observed-child.json'));
      final occupied = File(p.join(scratch.path, 'occupied-receipt.json'))
        ..writeAsStringSync('existing receipt');
      _writeReceiptHostEntry(
        wrapper,
        observed,
        publicationDestination: occupied,
      );
      final returnedHostIds = <int>[];
      await expectLater(
        executeCommand(
          'python3',
          const <String>['-c', 'import time; time.sleep(10)'],
          timeout: const Duration(seconds: 5),
          processHostEntryPath: wrapper.path,
          onProcessStarted: returnedHostIds.add,
        ),
        throwsStateError,
      );
      expect(occupied.readAsStringSync(), 'existing receipt');
      expect(returnedHostIds, hasLength(1));
      final recorded = jsonDecode(observed.readAsStringSync()) as Map;
      expect(recorded['host_pid'], returnedHostIds.single);
      expect(recorded['child_pid'], greaterThan(0));
      for (final processId in <int>[
        returnedHostIds.single,
        recorded['child_pid'] as int,
      ]) {
        final remaining = await Process.run('ps', <String>[
          '-p',
          '$processId',
          '-o',
          'pid=',
        ]);
        expect(remaining.stdout.toString().trim(), isEmpty);
        expect(remaining.exitCode, 1);
      }
    },
    skip: Platform.isWindows ? 'Probes POSIX process IDs with ps.' : false,
  );

  test('SIGTERM on the command host terminates owned descendants', () async {
    final ready = File(p.join(scratch.path, 'ready'));
    final leaked = File(p.join(scratch.path, 'leaked'));
    final script =
        'from pathlib import Path; import time; '
        'Path(${jsonEncode(ready.path)}).write_text("ready"); '
        'time.sleep(1); Path(${jsonEncode(leaked.path)}).write_text("leaked")';
    final host = await Process.start('python3', [
      'tool/testing/validation/process_host.py',
      '30',
      'python3',
      '-c',
      script,
    ]);
    final out = host.stdout.drain<void>();
    final err = host.stderr.drain<void>();
    try {
      for (var i = 0; i < 100 && !ready.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(ready.existsSync(), true);
      host.kill(ProcessSignal.sigterm);
      expect(await host.exitCode.timeout(const Duration(seconds: 3)), 143);
      await Future.wait([out, err]);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(leaked.existsSync(), false);
    } finally {
      host.kill(ProcessSignal.sigkill);
    }
  }, skip: Platform.isWindows ? 'Windows has no SIGTERM delivery.' : false);

  test(
    'successful lifecycle requires provider, suite, retrieval and cleanup',
    () async {
      final provider = FakeProvider();
      final result = await controller(provider).run(plan());
      expect(result['qualified'], true);
      expect(provider.calls, [
        'preflight',
        'start',
        'status',
        'collect',
        'cleanup',
      ]);
      expect(
        File(p.join(runs.path, 'qa-one', 'cleanup.json')).existsSync(),
        true,
      );
    },
  );
  test('provider failure remains failed even with a passing suite', () async {
    final provider = FakeProvider()..successful = false;
    final result = await controller(provider).run(plan());
    expect(result['qualified'], false);
    expect(result['phase'], 'FAILED');
  });
  test('missing assertions cannot be replaced by provider success', () async {
    final result = await controller(FakeProvider(), pass: false).run(plan());
    expect(result['qualified'], false);
  });
  test('preflight failure performs no mutation', () async {
    final provider = FakeProvider()..preflightFails = true;
    final result = await controller(provider).run(plan());
    expect(provider.starts, 0);
    expect(result['cleanup'], 'NOT_REQUIRED');
  });
  test('unknown submission is not retried and blocks a fresh run', () async {
    final provider = FakeProvider()..uncertainStart = true;
    final control = controller(provider);
    expect((await control.run(plan()))['cleanup'], 'UNKNOWN');
    expect(
      (await control.run(plan(id: 'qa-two')))['phase'],
      'PREFLIGHT_FAILED',
    );
    expect(provider.starts, 1);
    await expectLater(control.run(plan()), throwsStateError);
  });
  test(
    'Firebase checkpoint survives bootstrap failure and collects after cleanup',
    () async {
      final provider = FakeProvider()
        ..uncertainStart = true
        ..checkpointBeforeFailure = true;
      final result = await controller(provider).run(plan());
      expect(provider.cleanupRemote?['matrix_id'], 'matrix-one');
      expect(provider.calls, [
        'preflight',
        'start',
        'cleanup',
        'status',
        'collect',
      ]);
      expect(result['qualified'], false);
      expect(result['cleanup'], 'VERIFIED');
    },
  );
  test('collection failure still cleans up and stays failed', () async {
    final provider = FakeProvider()..collectionFails = true;
    final result = await controller(provider).run(plan());
    expect(
      provider.calls,
      containsAllInOrder(['cleanup', 'status', 'collect']),
    );
    expect(result['qualified'], false);
    expect(result['collection'], 'INCOMPLETE');
  });
  test(
    'transient status failures retry reads only and preserve safe evidence',
    () async {
      final provider = FakeProvider()
        ..statusErrors.addAll([
          const RemoteProviderFailure(RemoteFailureKind.http, httpStatus: 503),
          const RemoteProviderFailure(RemoteFailureKind.transport),
        ]);
      final result = await controller(provider).run(plan());
      expect(result['qualified'], true);
      expect(provider.starts, 1);
      expect(provider.calls.where((c) => c == 'status'), hasLength(3));
      expect((result['poll_failures'] as List).first['http_status'], 503);
      expect(result['error'], isNull);
    },
  );
  test(
    'permanent and exhausted poll failures clean up before final collection',
    () async {
      for (final errors in [
        [const RemoteProviderFailure(RemoteFailureKind.http, httpStatus: 403)],
        List.filled(3, const RemoteProviderFailure(RemoteFailureKind.timeout)),
      ]) {
        final provider = FakeProvider()..statusErrors.addAll(errors);
        final result = await controller(
          provider,
        ).run(plan(id: 'qa-fail-${errors.length}'));
        expect(provider.starts, 1);
        expect(result['qualified'], false);
        expect(result['cleanup'], 'VERIFIED');
        expect(result['collection'], 'COMPLETE');
        expect((result['poll_failures'] as List), hasLength(errors.length));
        expect(
          provider.calls,
          containsAllInOrder(['cleanup', 'status', 'collect']),
        );
        expect(result['failure']['operation'], 'RUNNING');
      }
    },
  );
  test('poll retry cannot extend the original deadline', () async {
    var time = now;
    final provider = FakeProvider()
      ..statusErrors.add(
        const RemoteProviderFailure(RemoteFailureKind.timeout),
      );
    final control = RemoteController(
      runs,
      provider,
      now: () => time,
      delay: (_) async {
        time = time.add(const Duration(hours: 1));
      },
      assess: (_, _) async => true,
    );
    final result = await control.run(plan());
    expect(result['qualified'], false);
    expect(provider.starts, 1);
    expect(provider.calls.where((c) => c == 'status'), hasLength(2));
    expect(result['failure']['error_type'], 'TimeoutException');
  });
  test(
    'matrix errors exclude response and token secrets from diagnostics',
    () async {
      for (final status in [403, 429, 503]) {
        final provider = GcloudProvider(
          execute: (_, _, {directory, timeout, environment}) async =>
              const CommandResult(0, 'secret-token', ''),
          createHttpClient: () => MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer secret-token');
            return http.Response('secret-response https://secret-url', status);
          }),
        );
        try {
          await provider.matrix(plan(), 'matrix-one');
          fail('Expected classified error');
        } on RemoteProviderFailure catch (error) {
          expect(error.httpStatus, status);
          expect(error.retryable, status != 403);
          expect(jsonEncode(error.toJson()), isNot(contains('secret')));
        }
      }
    },
  );
  test(
    'provider refuses to collect a pre-terminal Firebase snapshot',
    () async {
      var transferred = false;
      final provider = MatrixProvider(
        {'state': 'PENDING'},
        execute: (_, _, {directory, timeout, environment}) async {
          transferred = true;
          return const CommandResult(0, '', '');
        },
      );
      await expectLater(
        provider.collect(plan(), {'matrix_id': 'matrix-one'}, scratch),
        throwsStateError,
      );
      expect(transferred, false);
    },
  );
  test(
    'recovery never submits and cleanup failure blocks replacement',
    () async {
      final provider = FakeProvider()..cleanupVerified = false;
      final control = controller(provider);
      await control.run(plan());
      await control.recover('qa-one', 'status');
      expect(
        (await control.run(plan(id: 'qa-two')))['phase'],
        'PREFLIGHT_FAILED',
      );
      provider.cleanupVerified = true;
      expect(
        (await control.recover('qa-one', 'cleanup'))['cleanup'],
        'VERIFIED',
      );
      expect(provider.starts, 1);
    },
  );
  test(
    'Firebase recovery replaces legacy pending collection evidence',
    () async {
      final provider = FakeProvider();
      final control = controller(provider);
      await control.run(plan());
      final journal = File(p.join(runs.path, 'qa-one', 'orchestration.json'));
      final legacy =
          jsonDecode(journal.readAsStringSync()) as Map<String, dynamic>;
      legacy['remote'] = {
        'matrix_id': 'matrix-one',
        'state': 'PENDING',
        'terminal': false,
        'matrix': {'state': 'PENDING'},
      };
      journal.writeAsStringSync(jsonEncode(legacy));
      provider.statusOverride = {
        'state': 'FINISHED',
        'terminal': true,
        'matrix': {
          'state': 'FINISHED',
          'outcomeSummary': 'INCONCLUSIVE',
          'testExecutions': [
            {'state': 'CANCELLED'},
          ],
        },
      };
      provider.calls.clear();
      final cleaned = await control.recover('qa-one', 'cleanup');
      expect(cleaned['collection'], 'INCOMPLETE');
      expect(cleaned['qualified'], false);
      expect(cleaned['remote']['state'], 'FINISHED');
      expect(provider.calls, ['cleanup', 'status']);
      final collected = await control.recover('qa-one', 'collect');
      expect(collected['collection'], 'COMPLETE');
      expect(collected['remote']['matrix']['outcomeSummary'], 'INCONCLUSIVE');
      expect(collected['qualified'], false);
      expect(collected['phase'], 'FAILED');
      expect(provider.starts, 1);
      provider.statusOverride = {'state': 'PENDING', 'terminal': false};
      await expectLater(control.recover('qa-one', 'collect'), throwsStateError);
      expect(control.read('qa-one')['collection'], 'INCOMPLETE');
      expect(control.read('qa-one')['qualified'], false);
    },
  );
  test('stale credit and insufficient quota fail locally', () {
    expect(
      () => plan(
        target: 'gce-linux-cuda',
      ).validateBudget(now.add(const Duration(minutes: 16))),
      throwsStateError,
    );
    final json = jsonDecode(jsonEncode(plan().json)) as Map<String, dynamic>;
    (json['settings']['quota'] as Map)['remaining_physical'] = 0;
    expect(() => RemotePlan(json).validateBudget(now), throwsStateError);
  });
  test(
    'altered bundle and mobile profile mismatch fail before provider',
    () async {
      final provider = FakeProvider();
      final selected = plan();
      File(p.join(bundle.path, 'app.apk')).writeAsStringSync('changed');
      expect(
        (await controller(provider).run(selected))['phase'],
        'PREFLIGHT_FAILED',
      );
      await writeBundleManifest(bundle, {
        'target': 'android',
        'profile': 'tiny-gguf-cpu',
      });
      expect(
        (await controller(
          provider,
        ).run(plan(id: 'qa-two', profile: 'tiny-gguf-cuda')))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.calls, isEmpty);
    },
  );
  test(
    'wrong desktop OS and CPU profile on CUDA target fail before provisioning',
    () async {
      final provider = FakeProvider();
      await writeBundleManifest(bundle, {
        'target': 'desktop',
        'source_dirty': false,
        'build_os': 'macos',
        'build_abi': 'macos_arm64',
      });
      expect(
        (await controller(
          provider,
        ).run(plan(target: 'gce-linux-cuda')))['phase'],
        'PREFLIGHT_FAILED',
      );
      final assets = Directory(p.join(bundle.path, 'assets/profiles'))
        ..createSync(recursive: true);
      File(
        p.join(bundle.path, 'profile.json'),
      ).copySync(p.join(assets.path, 'tiny-gguf-cpu.json'));
      await writeBundleManifest(bundle, {
        'target': 'desktop',
        'source_dirty': false,
        'build_os': 'linux',
        'build_abi': 'linux_x64',
      });
      expect(
        (await controller(
          provider,
        ).run(plan(id: 'qa-two', target: 'gce-linux-cuda')))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.calls, isEmpty);
    },
  );
  test('Firebase rejects WebGPU chat bundles before preflight', () async {
    for (final (target, id, rejected) in [
      ('firebase-android', 'chat-gguf-webgpu', true),
      ('firebase-ios', 'chat-gguf-webgpu', true),
      ('firebase-android', 'chat-gguf-vulkan', false),
    ]) {
      File(
        'packages/llamadart_validation/assets/profiles/$id.json',
      ).copySync(p.join(bundle.path, 'profile.json'));
      await writeBundleManifest(bundle, {
        'target': target.substring(9),
        'profile': id,
        'source_dirty': false,
      });
      final provider = FakeProvider()..preflightFails = true;
      final state = await controller(provider).run(
        plan(id: 'qa-${target.substring(9)}-$id', target: target, profile: id),
      );
      expect(state['phase'], 'PREFLIGHT_FAILED', reason: id);
      expect(provider.calls, rejected ? isEmpty : ['preflight'], reason: id);
    }
  });
  test(
    'GCE accepts the CUDA decision profile and rejects its CPU and WebGPU twins',
    () async {
      final assets = Directory(p.join(bundle.path, 'assets/profiles'))
        ..createSync(recursive: true);
      for (final backend in ['cpu', 'cuda', 'webgpu']) {
        File(
          'packages/llamadart_validation/assets/profiles/decision-gguf-$backend.json',
        ).copySync(p.join(assets.path, 'decision-gguf-$backend.json'));
      }
      await writeBundleManifest(bundle, {
        'target': 'desktop',
        'source_dirty': false,
        'build_os': 'linux',
        'build_abi': 'linux_x64',
      });
      final provider = FakeProvider()..preflightFails = true;
      await controller(
        provider,
      ).run(plan(target: 'gce-linux-cuda', profile: 'decision-gguf-cuda'));
      expect(provider.calls, ['preflight']);
      expect(
        (await controller(provider).run(
          plan(
            id: 'qa-two',
            target: 'gce-linux-cuda',
            profile: 'decision-gguf-cpu',
          ),
        ))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(
        (await controller(provider).run(
          plan(
            id: 'qa-three',
            target: 'gce-linux-cuda',
            profile: 'decision-gguf-webgpu',
          ),
        ))['phase'],
        'PREFLIGHT_FAILED',
      );
      expect(provider.calls, ['preflight']);
    },
  );
  for (final target in ['gce-windows-cuda', 'gce-linux-cuda']) {
    test(
      '$target selects the supported transfer protocol for upload and collection',
      () async {
        final transfers = <List<String>>[];
        final provider = GcloudProvider(
          execute: (_, args, {directory, timeout, environment}) async {
            if (args.contains('scp')) {
              transfers.add(args);
              // Stop before executing the uploaded fixture, and exercise the
              // real upload failure path as well as successful collection.
              return CommandResult(transfers.length == 1 ? 1 : 0, '', '');
            }
            if (args.contains('create')) {
              return CommandResult(
                0,
                jsonEncode([
                  {
                    'id': '123',
                    'disks': [
                      {'source': 'owned-boot'},
                    ],
                    'scheduling': {
                      'instanceTerminationAction': 'DELETE',
                      'terminationTime': '2026-09-18T14:00:00Z',
                    },
                  },
                ]),
                '',
              );
            }
            if (args.any((a) => a.contains('nvidia-smi'))) {
              return const CommandResult(0, '550', '');
            }
            return const CommandResult(0, '', '');
          },
        );
        await expectLater(
          provider.start(plan(target: target), (_) {}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Bundle upload failed',
            ),
          ),
        );
        await provider.collect(plan(target: target), {}, scratch);
        expect(transfers, hasLength(2));
        for (final args in transfers) {
          expect(args.contains('--scp-flag=-O'), target == 'gce-windows-cuda');
          expect(args, contains('--tunnel-through-iap'));
        }
        expect(transfers.first, contains('qa-one:validation/qa-one/'));
        expect(transfers.last, contains('qa-one:validation/qa-one/results'));
      },
    );
  }
  test(
    'uncertain GCE creation cannot be cleared by an empty inventory',
    () async {
      final provider = GcloudProvider(
        execute: (binary, args, {directory, timeout, environment}) async =>
            const CommandResult(0, '[]', ''),
      );
      expect(
        (await provider.cleanup(
          plan(target: 'gce-linux-cuda'),
          {},
        ))['verified'],
        false,
      );
    },
  );
  test('cleanup refuses a changed or auxiliary boot disk', () async {
    final calls = <List<String>>[];
    final provider = GcloudProvider(
      execute: (binary, args, {directory, timeout, environment}) async {
        calls.add(args);
        return CommandResult(
          0,
          jsonEncode([
            {
              'id': '123',
              'labels': {'llamadart-validation': 'qa-one'},
              'zone':
                  'https://compute.googleapis.com/compute/v1/projects/test-project/zones/us-central1-a',
              'disks': [
                {
                  'boot': true,
                  'autoDelete': true,
                  'source':
                      'projects/test-project/zones/us-central1-a/disks/valuable-data',
                },
              ],
            },
          ]),
          '',
        );
      },
    );
    expect(
      (await provider.cleanup(plan(target: 'gce-linux-cuda'), {
        'instance_id': '123',
        'creation_confirmed': true,
        'disks': [
          'projects/test-project/zones/us-central1-a/disks/valuable-data',
        ],
      }))['verified'],
      false,
    );
    expect(calls.any((c) => c.contains('delete')), false);
  });
  test(
    'total process deadline includes inherited pipes and kills descendants',
    () async {
      final marker = p.join(scratch.path, 'should-not-exist');
      final code =
          'import subprocess,sys; subprocess.Popen([sys.executable,"-c",${jsonEncode('import time; from pathlib import Path; time.sleep(1); Path(${jsonEncode(marker)}).write_text("leaked")')}])';
      final watch = Stopwatch()..start();
      await expectLater(
        executeCommand('python3', [
          '-c',
          code,
        ], timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(File(marker).existsSync(), false);
    },
    skip: Platform.isWindows
        ? 'Windows job containment runs in validation bundle CI.'
        : false,
  );
}

Future<ProcessResult> _runDartFixture(
  Directory scratch,
  String source, {
  List<String> arguments = const <String>[],
  String? workingDirectory,
}) {
  final script = File(p.join(scratch.path, 'command_fixture.dart'))
    ..writeAsStringSync('''
import 'dart:io';

import '${File('tool/testing/validation/process.dart').absolute.uri}';

$source''');
  return Process.run(Platform.resolvedExecutable, <String>[
    '--packages=${File('.dart_tool/package_config.json').absolute.path}',
    script.path,
    ...arguments,
  ], workingDirectory: workingDirectory);
}

void _writeReceiptHostEntry(
  File wrapper,
  File childReceipt, {
  File? publicationDestination,
}) {
  final hostPath = File(
    'tool/testing/validation/process_host.py',
  ).absolute.path;
  final publication = publicationDestination == null
      ? ''
      : '''
    with pathlib.Path(${jsonEncode(publicationDestination.path)}).open('x') as stream:
        json.dump({'child_pid': child_pid}, stream)
''';
  wrapper.writeAsStringSync('''
import importlib.util, json, os, pathlib, sys
spec = importlib.util.spec_from_file_location('maintained_fixture_host', ${jsonEncode(hostPath)})
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
def receipt(child_pid):
    with pathlib.Path(${jsonEncode(childReceipt.path)}).open('x') as stream:
        json.dump({'host_pid': os.getpid(), 'child_pid': child_pid}, stream)
$publication
try:
    sys.exit(host.main(on_child_started=receipt))
except Exception as error:
    print('Subprocess host failed (' + type(error).__name__ + ')', file=sys.stderr)
    sys.exit(125)
''');
}
