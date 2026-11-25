import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

import '../../core/llama_logger.dart';
import '../../core/models/config/log_level.dart';

/// An exclusive lock on one model cache entry.
abstract interface class ModelCacheEntryLock {
  /// Releases the lock so the next waiting isolate or process can take it.
  Future<void> release();
}

/// Takes the exclusive lock at [lockPath], creating the file if needed, and
/// waits while another isolate or process holds it, calling
/// [throwIfCancelled] between attempts. An exception from [throwIfCancelled]
/// stops the wait and propagates without the lock.
///
/// Completes with `null` when the file system cannot lock [lockPath]; callers
/// then lose cross-process exclusion, not correctness.
typedef ModelCacheEntryLocker =
    Future<ModelCacheEntryLock?> Function(
      String lockPath, {
      required void Function() throwIfCancelled,
    });

/// The locker [DefaultModelDownloadManager] uses; tests replace it to simulate
/// a file system without locks.
ModelCacheEntryLocker modelCacheEntryLocker = acquireModelCacheEntryLock;

bool _warnedLockUnavailable = false;

/// Logs, once per isolate, that the model cache under [cacheRoot] cannot be
/// locked, so other processes sharing it are not kept from downloading the
/// same entry at the same time.
///
/// While warnings are filtered out nothing counts as logged, so enabling
/// logging later still shows the warning on the next attempt.
void warnModelCacheLockUnavailableOnce(String cacheRoot) {
  final level = LlamaLogger.instance.level;
  if (_warnedLockUnavailable ||
      level == LlamaLogLevel.none ||
      LlamaLogLevel.warn.index < level.index) {
    return;
  }
  _warnedLockUnavailable = true;
  LlamaLogger.instance.warning(
    'Cannot lock model cache entries under $cacheRoot: the directory is not '
    'writable or its file system refuses locks. Downloads there are '
    'serialized only within this isolate, so other isolates and processes '
    'may download the same model at the same time.',
  );
}

/// Lets tests observe the once-per-isolate warning again.
void resetModelCacheLockWarningForTesting() {
  _warnedLockUnavailable = false;
}

const Duration _firstPollDelay = Duration(milliseconds: 10);
const Duration _maxPollDelay = Duration(milliseconds: 200);

/// Takes the exclusive lock at [lockPath]; see [ModelCacheEntryLocker].
///
/// POSIX platforms use `flock(2)` rather than `RandomAccessFile.lock`, whose
/// `fcntl(2)` locks belong to the whole process: they never exclude another
/// isolate of the same process, and closing any descriptor of the file drops
/// them. Windows `LockFileEx` locks belong to the handle, so
/// `RandomAccessFile.lock` excludes isolates there. Either way the OS releases
/// the lock when the holding process exits, including after a crash.
Future<ModelCacheEntryLock?> acquireModelCacheEntryLock(
  String lockPath, {
  required void Function() throwIfCancelled,
}) {
  if (Platform.isWindows) {
    return _acquireWindowsLock(lockPath, throwIfCancelled);
  }
  final libc = _PosixLockApi.instance;
  if (libc == null) {
    return Future<ModelCacheEntryLock?>.value();
  }
  return _acquirePosixLock(libc, lockPath, throwIfCancelled);
}

Future<void> _waitBeforeRetry(int attempt) {
  final delayMs = math.min(
    _firstPollDelay.inMilliseconds << math.min(attempt, 8),
    _maxPollDelay.inMilliseconds,
  );
  return Future<void>.delayed(Duration(milliseconds: delayMs));
}

Future<ModelCacheEntryLock?> _acquirePosixLock(
  _PosixLockApi libc,
  String lockPath,
  void Function() throwIfCancelled,
) async {
  final fd = libc.openLockFile(lockPath);
  if (fd < 0) {
    return null;
  }
  try {
    for (var attempt = 0; ; attempt += 1) {
      final result = libc.tryLock(fd);
      if (result == _PosixLockResult.locked) {
        return _PosixEntryLock(libc, fd);
      }
      if (result == _PosixLockResult.unsupported) {
        libc.close(fd);
        return null;
      }
      throwIfCancelled();
      await _waitBeforeRetry(attempt);
    }
  } catch (_) {
    libc.close(fd);
    rethrow;
  }
}

Future<ModelCacheEntryLock?> _acquireWindowsLock(
  String lockPath,
  void Function() throwIfCancelled,
) async {
  final RandomAccessFile file;
  try {
    file = await File(lockPath).open(mode: FileMode.append);
  } on FileSystemException {
    return null;
  }
  try {
    for (var attempt = 0; ; attempt += 1) {
      try {
        await file.lock(FileLock.exclusive, 0, 1);
        return _WindowsEntryLock(file);
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != _windowsErrorLockViolation) {
          await file.close();
          return null;
        }
      }
      throwIfCancelled();
      await _waitBeforeRetry(attempt);
    }
  } catch (_) {
    await file.close();
    rethrow;
  }
}

const int _windowsErrorLockViolation = 33;

final class _WindowsEntryLock implements ModelCacheEntryLock {
  _WindowsEntryLock(this._file);

  final RandomAccessFile _file;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    try {
      // Closing alone also unlocks, but Windows may release a closed handle's
      // locks late; an explicit unlock lets the next waiter in at once.
      await _file.unlock(0, 1);
    } on FileSystemException {
      // Closing below still releases the lock.
    }
    await _file.close();
  }
}

final class _PosixEntryLock implements ModelCacheEntryLock, Finalizable {
  _PosixEntryLock(this._libc, this._fd) {
    _libc.closeOnCollect.attach(
      this,
      Pointer<Void>.fromAddress(_fd),
      detach: this,
    );
  }

  final _PosixLockApi _libc;
  final int _fd;
  bool _released = false;

  @override
  Future<void> release() async {
    if (_released) {
      return;
    }
    _released = true;
    _libc.closeOnCollect.detach(this);
    _libc.close(_fd);
  }
}

enum _PosixLockResult { locked, busy, unsupported }

typedef _OpenNative = Int Function(Pointer<Utf8>, Int, VarArgs<(Uint32,)>);
typedef _Open = int Function(Pointer<Utf8>, int, int);
typedef _FlockNative = Int Function(Int, Int);
typedef _Flock = int Function(int, int);
typedef _CloseNative = Int Function(Int);
typedef _Close = int Function(int);
typedef _ErrnoLocationNative = Pointer<Int> Function();
typedef _ErrnoLocation = Pointer<Int> Function();

final class _PosixLockApi {
  _PosixLockApi._({
    required _Open open,
    required _Flock flock,
    required _Close close,
    required _ErrnoLocation errnoLocation,
    required this.closeOnCollect,
    required bool darwin,
  }) : _open = open,
       _flock = flock,
       _close = close,
       _errnoLocation = errnoLocation,
       // O_RDONLY | O_CREAT | O_CLOEXEC. flock(2) needs no write access, so a
       // process that may only read another app's lock file can still lock it.
       _openFlags = darwin ? 0x200 | 0x1000000 : 0x40 | 0x80000,
       _eWouldBlock = darwin ? 35 : 11;

  static final _PosixLockApi? instance = _load();

  static _PosixLockApi? _load() {
    final darwin = Platform.isMacOS || Platform.isIOS;
    if (!darwin && !Platform.isLinux && !Platform.isAndroid) {
      return null;
    }
    final errnoSymbol = darwin
        ? '__error'
        : Platform.isAndroid
        ? '__errno'
        : '__errno_location';
    try {
      final libc = DynamicLibrary.process();
      final close = libc.lookup<NativeFunction<_CloseNative>>('close');
      return _PosixLockApi._(
        open: libc.lookupFunction<_OpenNative, _Open>('open'),
        flock: libc.lookupFunction<_FlockNative, _Flock>('flock', isLeaf: true),
        close: close.asFunction<_Close>(),
        errnoLocation: libc
            .lookupFunction<_ErrnoLocationNative, _ErrnoLocation>(
              errnoSymbol,
              isLeaf: true,
            ),
        // A lock whose isolate is killed before release() would otherwise
        // stay held until the process exits. close(int) takes the descriptor
        // in the register a finalizer passes its pointer token in.
        closeOnCollect: NativeFinalizer(close.cast()),
        darwin: darwin,
      );
    } on ArgumentError {
      return null;
    }
  }

  static const int _lockExclusive = 2;
  static const int _lockNonBlocking = 4;
  static const int _eIntr = 4;

  final _Open _open;
  final _Flock _flock;
  final _Close _close;
  final _ErrnoLocation _errnoLocation;
  final int _openFlags;
  final int _eWouldBlock;
  final NativeFinalizer closeOnCollect;

  int openLockFile(String lockPath) {
    final nativePath = lockPath.toNativeUtf8(allocator: calloc);
    try {
      return _open(nativePath, _openFlags, 0x1a4);
    } finally {
      calloc.free(nativePath);
    }
  }

  _PosixLockResult tryLock(int fd) {
    if (_flock(fd, _lockExclusive | _lockNonBlocking) == 0) {
      return _PosixLockResult.locked;
    }
    // Both calls are leaf calls, so the VM runs nothing in between that could
    // overwrite errno.
    final error = _errnoLocation().value;
    return error == _eWouldBlock || error == _eIntr
        ? _PosixLockResult.busy
        : _PosixLockResult.unsupported;
  }

  void close(int fd) {
    _close(fd);
  }
}
