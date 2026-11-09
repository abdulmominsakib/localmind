import 'package:background_downloader/background_downloader.dart';
import 'package:localmind/features/on_device/data/download_task_gateway.dart';

/// Minimal in-memory fake for [DownloadTaskGateway] used in tests.
class FakeDownloadTaskGateway implements DownloadTaskGateway {
  final Map<String, Task> _tasks = {};
  final List<String> canceledTaskIds = [];
  final List<String> deletedRecords = [];

  void seed(Task task) => _tasks[task.taskId] = task;

  @override
  Future<Task?> taskForId(String id) async => _tasks[id];

  @override
  Future<List<Task>> allTasks({bool allGroups = true}) async =>
      _tasks.values.toList();

  @override
  Future<TaskRecord?> recordForId(String id) async => null;

  @override
  Future<List<TaskRecord>> allRecords({String? group}) async => [];

  @override
  Future<TaskStatusUpdate> download(DownloadTask task,
          {void Function(double)? onProgress}) async =>
      TaskStatusUpdate(task, TaskStatus.complete);

  @override
  Future<bool> pause(DownloadTask task) async => true;

  @override
  Future<bool> resume(DownloadTask task) async => true;

  @override
  Future<bool> cancel(DownloadTask task) async {
    canceledTaskIds.add(task.taskId);
    return true;
  }

  @override
  Future<void> cancelTaskWithId(String id) async {
    canceledTaskIds.add(id);
  }

  @override
  Future<bool> deleteRecord(String id) async {
    deletedRecords.add(id);
    return true;
  }

  @override
  Future<void> deleteRecordsWithIds(Iterable<String> ids) async {
    deletedRecords.addAll(ids);
  }

  @override
  Future<PermissionStatus> requestPermission(PermissionType type) async =>
      PermissionStatus.granted;

  @override
  Stream<TaskUpdate> get statusUpdates => const Stream.empty();

  @override
  Stream<TaskUpdate> get progressUpdates => const Stream.empty();
}
