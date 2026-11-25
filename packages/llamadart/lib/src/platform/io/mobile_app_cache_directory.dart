import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../../core/llama_logger.dart';
import '../../core/models/config/log_level.dart';
import '../../core/models/download/model_download_manager_base.dart';

// Android and iOS paths are POSIX whatever the host running the tests.
final path.Context _posix = path.posix;

/// Finds the mobile app cache directory for the default model cache.
///
/// Tests replace it to exercise the Android and iOS defaults on a desktop
/// host; production code never reassigns it.
String? Function(ModelCachePlatform platform) mobileAppCacheDirectoryResolver =
    hostMobileAppCacheDirectory;

/// The running app's private cache directory on Android and iOS, or `null`
/// when [platform] is not the host platform or the directory cannot be found.
///
/// This is the directory Flutter's `getApplicationCacheDirectory()` returns.
/// It survives app updates and restarts, is not backed up, and the OS clears
/// it only under storage pressure. The process temporary directory is not
/// durable: Flutter's Android `Directory.systemTemp` is `code_cache`, which
/// Android empties on every app update, and iOS purges `tmp` while the app is
/// not running.
String? hostMobileAppCacheDirectory(ModelCachePlatform platform) {
  if (platform != ModelCachePlatform.parse(Platform.operatingSystem)) {
    return null;
  }
  switch (platform) {
    case ModelCachePlatform.android:
      return androidAppCacheDirectory(
        cmdline: _readText('/proc/self/cmdline'),
        status: _readText('/proc/self/status'),
        runtimeDirectories: <String?>[
          Directory.systemTemp.path,
          Platform.environment['TMPDIR'],
        ],
        directoryExists: _directoryExists,
      );
    case ModelCachePlatform.ios:
      return iosAppCacheDirectory(
        home: environmentVariable('HOME'),
        directoryExists: _directoryExists,
      );
    default:
      return null;
  }
}

bool _warnedMobileTemporaryCache = false;

/// Logs, once per isolate, that [platform]'s model cache fell back to the
/// temporary [fallback] directory.
///
/// While warnings are filtered out nothing counts as logged, so enabling
/// logging later still shows the warning on the next fallback.
void warnMobileTemporaryCacheOnce(
  ModelCachePlatform platform,
  String fallback,
) {
  if (_warnedMobileTemporaryCache || !_warningsEnabled()) {
    return;
  }
  _warnedMobileTemporaryCache = true;
  LlamaLogger.instance.warning(
    'Could not find the ${platform.name} app cache directory; caching models '
    'in $fallback, which the OS may clear. Set '
    'DefaultModelDownloadManager.globalCacheDirectory to an app directory.',
  );
}

bool _warningsEnabled() {
  final level = LlamaLogger.instance.level;
  return level != LlamaLogLevel.none && LlamaLogLevel.warn.index >= level.index;
}

/// Lets tests observe the once-per-isolate warning again.
void resetMobileTemporaryCacheWarningForTesting() {
  _warnedMobileTemporaryCache = false;
}

/// The Android app cache directory, `<data dir>/cache`, for the process
/// described by its `/proc/self/cmdline` and `/proc/self/status` contents.
///
/// The data dir is the parent of a [runtimeDirectories] entry that sits
/// directly inside a directory named after the package (Flutter's
/// `code_cache` temp dir, the framework's `TMPDIR`), which also covers apps
/// moved to adopted storage; otherwise `/data/user/<user id>/<package>`.
String? androidAppCacheDirectory({
  required String? cmdline,
  required String? status,
  required Iterable<String?> runtimeDirectories,
  required bool Function(String path) directoryExists,
}) {
  final packageName = _androidPackageName(cmdline);
  if (packageName == null) {
    return null;
  }
  final userId = _androidUserId(status);
  final candidates = <String>[
    for (final directory in runtimeDirectories)
      if (directory != null && directory.isNotEmpty)
        if (_posix.basename(_posix.dirname(_posix.normalize(directory))) ==
            packageName)
          _posix.dirname(_posix.normalize(directory)),
    if (userId != null) '/data/user/$userId/$packageName',
    if (userId == null || userId == 0) '/data/data/$packageName',
  ];
  for (final dataDirectory in candidates) {
    if (directoryExists(dataDirectory)) {
      return _posix.join(dataDirectory, 'cache');
    }
  }
  return null;
}

/// The iOS app cache directory, `<home>/Library/Caches`, where [home] is the
/// app's sandbox container.
String? iosAppCacheDirectory({
  required String? home,
  required bool Function(String path) directoryExists,
}) {
  if (home == null || home.isEmpty) {
    return null;
  }
  final caches = _posix.join(home, 'Library', 'Caches');
  return directoryExists(caches) ? caches : null;
}

final RegExp _androidPackagePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
);

String? _androidPackageName(String? cmdline) {
  if (cmdline == null) {
    return null;
  }
  final processName = cmdline.split('\u0000').first.split(':').first.trim();
  return _androidPackagePattern.hasMatch(processName) ? processName : null;
}

// Android app uids are `userId * 100000 + appId`.
int? _androidUserId(String? status) {
  if (status == null) {
    return null;
  }
  for (final line in status.split('\n')) {
    if (line.startsWith('Uid:')) {
      final realUid = int.tryParse(
        line.substring(4).trim().split(RegExp(r'\s+')).first,
      );
      return realUid == null ? null : realUid ~/ 100000;
    }
  }
  return null;
}

String? _readText(String filePath) {
  try {
    return File(filePath).readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

bool _directoryExists(String directoryPath) {
  try {
    return Directory(directoryPath).existsSync();
  } on FileSystemException {
    return false;
  }
}

typedef _Getenv = Pointer<Utf8> Function(Pointer<Utf8> name);

/// The value of environment variable [name] from [environment] (default
/// `Platform.environment`), else from libc `getenv`.
///
/// Dart's `Platform.environment` is always empty on iOS; libc still has it.
String? environmentVariable(String name, {Map<String, String>? environment}) {
  final fromEnvironment = (environment ?? Platform.environment)[name];
  if (fromEnvironment != null) {
    return fromEnvironment;
  }
  final _Getenv getenv;
  try {
    getenv = DynamicLibrary.process().lookupFunction<_Getenv, _Getenv>(
      'getenv',
    );
  } on ArgumentError {
    return null;
  }
  final nativeName = name.toNativeUtf8(allocator: calloc);
  try {
    final value = getenv(nativeName);
    return value == nullptr ? null : value.toDartString();
  } finally {
    calloc.free(nativeName);
  }
}
