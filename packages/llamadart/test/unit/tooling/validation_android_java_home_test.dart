@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/testing/validation/bundle.dart';
import '../../../tool/testing/validation/process.dart';

void main() {
  late Directory scratch;
  late String configJdk;
  late String doctorJdk;
  late String envJdk;

  String makeJdk(String name) {
    final home = p.join(scratch.path, name);
    File(
      p.join(home, 'bin', Platform.isWindows ? 'java.exe' : 'java'),
    ).createSync(recursive: true);
    return home;
  }

  String javaBinary(String home) =>
      p.join(home, 'bin', Platform.isWindows ? 'java.exe' : 'java');

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('validation-java-home-');
    configJdk = makeJdk('config-jdk');
    doctorJdk = makeJdk('doctor-jdk');
    envJdk = makeJdk('env-jdk');
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  CommandExecutor flutter({
    String? jdkDir,
    String? doctorJava,
    String lineEnding = '\n',
  }) => (binary, args, {directory, timeout, environment}) async {
    expect(binary, 'flutter');
    if (args.join(' ') == 'config --machine') {
      return CommandResult(
        0,
        'Analytics banner\n${jsonEncode({'android-sdk': '/sdk', 'jdk-dir': ?jdkDir})}',
        '',
      );
    }
    if (args.join(' ') == 'doctor -v') {
      return CommandResult(
        0,
        doctorJava == null
            ? '[!] Android toolchain$lineEnding'
            : '[✓] Android toolchain$lineEnding'
                  '    • Java binary at: $doctorJava$lineEnding',
        '',
      );
    }
    throw StateError('Unexpected command: $binary $args');
  };

  group('resolveAndroidJavaHome', () {
    test('prefers flutter config --jdk-dir', () async {
      expect(
        await resolveAndroidJavaHome(
          execute: flutter(
            jdkDir: configJdk,
            doctorJava: javaBinary(doctorJdk),
          ),
          environment: {'JAVA_HOME': envJdk},
        ),
        configJdk,
      );
    });

    test('uses the Java binary flutter doctor reports', () async {
      expect(
        await resolveAndroidJavaHome(
          execute: flutter(doctorJava: javaBinary(doctorJdk)),
          environment: {'JAVA_HOME': envJdk},
        ),
        doctorJdk,
      );
    });

    test('parses CRLF flutter doctor output', () async {
      expect(
        await resolveAndroidJavaHome(
          execute: flutter(
            doctorJava: javaBinary(doctorJdk),
            lineEnding: '\r\n',
          ),
          environment: {'JAVA_HOME': envJdk},
        ),
        doctorJdk,
      );
    });

    test('skips Flutter candidates that are not JDK homes', () async {
      expect(
        await resolveAndroidJavaHome(
          execute: flutter(
            jdkDir: p.join(scratch.path, 'missing'),
            doctorJava: javaBinary(p.join(scratch.path, 'gone')),
          ),
          environment: {'JAVA_HOME': envJdk},
        ),
        envJdk,
      );
    });

    test('fails with an actionable message when no JDK is found', () async {
      await expectLater(
        resolveAndroidJavaHome(
          execute: flutter(),
          environment: {'JAVA_HOME': p.join(scratch.path, 'missing')},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('flutter config --jdk-dir'), contains('JAVA_HOME')),
          ),
        ),
      );
    });
  });

  group('Android bundle Gradle step', () {
    late String root;
    late List<(String, List<String>, Map<String, String>?)> commands;

    setUp(() {
      root = p.join(scratch.path, 'checkout');
      for (final path in [
        '.flutter-version',
        'hook/build.dart',
        'lib/src/hook/native_release_pins.dart',
        'scripts/fetch_webgpu_bridge_assets.sh',
        'packages/llamadart_validation/pubspec.lock',
        'packages/llamadart_validation/assets/profiles/tiny-gguf-cpu.json',
        'example/chat_app/pubspec.lock',
      ]) {
        final target = File(p.join(root, path));
        target.parent.createSync(recursive: true);
        File(path).copySync(target.path);
      }
      commands = [];
    });

    CommandExecutor build({String? jdkDir}) =>
        (binary, args, {directory, timeout, environment}) async {
          commands.add((binary, args, environment));
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
          if (binary == 'flutter' && args.first == 'config') {
            return CommandResult(0, jsonEncode({'jdk-dir': ?jdkDir}), '');
          }
          final outputs = p.join(root, 'example/chat_app/build/app/outputs');
          final built = [
            if (binary == 'flutter' && args.first == 'build')
              p.join(outputs, 'flutter-apk', 'app-debug.apk'),
            if ([binary, ...args].any((arg) => arg.contains('gradlew'))) ...[
              p.join(outputs, 'flutter-apk', 'app-debug.apk'),
              p.join(
                outputs,
                'apk',
                'androidTest',
                'debug',
                'app-debug-androidTest.apk',
              ),
            ],
          ];
          for (final path in built) {
            File(path).createSync(recursive: true);
          }
          return const CommandResult(0, '', '');
        };

    Future<(String, List<String>, Map<String, String>?)> gradleStep(
      Map<String, String> environment,
    ) async {
      await buildValidationBundle(
        root,
        'android',
        p.join(scratch.path, 'out'),
        execute: build(jdkDir: configJdk),
        environment: environment,
      );
      return commands.singleWhere(
        (command) => command.$2.contains('app:assembleAndroidTest'),
      );
    }

    final gradlew = Platform.isWindows ? 'gradlew.bat' : './gradlew';

    test('passes the Flutter JDK to Gradle when JAVA_HOME is unset', () async {
      final gradle = await gradleStep(const {});
      expect(gradle.$1, gradlew);
      expect(gradle.$2.first, 'app:assembleAndroidTest');
      expect(gradle.$3, containsPair('JAVA_HOME', configJdk));
    });

    test('replaces a JAVA_HOME that differs from the Flutter JDK', () async {
      final gradle = await gradleStep({'JAVA_HOME': envJdk});
      expect(gradle.$1, gradlew);
      expect(gradle.$3, containsPair('JAVA_HOME', configJdk));
    });

    test('fails before any Android build without a JDK', () async {
      await expectLater(
        buildValidationBundle(
          root,
          'android',
          p.join(scratch.path, 'out'),
          execute: build(),
          environment: const {},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('JAVA_HOME'),
          ),
        ),
      );
      expect(
        commands.where(
          (command) =>
              command.$2.contains('build') ||
              command.$2.contains('app:assembleAndroidTest'),
        ),
        isEmpty,
      );
    });
  });
}
