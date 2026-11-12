@TestOn('vm')
library;

import 'dart:io';

import 'package:llamadart/src/core/models/download/model_download_manager_base.dart';
import 'package:llamadart/src/platform/io/mobile_app_cache_directory.dart';
import 'package:test/test.dart';

const String _package = 'com.example.app';
const String _flutterCodeCache = '/data/user/0/$_package/code_cache';
const String _status =
    'Name:\tcom.example.app\nUid:\t10218\t10218\t10218\t10218\n';
const String _secondaryUserStatus =
    'Name:\tcom.example.app\nUid:\t1010218\t1010218\t1010218\t1010218\n';

bool Function(String) _existing(Set<String> directories) =>
    directories.contains;

void main() {
  group('androidAppCacheDirectory', () {
    test('uses the data dir that holds the runtime temp directory', () {
      expect(
        androidAppCacheDirectory(
          cmdline: '$_package\u0000\u0000',
          status: _status,
          runtimeDirectories: const <String?>[_flutterCodeCache, null],
          directoryExists: _existing(<String>{'/data/user/0/$_package'}),
        ),
        '/data/user/0/$_package/cache',
      );
    });

    test('follows apps moved to adopted storage', () {
      const adopted = '/mnt/expand/1234-abcd/user/0/$_package';
      expect(
        androidAppCacheDirectory(
          cmdline: _package,
          status: _status,
          runtimeDirectories: const <String?>['$adopted/code_cache/'],
          directoryExists: _existing(<String>{adopted}),
        ),
        '$adopted/cache',
      );
    });

    test('derives the data dir from the package and user without '
        'a runtime directory', () {
      expect(
        androidAppCacheDirectory(
          cmdline: '$_package:remote\u0000',
          status: _secondaryUserStatus,
          runtimeDirectories: const <String?>['/data/local/tmp'],
          directoryExists: _existing(<String>{'/data/user/10/$_package'}),
        ),
        '/data/user/10/$_package/cache',
      );
      expect(
        androidAppCacheDirectory(
          cmdline: _package,
          status: null,
          runtimeDirectories: const <String?>[],
          directoryExists: _existing(<String>{'/data/data/$_package'}),
        ),
        '/data/data/$_package/cache',
      );
    });

    test('uses /data/data only for the primary user', () {
      expect(
        androidAppCacheDirectory(
          cmdline: _package,
          status: _secondaryUserStatus,
          runtimeDirectories: const <String?>[],
          directoryExists: _existing(<String>{'/data/data/$_package'}),
        ),
        isNull,
      );
      expect(
        androidAppCacheDirectory(
          cmdline: _package,
          status: _status,
          runtimeDirectories: const <String?>[],
          directoryExists: _existing(<String>{'/data/data/$_package'}),
        ),
        '/data/data/$_package/cache',
      );
    });

    test('returns null for a process that is not an app package', () {
      for (final cmdline in <String?>[
        null,
        '',
        '/data/local/tmp/dart\u0000main.dart',
        'app_process',
      ]) {
        expect(
          androidAppCacheDirectory(
            cmdline: cmdline,
            status: _status,
            runtimeDirectories: const <String?>[_flutterCodeCache],
            directoryExists: (_) => true,
          ),
          isNull,
          reason: cmdline,
        );
      }
    });

    test('returns null when no data dir exists', () {
      expect(
        androidAppCacheDirectory(
          cmdline: _package,
          status: _status,
          runtimeDirectories: const <String?>[_flutterCodeCache],
          directoryExists: (_) => false,
        ),
        isNull,
      );
    });
  });

  group('iosAppCacheDirectory', () {
    const home = '/var/mobile/Containers/Data/Application/ABC';

    test('uses Library/Caches in the app container', () {
      expect(
        iosAppCacheDirectory(
          home: home,
          directoryExists: _existing(<String>{'$home/Library/Caches'}),
        ),
        '$home/Library/Caches',
      );
    });

    test('returns null without a home or Library/Caches', () {
      expect(
        iosAppCacheDirectory(home: null, directoryExists: (_) => true),
        isNull,
      );
      expect(
        iosAppCacheDirectory(home: '', directoryExists: (_) => true),
        isNull,
      );
      expect(
        iosAppCacheDirectory(home: home, directoryExists: (_) => false),
        isNull,
      );
    });
  });

  group('environmentVariable', () {
    test('prefers the given environment', () {
      expect(
        environmentVariable(
          'HOME',
          environment: const <String, String>{'HOME': '/given'},
        ),
        '/given',
      );
    });

    test(
      'reads libc getenv when the Dart environment lacks the name, as on iOS',
      () {
        expect(
          environmentVariable('HOME', environment: const <String, String>{}),
          Platform.environment['HOME'],
        );
        expect(
          environmentVariable(
            'LLAMADART_UNSET_VARIABLE_838',
            environment: const <String, String>{},
          ),
          isNull,
        );
      },
      skip: Platform.isWindows ? 'libc getenv is POSIX-only here' : false,
    );
  });

  test('the default resolver is the host probe', () {
    expect(mobileAppCacheDirectoryResolver, same(hostMobileAppCacheDirectory));
  });

  test('hostMobileAppCacheDirectory only probes the host platform', () {
    final host = ModelCachePlatform.parse(Platform.operatingSystem);
    for (final platform in ModelCachePlatform.values) {
      if (platform == host && platform.isMobile) {
        continue;
      }
      expect(
        hostMobileAppCacheDirectory(platform),
        isNull,
        reason: platform.name,
      );
    }
  });
}
