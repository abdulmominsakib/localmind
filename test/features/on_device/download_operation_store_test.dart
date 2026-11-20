import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/download_operation_store.dart';
import 'package:localmind/features/on_device/data/models/download_operation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('begin + forModel round-trip', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DownloadOperationStore(prefs);
    store.loadSync();

    final op = DownloadOperation(
      operationId: 'op-1',
      modelId: 'm1',
      type: DownloadOperationType.update,
      taskId: 'm1-update',
      phase: DownloadOperationPhase.downloading,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await store.begin(op);
    expect(store.forModel('m1')?.operationId, 'op-1');
    expect(store.forModel('m1')?.type, DownloadOperationType.update);
  });

  test('complete removes operation', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DownloadOperationStore(prefs);
    store.loadSync();

    final op = DownloadOperation(
      operationId: 'op-2',
      modelId: 'm2',
      type: DownloadOperationType.download,
      taskId: 'm2',
      phase: DownloadOperationPhase.downloading,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await store.begin(op);
    await store.complete('op-2');
    expect(store.forModel('m2'), isNull);
  });

  test('markPhase updates phase', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DownloadOperationStore(prefs);
    store.loadSync();

    final op = DownloadOperation(
      operationId: 'op-3',
      modelId: 'm3',
      type: DownloadOperationType.update,
      taskId: 'm3-update',
      phase: DownloadOperationPhase.downloading,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await store.begin(op);
    await store.markPhase('op-3', DownloadOperationPhase.finalizing);
    expect(store.forModel('m3')?.phase, DownloadOperationPhase.finalizing);
  });

  test('prune removes ops for deleted models', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DownloadOperationStore(prefs);
    store.loadSync();

    await store.begin(DownloadOperation(
      operationId: 'op-4',
      modelId: 'm4',
      type: DownloadOperationType.download,
      taskId: 'm4',
      phase: DownloadOperationPhase.downloading,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await store.begin(DownloadOperation(
      operationId: 'op-5',
      modelId: 'm5',
      type: DownloadOperationType.download,
      taskId: 'm5',
      phase: DownloadOperationPhase.downloading,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await store.prune(liveModelIds: {'m4'});
    expect(store.forModel('m4'), isNotNull);
    expect(store.forModel('m5'), isNull);
  });

  test('loadSync tolerates corrupt JSON', () async {
    SharedPreferences.setMockInitialValues({'model_download_operations_v1': '{bad'});
    final prefs = await SharedPreferences.getInstance();
    final store = DownloadOperationStore(prefs);
    store.loadSync();
    expect(store.all(), isEmpty);
  });
}
