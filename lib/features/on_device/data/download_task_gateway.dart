import 'package:background_downloader/background_downloader.dart';

/// Narrow facade over [FileDownloader] to enable testing repositories without
/// touching the singleton downloader.
///
/// Production default wraps the real [FileDownloader] singleton.
/// Tests may inject a fake implementation.
abstract class DownloadTaskGateway {
  Future<Task?> taskForId(String id);
  Future<List<Task>> allTasks({bool allGroups = true});
  Future<TaskRecord?> recordForId(String id);
  Future<List<TaskRecord>> allRecords({String? group});
  Future<TaskStatusUpdate> download(
    DownloadTask task, {
    void Function(double)? onProgress,
  });
  Future<bool> pause(DownloadTask task);
  Future<bool> resume(DownloadTask task);
  Future<bool> cancel(DownloadTask task);
  Future<void> cancelTaskWithId(String id);
  Future<bool> deleteRecord(String id);
  Future<void> deleteRecordsWithIds(Iterable<String> ids);
  Future<PermissionStatus> requestPermission(PermissionType type);
  Stream<TaskUpdate> get statusUpdates;
  Stream<TaskUpdate> get progressUpdates;
}

/// Production implementation wrapping the real [FileDownloader] singleton.
class FileDownloaderGateway implements DownloadTaskGateway {
  FileDownloaderGateway([FileDownloader? downloader])
      : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;

  @override
  Future<Task?> taskForId(String id) => _downloader.taskForId(id);

  @override
  Future<List<Task>> allTasks({bool allGroups = true}) =>
      _downloader.allTasks(allGroups: allGroups);

  @override
  Future<TaskRecord?> recordForId(String id) async {
    try {
      return await _downloader.database.recordForId(id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<TaskRecord>> allRecords({String? group}) =>
      _downloader.database.allRecords(group: group);

  @override
  Future<TaskStatusUpdate> download(
    DownloadTask task, {
    void Function(double)? onProgress,
  }) =>
      _downloader.download(task, onProgress: onProgress);

  @override
  Future<bool> pause(DownloadTask task) => _downloader.pause(task);

  @override
  Future<bool> resume(DownloadTask task) => _downloader.resume(task);

  @override
  Future<bool> cancel(DownloadTask task) => _downloader.cancel(task);

  @override
  Future<void> cancelTaskWithId(String id) =>
      _downloader.cancelTaskWithId(id);

  @override
  Future<bool> deleteRecord(String id) async {
    try {
      await _downloader.database.deleteRecordWithId(id);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> deleteRecordsWithIds(Iterable<String> ids) async {
    try {
      await _downloader.database.deleteRecordsWithIds(ids);
    } catch (_) {}
  }

  @override
  Future<PermissionStatus> requestPermission(PermissionType type) async {
    try {
      return await _downloader.permissions.request(type);
    } catch (_) {
      return PermissionStatus.requestError;
    }
  }

  @override
  Stream<TaskUpdate> get statusUpdates => _downloader.updates;

  @override
  Stream<TaskUpdate> get progressUpdates => _downloader.updates;
}
