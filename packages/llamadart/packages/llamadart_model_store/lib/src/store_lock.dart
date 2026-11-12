import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// An exclusive lock on a store directory, held across processes.
///
/// `RandomAccessFile.lock` takes `fcntl(2)` locks on POSIX, which belong to
/// the whole process: the queue below serializes holders within an isolate
/// and the file lock excludes other processes, but a second isolate of the
/// same process neither waits for the lock nor, once it closes its file,
/// leaves the first one holding it. Stores are therefore used from one
/// isolate per process.
final class StoreLock {
  /// Creates a lock backed by the file at [path].
  ///
  /// When [path]'s directory exists, symbolic links in it are resolved, so
  /// every spelling of one directory shares one queue.
  StoreLock(String path) : path = _canonical(path);

  /// The lock file.
  final String path;

  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  static String _canonical(String path) {
    final absolute = p.normalize(p.absolute(path));
    try {
      return p.join(
        Directory(p.dirname(absolute)).resolveSymbolicLinksSync(),
        p.basename(absolute),
      );
    } on FileSystemException {
      return absolute;
    }
  }

  /// Runs [action] while holding the lock, waiting for any other holder.
  Future<T> run<T>(Future<T> Function() action) async {
    final previous = _tails[path];
    final done = Completer<void>();
    _tails[path] = done.future;
    try {
      await previous;
      final file = await File(path).open(mode: FileMode.append);
      try {
        await file.lock(FileLock.blockingExclusive);
        try {
          return await action();
        } finally {
          // Windows may release a closed handle's lock late; unlocking first
          // lets the next holder in at once.
          await file.unlock();
        }
      } finally {
        await file.close();
      }
    } finally {
      if (identical(_tails[path], done.future)) {
        _tails.remove(path);
      }
      done.complete();
    }
  }
}
