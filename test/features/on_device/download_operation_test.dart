import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/models/download_operation.dart';

void main() {
  test('DownloadOperation round-trips through JSON', () {
    final op = DownloadOperation(
      operationId: 'op-1',
      modelId: 'm1',
      type: DownloadOperationType.update,
      taskId: 'm1-update',
      baseRevision: 'rev1',
      targetRevision: 'rev2',
      phase: DownloadOperationPhase.finalizing,
      startedAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
    );
    final restored = DownloadOperation.fromJson(op.toJson());
    expect(restored.operationId, 'op-1');
    expect(restored.modelId, 'm1');
    expect(restored.type, DownloadOperationType.update);
    expect(restored.taskId, 'm1-update');
    expect(restored.baseRevision, 'rev1');
    expect(restored.targetRevision, 'rev2');
    expect(restored.phase, DownloadOperationPhase.finalizing);
  });

  test('DownloadOperation copyWith preserves fields', () {
    final op = DownloadOperation(
      operationId: 'op-2',
      modelId: 'm2',
      type: DownloadOperationType.download,
      taskId: 'm2',
      phase: DownloadOperationPhase.downloading,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final updated = op.copyWith(phase: DownloadOperationPhase.cancelRequested);
    expect(updated.phase, DownloadOperationPhase.cancelRequested);
    expect(updated.operationId, 'op-2');
    expect(updated.type, DownloadOperationType.download);
  });

  test('DownloadOperation fromJson tolerates missing fields', () {
    final op = DownloadOperation.fromJson({});
    expect(op.operationId, '');
    expect(op.modelId, '');
    expect(op.type, DownloadOperationType.download);
    expect(op.phase, DownloadOperationPhase.started);
  });

  test('DownloadOperation fromJson tolerates unknown enum indices', () {
    final op = DownloadOperation.fromJson({
      'type': 99,
      'phase': 99,
    });
    expect(op.type, DownloadOperationType.download);
    expect(op.phase, DownloadOperationPhase.started);
  });
}
