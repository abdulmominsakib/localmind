import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/models/download_progress_info.dart';
import 'package:localmind/features/on_device/data/models/download_status.dart';
import 'package:localmind/features/on_device/utils/on_device_error_formatter.dart';

void main() {
  test('fromJson clamps progress to 0..1', () {
    final info = DownloadProgressInfo.fromJson({
      'modelId': 'm1',
      'progress': 1.5,
      'receivedBytes': 10,
      'totalBytes': 5,
    });
    expect(info.progress, 1.0);
    // total >= received
    expect(info.totalBytes, 10);
  });

  test('fromJson clamps negative bytes to 0', () {
    final info = DownloadProgressInfo.fromJson({
      'modelId': 'm2',
      'receivedBytes': -5,
      'totalBytes': -3,
    });
    expect(info.receivedBytes, 0);
    expect(info.totalBytes, 0);
  });

  test('pauseReason round-trips through JSON', () {
    final info = DownloadProgressInfo(
      modelId: 'm3',
      pauseReason: DownloadPauseReason.backgroundPolicy,
      errorCategory: DownloadErrorCategory.network,
    );
    final restored = DownloadProgressInfo.fromJson(info.toJson());
    expect(restored.pauseReason, DownloadPauseReason.backgroundPolicy);
    expect(restored.errorCategory, DownloadErrorCategory.network);
  });

  test('categorizeDownloadError maps storage errors', () {
    expect(
      categorizeDownloadError(Exception('ENOSPC: no space left')),
      DownloadErrorCategory.storage,
    );
    expect(
      categorizeDownloadError(Exception('401 unauthorized')),
      DownloadErrorCategory.httpAuth,
    );
    expect(
      categorizeDownloadError(Exception('SocketException: failed')),
      DownloadErrorCategory.network,
    );
  });
}
