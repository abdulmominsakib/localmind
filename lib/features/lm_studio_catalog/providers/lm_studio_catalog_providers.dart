import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../servers/data/models/server.dart';
import '../data/catalog_models.dart';
import '../data/lm_studio_catalog_service.dart';
import '../data/lm_studio_download_service.dart';

final lmStudioCatalogServiceProvider = Provider<LmStudioCatalogService>((ref) {
  return LmStudioCatalogService(ref.read(dioProvider));
});

final lmStudioDownloadServiceProvider = Provider<LmStudioDownloadService>((ref) {
  return LmStudioDownloadService(ref.read(dioProvider));
});

final lmStudioStaffPicksProvider =
    FutureProvider.autoDispose<List<LmCatalogModel>>((ref) async {
  final service = ref.read(lmStudioCatalogServiceProvider);
  return service.fetchStaffPicks();
});

final lmStudioCatalogSearchProvider = FutureProvider.autoDispose
    .family<List<LmCatalogModel>, String>((ref, query) async {
  final service = ref.read(lmStudioCatalogServiceProvider);
  final staffPicks = await ref.watch(lmStudioStaffPicksProvider.future);
  return service.searchCatalog(query: query, staffPicks: staffPicks);
});

final lmStudioModelReadmeProvider =
    FutureProvider.autoDispose.family<String?, LmCatalogModel>((ref, model) async {
  final service = ref.read(lmStudioCatalogServiceProvider);
  return service.fetchReadme(model);
});

class LmDownloadManagerState {
  const LmDownloadManagerState({
    this.jobs = const [],
  });

  final List<LmDownloadJob> jobs;

  List<LmDownloadJob> get activeJobs =>
      jobs.where((job) => job.status.isActive).toList();

  List<LmDownloadJob> get completedJobs => jobs
      .where(
        (job) =>
            job.status == LmDownloadStatus.completed ||
            job.status == LmDownloadStatus.alreadyDownloaded,
      )
      .toList();

  double? get overallProgress {
    final active = activeJobs;
    if (active.isEmpty) return null;
    var total = 0;
    var downloaded = 0;
    for (final job in active) {
      if (job.totalSizeBytes != null && job.downloadedBytes != null) {
        total += job.totalSizeBytes!;
        downloaded += job.downloadedBytes!;
      }
    }
    if (total <= 0) return null;
    return downloaded / total;
  }

  LmDownloadManagerState copyWith({List<LmDownloadJob>? jobs}) {
    return LmDownloadManagerState(jobs: jobs ?? this.jobs);
  }
}

class LmDownloadManagerNotifier extends Notifier<LmDownloadManagerState> {
  final Map<String, Timer> _pollers = {};
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  int _notificationId = 9000;

  @override
  LmDownloadManagerState build() {
    ref.onDispose(_disposePollers);
    return const LmDownloadManagerState();
  }

  Future<void> _ensureNotifications() async {
    if (_notificationsReady) return;
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(settings: initSettings);
    _notificationsReady = true;
  }

  Future<void> startDownload({
    required Server server,
    required LmCatalogModel model,
  }) async {
    final service = ref.read(lmStudioDownloadServiceProvider);
    final job = await service.startDownload(server: server, model: model);

    final updatedJobs = [...state.jobs];
    updatedJobs.removeWhere((j) => j.jobId == job.jobId && job.jobId.isNotEmpty);
    updatedJobs.insert(0, job);
    state = state.copyWith(jobs: updatedJobs);

    if (job.status == LmDownloadStatus.alreadyDownloaded) {
      await _notifyCompleted(job);
      return;
    }

    if (job.jobId.isNotEmpty && job.status.isActive) {
      _startPolling(server: server, job: job);
    }
  }

  void _startPolling({required Server server, required LmDownloadJob job}) {
    _pollers[job.jobId]?.cancel();
    _pollers[job.jobId] = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _poll(server: server, jobId: job.jobId);
    });
  }

  Future<void> _poll({required Server server, required String jobId}) async {
    final current = state.jobs.where((j) => j.jobId == jobId).firstOrNull;
    if (current == null) return;

    try {
      final service = ref.read(lmStudioDownloadServiceProvider);
      final updated = await service.fetchStatus(server: server, job: current);
      _replaceJob(updated);

      if (updated.status == LmDownloadStatus.completed ||
          updated.status == LmDownloadStatus.alreadyDownloaded) {
        _pollers[jobId]?.cancel();
        _pollers.remove(jobId);
        await _notifyCompleted(updated);
      } else if (updated.status == LmDownloadStatus.failed) {
        _pollers[jobId]?.cancel();
        _pollers.remove(jobId);
        await _notifyFailed(updated);
      }
    } catch (_) {}
  }

  void _replaceJob(LmDownloadJob updated) {
    final jobs = [...state.jobs];
    final index = jobs.indexWhere((j) => j.jobId == updated.jobId);
    if (index >= 0) {
      jobs[index] = updated;
    } else {
      jobs.insert(0, updated);
    }
    state = state.copyWith(jobs: jobs);
  }

  Future<void> _notifyCompleted(LmDownloadJob job) async {
    await _ensureNotifications();
    final id = _notificationId++;
    await _notifications.show(
      id: id,
      title: 'Download complete',
      body: job.displayName,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lm_studio_downloads',
          'LM Studio downloads',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> _notifyFailed(LmDownloadJob job) async {
    await _ensureNotifications();
    final id = _notificationId++;
    await _notifications.show(
      id: id,
      title: 'Download failed',
      body: job.displayName,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lm_studio_downloads',
          'LM Studio downloads',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  void clearCompleted() {
    state = state.copyWith(
      jobs: state.jobs.where((job) => job.status.isActive).toList(),
    );
  }

  void _disposePollers() {
    for (final timer in _pollers.values) {
      timer.cancel();
    }
    _pollers.clear();
  }
}

final lmDownloadManagerProvider =
    NotifierProvider<LmDownloadManagerNotifier, LmDownloadManagerState>(
  LmDownloadManagerNotifier.new,
);

final lmActiveDownloadCountProvider = Provider<int>((ref) {
  return ref.watch(lmDownloadManagerProvider).activeJobs.length;
});

final lmOverallDownloadProgressProvider = Provider<double?>((ref) {
  return ref.watch(lmDownloadManagerProvider).overallProgress;
});
