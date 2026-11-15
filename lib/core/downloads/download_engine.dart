import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// Private fields are wired through named constructor parameters, and the FFI
// struct members of disk_space.dart mirror the C ABI — both patterns are
// intentional here.
// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logger/app_logger.dart';
import 'download_task.dart';
import 'os_download_bridge.dart';

/// SharedPreferences-backed persistence of the task list. The engine is the
/// single writer; UI mutates state only through engine methods.
class DownloadTaskStore {
  static const storageKey = 'localmind.download_engine.tasks.v1';

  final SharedPreferences _prefs;

  const DownloadTaskStore(this._prefs);

  List<DownloadTask> load() {
    final encoded = _prefs.getString(storageKey);
    if (encoded == null || encoded.isEmpty) return const <DownloadTask>[];
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded
          .map((e) => DownloadTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      Log.error('Corrupt download task store, starting empty: $e');
      return const <DownloadTask>[];
    }
  }

  Future<void> save(List<DownloadTask> tasks) async {
    final encoded = jsonEncode(tasks.map((t) => t.toJson()).toList());
    if (!await _prefs.setString(storageKey, encoded)) {
      throw StateError('Could not save download tasks');
    }
  }
}

/// Why a running transfer was stopped through its cancel token.
enum _StopReason { pause, cancel, delete }

/// Durable, resumable, queued file downloads from Hugging Face.
///
/// The engine owns bytes and task state; consumers (e.g. the GGUF import
/// repository) own validation/publishing via [registerPostTransfer] — only a
/// successful post-transfer hook lets a task reach `completed`.
/// The engine surface the lifecycle observer drives — declared here so the
/// engine implements it and the observer (and tests) depend on the
/// abstraction, not the concrete engine.
abstract class DownloadLifecycleController {
  Future<void> pauseAllRunning({String? note});
  Future<void> resumeSystemPaused();
}

class DownloadEngine implements DownloadLifecycleController {
  static const _diskMarginBytes = 64 * 1024 * 1024;
  static const _defaultCheckpointIntervalBytes = 8 * 1024 * 1024;

  final DownloadTaskStore _store;
  final Dio _dio;
  final Future<Directory> Function() _workDirectory;
  final String? Function() _tokenResolver;
  final int maxConcurrent;
  final int checkpointIntervalBytes;
  final int? Function(String path)? _freeDiskSpaceBytes;

  final Map<String, DownloadTask> _tasks = {};
  final Map<String, String> _authTokens = {};
  final Map<String, CancelToken> _activeTokens = {};
  final Map<CancelToken, _StopReason> _stopReasons = {};
  final Map<String, Completer<_StopReason>> _stopSignals = {};
  /// Tasks paused by the system (lifecycle/network), not by the user.
  /// Drives [resumeSystemPaused]; membership is cleared by user intent.
  final Set<String> _systemPaused = {};
  /// Notes (e.g. network-loss markers) attached to system pauses, applied to
  /// the task's error field when the stop finalizes.
  final Map<String, String> _pauseNotes = {};
  final StreamController<List<DownloadTask>> _changes =
      StreamController<List<DownloadTask>>.broadcast();
  final Completer<void> _ready = Completer<void>();

  final List<Future<void> Function(DownloadTask task)> _postTransferHooks = [];
  Future<void> _sidecarChain = Future<void>.value();
  Future<void> Function(DownloadTask task, Object error)? _taskFailureHandler;
  bool _disposed = false;
  int _activeCount = 0;

  DownloadEngine({
    required DownloadTaskStore store,
    required Dio dio,
    required Future<Directory> Function() workDirectory,
    required String? Function() tokenResolver,
    this.maxConcurrent = 2,
    this.checkpointIntervalBytes = _defaultCheckpointIntervalBytes,
    int? Function(String path)? freeDiskSpaceBytes,
  })  : _store = store,
        _dio = dio,
        _workDirectory = workDirectory,
        _tokenResolver = tokenResolver,
        _freeDiskSpaceBytes = freeDiskSpaceBytes {
    _initialize();
  }

  /// Completes once persisted tasks are loaded, running tasks are demoted to
  /// `paused`, and orphaned partial files are cleaned up.
  Future<void> get ready => _ready.future;

  /// Unmodifiable snapshot of all known tasks.
  List<DownloadTask> get tasks => _tasks.values.toList(growable: false);

  /// Broadcast stream emitting the full task list on every change.
  Stream<List<DownloadTask>> get changes => _changes.stream;

  /// Registers an additional post-transfer hook. On completion every hook
  /// runs in registration order; each hook self-selects by [DownloadTaskKind]
  /// and returns immediately for kinds it does not own. A successful return
  /// lets the engine set `completed`; a thrown error marks the task `failed`
  /// (bytes kept for retry) and cancels dependent tasks with that reason.
  void registerPostTransfer(Future<void> Function(DownloadTask task)? hook) {
    if (hook != null) _postTransferHooks.add(hook);
  }

  /// Registers a failure hook, invoked once per task after the engine marks
  /// it `failed` (network error, truncated stream, or a post-transfer hook
  /// throwing). Consumers use it to roll back partially published imports.
  void registerTaskFailureHandler(
    Future<void> Function(DownloadTask task, Object error)? handler,
  ) {
    _taskFailureHandler = handler;
  }

  /// Events from the OS downloader (iOS URLSession / Android WorkManager)
  /// for a task whose bytes the OS moves. Progress updates bookkeeping only;
  /// completion runs the same post-transfer validation/publish chain as the
  /// in-app path; failure marks the task  and cancels dependents.
  Future<void> ingestNativeEvent(
    String taskId, {
    int? receivedBytes,
    bool completed = false,
    Object? error,
  }) async {
    final task = _tasks[taskId];
    if (task == null || !task.osManaged) {
      Log.warning('Native event for unknown/non-OS task $taskId ignored');
      return;
    }
    if (completed) {
      final durableOffset = await _fileLength(File(task.partPath));
      await _writeSidecar('${task.partPath}.json', task.url,
          task.etag ?? '', task.totalBytes, durableOffset);
      final finished = task.copyWith(
        receivedBytes: task.totalBytes > 0 ? task.totalBytes : durableOffset,
        totalBytes:
            task.totalBytes > 0 ? task.totalBytes : durableOffset,
      );
      if (_postTransferHooks.isNotEmpty) {
        try {
          await _runPostTransferHooks(finished);
        } catch (e) {
          await _update(finished.copyWith(
            state: DownloadTaskState.failed,
            error: e.toString(),
          ));
          await _notifyFailure(finished, e);
          await _cancelDependents(task.id, 'Dependency failed');
          return;
        }
      }
      await _update(finished.copyWith(state: DownloadTaskState.completed));
      return;
    }
    if (error != null) {
      final failure = _transferErrorText(error);
      await _update(task.copyWith(
        state: DownloadTaskState.failed,
        error: failure,
      ));
      await _notifyFailure(task, failure);
      await _cancelDependents(task.id, 'Dependency failed');
      return;
    }
    if (receivedBytes != null) {
      final current = _tasks[taskId] ?? task;
      await _update(current.copyWith(receivedBytes: receivedBytes));
    }
  }

  /// Runs every registered post-transfer hook in order; the first throw
  /// propagates so the caller applies failure semantics.
  Future<void> _runPostTransferHooks(DownloadTask task) async {
    for (final hook in _postTransferHooks) {
      await hook(task);
    }
  }

  Future<void> _initialize() async {
    try {
      final persisted = _store.load();
      for (final task in persisted) {
        _tasks[task.id] = task.state == DownloadTaskState.running
            ? task.copyWith(state: DownloadTaskState.paused)
            : task;
      }
      await _cleanupOrphans();
      _emit();
      await _store.save(tasks);
      _maybeSchedule();
    } catch (e) {
      Log.error('Download engine init failed: $e');
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Removes partial files and sidecars with no matching task record.
  Future<void> _cleanupOrphans() async {
    try {
      final dir = await _workDirectory();
      if (!await dir.exists()) return;
      final knownParts = _tasks.values.map((t) => t.partPath).toSet();
      final knownSidecars =
          _tasks.values.map((t) => '${t.partPath}.json').toSet();
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final path = entity.path;
        final isPart = path.endsWith('.part');
        final isSidecar = path.endsWith('.part.json');
        if (isPart && !knownParts.contains(path)) {
          await entity.delete();
        } else if (isSidecar && !knownSidecars.contains(path)) {
          await entity.delete();
        }
      }
    } catch (e) {
      Log.warning('Orphan partial cleanup skipped: $e');
    }
  }

  Future<DownloadTask> enqueue({
    required DownloadTaskKind kind,
    required String groupId,
    required String url,
    required String finalPath,
    required String partPath,
    String? dependsOnTaskId,
    bool requiresAuth = false,
    String? authToken,
    bool osManaged = false,
  }) async {
    await ready;
    final duplicate = _tasks.values.where(
      (t) => t.finalPath == finalPath && t.state != DownloadTaskState.failed,
    );
    if (duplicate.isNotEmpty) {
      throw StateError('A download for this file already exists');
    }
    final now = DateTime.now();
    final task = DownloadTask(
      id: 'dl-${now.microsecondsSinceEpoch}-${_tasks.length}',
      kind: kind,
      groupId: groupId,
      url: url,
      finalPath: finalPath,
      partPath: partPath,
      dependsOnTaskId: dependsOnTaskId,
      requiresAuth: requiresAuth,
      osManaged: osManaged,
      createdAt: now,
      updatedAt: now,
    );
    _tasks[task.id] = task;
    if (authToken != null && authToken.isNotEmpty) {
      _authTokens[task.id] = authToken;
    }
    await _persist();
    _emit();
    Log.info('Enqueued download task ${task.id} (${task.kind.name})');
    _maybeSchedule();
    return task;
  }

  Future<void> pause(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    // User pause overrides a system pause — drop the system bookkeeping.
    _systemPaused.remove(taskId);
    _pauseNotes.remove(taskId);
    if (task.state == DownloadTaskState.queued) {
      await _update(task.copyWith(state: DownloadTaskState.paused));
      return;
    }
    if (task.state == DownloadTaskState.running) {
      _stop(task, _StopReason.pause);
    }
  }

  /// Resumes a `paused` or `canceled` task by re-queueing it.
  Future<void> resume(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    // The user resuming a system-paused task is user intent — drop it from
    // the system set so a later resumeSystemPaused does not double-handle it.
    _systemPaused.remove(taskId);
    if (task.state == DownloadTaskState.paused ||
        task.state == DownloadTaskState.canceled) {
      await _update(task.copyWith(
        state: DownloadTaskState.queued,
        clearError: true,
      ));
    }
  }

  /// Gracefully pauses every running task (and holds queued ones from
  /// starting), recording them as system-paused so [resumeSystemPaused] can
  /// restore exactly this set. [note] — e.g. a network-loss marker — is
  /// applied to each task's error field when the stop finalizes. Never
  /// touches user-paused or failed tasks.
  @override
  Future<void> pauseAllRunning({String? note}) async {
    final affected = _tasks.values
        .where((t) =>
            (t.state == DownloadTaskState.running ||
                t.state == DownloadTaskState.queued) &&
            // OS-managed tasks keep downloading in the background — the OS
            // owns their transport, so lifecycle pauses do not apply.
            !t.osManaged)
        .toList(growable: false);
    for (final task in affected) {
      _systemPaused.add(task.id);
      if (note != null) {
        _pauseNotes[task.id] = note;
      }
      if (task.state == DownloadTaskState.running) {
        _stop(task, _StopReason.pause);
      } else {
        final current = _tasks[task.id] ?? task;
        _tasks[task.id] = current.copyWith(
          state: DownloadTaskState.paused,
          error: note,
        );
      }
    }
    if (affected.isNotEmpty) {
      await _persist();
      _emit();
    }
  }

  /// Re-queues exactly the system-paused set (lifecycle/network pauses).
  /// User-paused and failed tasks are never touched.
  @override
  Future<void> resumeSystemPaused() async {
    final ids = _systemPaused.toList(growable: false);
    _systemPaused.clear();
    _pauseNotes.clear();
    for (final id in ids) {
      final task = _tasks[id];
      if (task != null && task.state == DownloadTaskState.paused) {
        await _update(task.copyWith(
          state: DownloadTaskState.queued,
          clearError: true,
        ));
      }
    }
  }

  /// Hands a running (or queued) task to the OS downloader: the in-app
  /// transfer stops gracefully, the sidecar lands, and the native side
  /// resumes from the recorded offset. Returns false (task unchanged on the
  /// in-app path) when unsupported or the hand-off fails.
  Future<bool> delegateToOs(
    String taskId, {
    required Future<bool> Function(OsDownloadHandOff payload) handOff,
  }) async {
    final task = _tasks[taskId];
    if (task == null || task.osManaged) return false;
    if (task.state == DownloadTaskState.running) {
      _stop(task, _StopReason.pause);
      final landed = await _waitForState(
        taskId,
        DownloadTaskState.paused,
        const Duration(seconds: 5),
      );
      if (!landed) return false;
    }
    final current = _tasks[taskId]!;
    final sidecar = await DownloadSidecar.load('${current.partPath}.json');
    final offset =
        sidecar?.offset ?? (current.receivedBytes > 0 ? current.receivedBytes : 0);
    final token = _authTokens.remove(taskId) ??
        (current.requiresAuth ? _tokenResolver() : null);
    final ok = await handOff(OsDownloadHandOff(
      taskId: taskId,
      url: current.url,
      authToken: token,
      offset: offset,
      totalBytes: current.totalBytes,
      partPath: current.partPath,
      finalPath: current.finalPath,
    ));
    if (!ok) return false;
    _systemPaused.remove(taskId);
    _pauseNotes.remove(taskId);
    await _update(current.copyWith(
      state: DownloadTaskState.running,
      osManaged: true,
      receivedBytes: offset,
      clearError: true,
    ));
    return true;
  }

  Future<bool> _waitForState(
    String taskId,
    DownloadTaskState state,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final task = _tasks[taskId];
      if (task != null && task.state == state) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return false;
  }

  Future<void> cancel(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    _systemPaused.remove(taskId);
    if (task.state == DownloadTaskState.running) {
      _stop(task, _StopReason.cancel);
      return;
    }
    if (task.state == DownloadTaskState.queued ||
        task.state == DownloadTaskState.paused ||
        task.state == DownloadTaskState.failed) {
      await _update(task.copyWith(
        state: DownloadTaskState.canceled,
        clearError: true,
      ));
      await _cancelDependents(taskId, 'Dependency canceled');
    }
  }

  Future<void> retry(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    if (task.state == DownloadTaskState.failed) {
      await _update(task.copyWith(
        state: DownloadTaskState.queued,
        clearError: true,
      ));
    }
  }

  Future<void> delete(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;
    _systemPaused.remove(taskId);
    _pauseNotes.remove(taskId);
    await _cancelDependents(taskId, 'Dependency deleted');
    if (task.state == DownloadTaskState.running) {
      _stop(task, _StopReason.delete);
      return;
    }
    await _remove(task);
  }

  /// Deletes every task of an import group (records + partial files only;
  /// published model files are the consumer's responsibility).
  Future<void> deleteGroup(String groupId) async {
    for (final task in _tasks.values
        .where((t) => t.groupId == groupId)
        .toList(growable: false)) {
      await delete(task.id);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final token in _activeTokens.values.toList(growable: false)) {
      if (!token.isCancelled) {
        token.cancel('engine disposed');
      }
    }
    for (final signal in _stopSignals.values.toList(growable: false)) {
      if (!signal.isCompleted) {
        signal.complete(_StopReason.pause);
      }
    }
    await _changes.close();
  }

  void _stop(DownloadTask task, _StopReason reason) {
    final token = _activeTokens[task.id];
    if (token != null && !token.isCancelled) {
      _stopReasons[token] = reason;
      token.cancel(reason.name);
    }
    final signal = _stopSignals[task.id];
    if (signal != null && !signal.isCompleted) {
      signal.complete(reason);
    }
  }

  Future<void> _update(DownloadTask task) async {
    _tasks[task.id] = task;
    await _persist();
    _emit();
    _maybeSchedule();
  }

  Future<void> _persist() async {
    try {
      await _store.save(tasks);
    } catch (e) {
      Log.error('Persisting download tasks failed: $e');
    }
  }

  void _emit() {
    if (!_changes.isClosed) {
      _changes.add(tasks);
    }
  }

  void _maybeSchedule() {
    if (_disposed) return;
    while (_activeCount < maxConcurrent) {
      final next = _nextEligible();
      if (next == null) return;
      // Claim synchronously before launching: _run suspends at its first
      // await, and a re-entrant _maybeSchedule (from _update) must not pick
      // the still-queued task twice.
      _tasks[next.id] = next.copyWith(state: DownloadTaskState.running);
      _activeCount++;
      unawaited(_run(_tasks[next.id]!));
    }
  }

  DownloadTask? _nextEligible() {
    final candidates = _tasks.values
        .where((t) => t.state == DownloadTaskState.queued)
        .where((t) {
          if (t.dependsOnTaskId == null) return true;
          final dep = _tasks[t.dependsOnTaskId];
          return dep != null && dep.state == DownloadTaskState.completed;
        })
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (candidates.isEmpty) return null;
    return candidates.first;
  }

  Future<void> _cancelDependents(
    String taskId,
    String reason, {
    bool removeFromStore = false,
  }) async {
    final dependents = _tasks.values
        .where((t) => t.dependsOnTaskId == taskId)
        .toList(growable: false);
    for (final dependent in dependents) {
      final message = '$reason: task $taskId';
      if (dependent.state == DownloadTaskState.running) {
        _stop(dependent, _StopReason.cancel);
      }
      _tasks[dependent.id] = dependent.copyWith(
        state: DownloadTaskState.canceled,
        error: message,
      );
      if (removeFromStore) {
        await _remove(dependent);
      }
      await _cancelDependents(dependent.id, reason,
          removeFromStore: removeFromStore);
    }
    if (dependents.isNotEmpty) {
      await _persist();
      _emit();
    }
  }

  Future<void> _remove(DownloadTask task) async {
    _tasks.remove(task.id);
    try {
      final part = File(task.partPath);
      if (await part.exists()) await part.delete();
      await DownloadSidecar.delete('${task.partPath}.json');
    } catch (e) {
      Log.warning('Cleaning up files for ${task.id} failed: $e');
    }
    await _persist();
    _emit();
  }

  Future<void> _run(DownloadTask task) async {
    final token = CancelToken();
    _activeTokens[task.id] = token;
    try {
      final dir = await _workDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final partFile = File(task.partPath);
      final sidecarPath = '${task.partPath}.json';

      // Reconcile the retained partial against its sidecar.
      var offset = 0;
      var sidecar = await DownloadSidecar.load(sidecarPath);
      if (sidecar != null) {
        final resolved = await DownloadSidecar.resolveOffset(
          sidecar: sidecar,
          partFile: partFile,
        );
        if (resolved < 0) {
          // Torn write below the recorded offset: restart from byte 0.
          if (await partFile.exists()) await partFile.delete();
          await DownloadSidecar.delete(sidecarPath);
          sidecar = null;
          offset = 0;
        } else {
          offset = resolved;
          // OS-cached bytes can extend past the last checkpoint (hard kill
          // between our sidecar write and the OS flushing the tail). Append
          // mode writes at END-of-file, so anything past the recorded offset
          // must be truncated away or the resume leaves a mid-file hole.
          final partLength = await _fileLength(partFile);
          if (partLength > offset) {
            final raf = await partFile.open(mode: FileMode.append);
            try {
              await raf.truncate(offset);
            } finally {
              await raf.close();
            }
          }
        }
      }

      // Two attempts: the first honors a retained partial (Range), the
      // second restarts from byte 0 when the server resets the transfer.
      for (var attempt = 0; attempt < 2; attempt++) {
        final authToken =
            _authTokens.remove(task.id) ??
            (task.requiresAuth ? _tokenResolver() : null);
        final response = await _dio.get<ResponseBody>(
          task.url,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: true,
            headers: {
              if (offset > 0) 'range': 'bytes=$offset-',
              if (task.requiresAuth &&
                  authToken != null &&
                  authToken.isNotEmpty)
                HttpHeaders.authorizationHeader: 'Bearer $authToken',
            },
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
          cancelToken: token,
        );

        final status = response.statusCode ?? 0;
        final respEtag = response.headers.value(HttpHeaders.etagHeader);
        var total = _contentLength(response.headers);
        var rangeHonored = false;

        if (status == 206) {
          final range =
              _parseContentRange(response.headers.value('content-range'));
          if (range == null || range.$1 != offset) {
            // Range not honored as requested: restart from byte 0 with a
            // fresh request (the 206 body starts at the server's offset).
            offset = 0;
            sidecar = null;
            if (await partFile.exists()) await partFile.delete();
            await DownloadSidecar.delete(sidecarPath);
            continue;
          }
          rangeHonored = true;
          total = range.$3 ?? sidecar?.totalBytes ?? total;
        } else if (status == 200 && offset > 0) {
          // Server ignored the range; its body starts at byte 0.
          offset = 0;
          sidecar = null;
          if (await partFile.exists()) await partFile.delete();
          await DownloadSidecar.delete(sidecarPath);
        }

        if (total == null || total <= 0) {
          throw const HttpException('Server did not report the file size');
        }
        final resolvedTotal = total;

        // Identity check against the sidecar (ETag + totalBytes only).
        if (sidecar != null &&
            rangeHonored &&
            !sidecar.matches(etag: respEtag, totalBytes: resolvedTotal)) {
          offset = 0;
          sidecar = null;
          if (await partFile.exists()) await partFile.delete();
          await DownloadSidecar.delete(sidecarPath);
          continue;
        }

        // Disk-space check once the size is known.
        final free = _freeDiskSpaceBytes?.call(task.finalPath);
        if (free != null && free < resolvedTotal - offset + _diskMarginBytes) {
          throw const HttpException(
            'Not enough free disk space for this download',
          );
        }

        await _update(task.copyWith(
          state: DownloadTaskState.running,
          receivedBytes: offset,
          totalBytes: resolvedTotal,
          etag: respEtag ?? task.etag,
        ));

        // Initial sidecar: a transfer entering running without one (fresh
        // task) records its starting offset immediately, so even the first
        // stop boundary is unambiguous.
        if (sidecar == null) {
          sidecar = DownloadSidecar(
            sourceUrl: task.url,
            etag: respEtag ?? task.etag ?? '',
            totalBytes: resolvedTotal,
            offset: offset,
          );
          await _writeSidecar(sidecarPath, sidecar.sourceUrl, sidecar.etag,
              sidecar.totalBytes, sidecar.offset);
        }

        final sink = partFile.openWrite(
          mode: offset > 0 ? FileMode.append : FileMode.write,
        );
        var received = offset;
        var lastCheckpoint = offset;

        final body = response.data;
        if (body == null) {
          await sink.flush();
          await sink.close();
          throw const HttpException('Empty download stream');
        }

        // Consume the stream with a stop signal racing the data. A custom
        // adapter's stream is not interrupted by the cancel token alone, so
        // pause/cancel must arrive through the signal. Writes are plain
        // buffered adds — no flush mid-stream, so nothing can overlap them;
        // the sidecar lands when the transfer stops (pause/cancel/fail) or
        // completes. Crash-level checkpoints periodically advance the sidecar
        // offset (no flush: process kills keep the OS page cache, and the
        // reconcile-time truncate + torn-write clamp keep power-loss safe).
        final stopSignal = Completer<_StopReason>();
        _stopSignals[task.id] = stopSignal;
        final streamDone = Completer<void>();
        Object? streamFailure;
        late final StreamSubscription<Uint8List> subscription;
        subscription = body.stream.listen(
          (chunk) {
            if (stopSignal.isCompleted) {
              unawaited(subscription.cancel().catchError((_) {}));
              return;
            }
            sink.add(chunk);
            received += chunk.length;
            if (received - lastCheckpoint >= checkpointIntervalBytes) {
              lastCheckpoint = received;
              unawaited(_writeSidecar(sidecarPath, task.url,
                  respEtag ?? task.etag ?? '', resolvedTotal, received));
            }
            final current = _tasks[task.id];
            if (current != null) {
              _tasks[task.id] = current.copyWith(receivedBytes: received);
              _emit();
            }
          },
          onError: (Object e) {
            streamFailure = e;
            if (!streamDone.isCompleted) streamDone.complete();
          },
          onDone: () {
            if (!streamDone.isCompleted) streamDone.complete();
          },
        );
        _StopReason? stopped;
        try {
          stopped = await Future.any<_StopReason?>([
            streamDone.future.then((_) => null),
            stopSignal.future,
          ]);
        } finally {
          _stopSignals.remove(task.id);
        }
        await sink.flush();
        await sink.close();
        unawaited(subscription.cancel().catchError((_) {}));
        final durableOffset = await _fileLength(partFile);
        await _writeSidecar(sidecarPath, task.url,
            respEtag ?? task.etag ?? '', resolvedTotal, durableOffset);

        if (stopped != null) {
          // pause/cancel/delete while running: bytes retained, state per
          // reason (delete removes the record and its files). A system pause
          // note (e.g. network loss) lands in the error field.
          if (stopped == _StopReason.delete) {
            await _remove(task);
          } else {
            final note = _pauseNotes.remove(task.id);
            await _update(task.copyWith(
              state: stopped == _StopReason.pause
                  ? DownloadTaskState.paused
                  : DownloadTaskState.canceled,
              receivedBytes: durableOffset,
              totalBytes: resolvedTotal,
              error: note,
              clearError: note == null,
            ));
          }
          return;
        }
        if (streamFailure != null) {
          final failure = _transferErrorText(streamFailure!);
          _systemPaused.remove(task.id);
          await _update(task.copyWith(
            state: DownloadTaskState.failed,
            receivedBytes: durableOffset,
            totalBytes: resolvedTotal,
            error: failure,
          ));
          await _notifyFailure(task, failure);
          await _cancelDependents(task.id, 'Dependency failed');
          return;
        }
        if (durableOffset < resolvedTotal) {
          // Truncated stream (the connection dropped without an error):
          // never publish a partial file as complete.
          final failure = 'Transfer ended early: '
              '$durableOffset of $resolvedTotal bytes';
          _systemPaused.remove(task.id);
          await _update(task.copyWith(
            state: DownloadTaskState.failed,
            receivedBytes: durableOffset,
            totalBytes: resolvedTotal,
            error: failure,
          ));
          await _notifyFailure(task, failure);
          await _cancelDependents(task.id, 'Dependency failed');
          return;
        }

        // Byte transfer finished successfully.
        final finished = task.copyWith(
          receivedBytes: resolvedTotal,
          totalBytes: resolvedTotal,
          etag: respEtag ?? task.etag,
        );

        if (_postTransferHooks.isNotEmpty) {
          try {
            await _runPostTransferHooks(finished);
          } catch (e) {
            await _update(finished.copyWith(
              state: DownloadTaskState.failed,
              error: e.toString(),
            ));
            await _notifyFailure(finished, e);
            await _cancelDependents(task.id, 'Dependency failed');
            return;
          }
        }
        await _update(finished.copyWith(state: DownloadTaskState.completed));
        return;
      }
      // Both attempts ended in a reset; give up for this run.
      throw const HttpException('Server did not honor resume ranges');
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        // Cancellation during resolve/headers: keep bytes and land the task
        // in `paused`/`canceled` so it never stays stuck on `running`.
        final taskNow = _tasks[task.id];
        final reason = _stopReasons[token] ?? _StopReason.pause;
        if (taskNow != null) {
          if (reason == _StopReason.delete) {
            await _remove(taskNow);
          } else {
            await _update(taskNow.copyWith(
              state: reason == _StopReason.pause
                  ? DownloadTaskState.paused
                  : DownloadTaskState.canceled,
            ));
          }
        }
        return;
      }
      Log.error('Download task ${task.id} failed: $e');
      final current = _tasks[task.id];
      if (current != null) {
        final failure = _transferErrorText(e);
        _systemPaused.remove(current.id);
        await _update(current.copyWith(
          state: DownloadTaskState.failed,
          error: failure,
        ));
        await _notifyFailure(current, failure);
        await _cancelDependents(task.id, 'Dependency failed');
      }
    } finally {
      _activeTokens.remove(task.id);
      _stopReasons.remove(token);
      _stopSignals.remove(task.id);
      _activeCount = (_activeCount - 1).clamp(0, maxConcurrent);
      _maybeSchedule();
    }
  }

  /// Auth failures get a distinct reason (spec: distinguishable from
  /// network errors); everything else falls back to the exception text.
  String _transferErrorText(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        return 'Authentication failed (HTTP $status)';
      }
    }
    return e.toString();
  }

  Future<void> _notifyFailure(DownloadTask task, Object error) async {
    final handler = _taskFailureHandler;
    if (handler == null) return;
    try {
      await handler(task, error);
    } catch (e) {
      Log.error('Download failure handler threw for ${task.id}: $e');
    }
  }

  /// All sidecar writes serialize through one chain: two overlapping saves
  /// share the same `.tmp` path and collide (write handle vs rename →
  /// sharing violation on Windows). Checkpoint saves are best-effort — a
  /// failure is logged and the chain stays alive for the next save.
  Future<void> _writeSidecar(
    String sidecarPath,
    String sourceUrl,
    String etag,
    int totalBytes,
    int offset,
  ) {
    _sidecarChain = _sidecarChain.then((_) async {
      try {
        await DownloadSidecar(
          sourceUrl: sourceUrl,
          etag: etag,
          totalBytes: totalBytes,
          offset: offset,
        ).save(sidecarPath);
      } catch (e) {
        Log.warning('Sidecar write failed for $sidecarPath: $e');
      }
    });
    return _sidecarChain;
  }

  Future<int> _fileLength(File file) async {
    return await file.exists() ? file.length() : 0;
  }
}

int? _contentLength(Headers headers) {
  final value = headers.value(HttpHeaders.contentLengthHeader);
  if (value == null) return null;
  return int.tryParse(value.trim());
}

/// Parses `bytes <start>-<end>/<total>`; returns (start, end, total) with
/// nullable end/total per RFC 7233.
(int, int?, int?)? _parseContentRange(String? value) {
  if (value == null) return null;
  final match =
      RegExp(r'^bytes (\d+)-(\d+)/(\*|(\d+))$').firstMatch(value.trim());
  if (match == null) return null;
  final start = int.parse(match.group(1)!);
  final end = int.parse(match.group(2)!);
  final totalGroup = match.group(3);
  final total = totalGroup == '*' ? null : int.parse(totalGroup!);
  return (start, end, total);
}
