import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../../servers/data/models/server.dart';
import '../../servers/providers/server_providers.dart';
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

class LmCatalogSearchState {
  const LmCatalogSearchState({
    this.staffMatches = const [],
    this.communityModels = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.nextUrl,
    this.hasMore = false,
  });

  final List<LmCatalogModel> staffMatches;
  final List<LmCatalogModel> communityModels;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final String? nextUrl;
  final bool hasMore;

  List<LmCatalogModel> get allModels => [...staffMatches, ...communityModels];

  LmCatalogSearchState copyWith({
    List<LmCatalogModel>? staffMatches,
    List<LmCatalogModel>? communityModels,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    String? nextUrl,
    bool? hasMore,
    bool clearError = false,
  }) {
    return LmCatalogSearchState(
      staffMatches: staffMatches ?? this.staffMatches,
      communityModels: communityModels ?? this.communityModels,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      nextUrl: nextUrl ?? this.nextUrl,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class LmCatalogSearchNotifier extends Notifier<LmCatalogSearchState> {
  String _query = '';

  @override
  LmCatalogSearchState build() => const LmCatalogSearchState();

  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed == _query && state.allModels.isNotEmpty && !state.isLoading) {
      return;
    }
    _query = trimmed;

    if (trimmed.isEmpty) {
      state = const LmCatalogSearchState();
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);
    final service = ref.read(lmStudioCatalogServiceProvider);

    try {
      final staffPicks = await ref.read(lmStudioStaffPicksProvider.future);
      final staffMatches =
          staffPicks.where((m) => m.matchesQuery(trimmed)).toList();
      final page = await service.searchHuggingFace(query: trimmed);
      final staffIds = staffMatches.map((m) => m.id).toSet();
      final community =
          page.models.where((m) => !staffIds.contains(m.id)).toList();

      state = LmCatalogSearchState(
        staffMatches: staffMatches,
        communityModels: community,
        nextUrl: page.nextUrl,
        hasMore: page.nextUrl != null,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.nextUrl == null) return;

    state = state.copyWith(isLoadingMore: true);
    final service = ref.read(lmStudioCatalogServiceProvider);

    try {
      final page = await service.searchHuggingFace(nextUrl: state.nextUrl);
      final existingIds = state.allModels.map((m) => m.id).toSet();
      final more =
          page.models.where((m) => !existingIds.contains(m.id)).toList();

      state = state.copyWith(
        communityModels: [...state.communityModels, ...more],
        nextUrl: page.nextUrl,
        hasMore: page.nextUrl != null,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }
}

final lmCatalogSearchProvider =
    NotifierProvider<LmCatalogSearchNotifier, LmCatalogSearchState>(
  LmCatalogSearchNotifier.new,
);

final lmModelDetailProvider =
    FutureProvider.autoDispose.family<LmModelDetail, LmCatalogModel>(
        (ref, model) async {
  final service = ref.read(lmStudioCatalogServiceProvider);
  return service.fetchModelDetail(model);
});

class LmDownloadManagerState {
  const LmDownloadManagerState({
    this.jobs = const [],
  });

  final List<LmDownloadJob> jobs;

  List<LmDownloadJob> get activeJobs =>
      jobs.where((job) => job.status.isActive).toList();

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
  static const _storageKey = 'lm_studio_active_downloads';

  final Map<String, Timer> _pollers = {};
  final Map<String, String> _jobServerIds = {};
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  int _notificationId = 9000;

  @override
  LmDownloadManagerState build() {
    ref.onDispose(_disposePollers);
    unawaited(_restoreActiveDownloads());
    return const LmDownloadManagerState();
  }

  /// Re-attaches to any downloads that were still in progress when the app
  /// was last closed, so a restart doesn't silently abandon tracking of a
  /// download that's still running on the LM Studio server.
  Future<void> _restoreActiveDownloads() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;

    List<dynamic> entries;
    try {
      entries = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      await prefs.remove(_storageKey);
      return;
    }

    final servers = await ref.read(serversProvider.future);
    final service = ref.read(lmStudioDownloadServiceProvider);

    for (final entry in entries) {
      if (entry is! Map) continue;
      final serverId = entry['serverId'] as String?;
      final jobId = entry['jobId'] as String?;
      final modelId = entry['modelId'] as String?;
      if (serverId == null || jobId == null || modelId == null) continue;
      final displayName = entry['displayName'] as String? ?? modelId;

      final server = servers.where((s) => s.id == serverId).firstOrNull;
      if (server == null) continue;

      final placeholder = LmDownloadJob(
        jobId: jobId,
        modelId: modelId,
        displayName: displayName,
        status: LmDownloadStatus.downloading,
      );

      try {
        final updated = await service.fetchStatus(
          server: server,
          job: placeholder,
        );
        _jobServerIds[jobId] = serverId;
        _replaceJob(updated);

        if (updated.status.isActive) {
          _startPolling(server: server, job: updated);
        } else if (updated.status == LmDownloadStatus.completed ||
            updated.status == LmDownloadStatus.alreadyDownloaded) {
          await _notifyCompleted(updated);
          ref.invalidate(availableModelsProvider(server.id));
        } else if (updated.status == LmDownloadStatus.failed) {
          await _notifyFailed(updated);
        }
      } on LmDownloadJobNotFoundException {
        // Job no longer exists on the server; drop it.
      } catch (_) {
        // Couldn't reach the server right now — leave it persisted so the
        // next restore attempt (or a manual refresh) can pick it back up.
      }
    }

    await _persistActiveDownloads();
  }

  Future<void> _persistActiveDownloads() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final active = state.jobs.where((j) => j.status.isActive).toList();
    if (active.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }

    final entries = active
        .map(
          (j) => {
            'serverId': _jobServerIds[j.jobId],
            'jobId': j.jobId,
            'modelId': j.modelId,
            'displayName': j.displayName,
          },
        )
        .where((e) => e['serverId'] != null)
        .toList();
    await prefs.setString(_storageKey, jsonEncode(entries));
  }

  void _setJobs(List<LmDownloadJob> jobs) {
    state = state.copyWith(jobs: jobs);
    unawaited(_persistActiveDownloads());
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
    required LmModelDetail detail,
    LmModelQuantOption? quant,
  }) async {
    final downloadService = ref.read(lmStudioDownloadServiceProvider);
    final request = downloadService.buildDownloadRequest(
      model: model,
      detail: detail,
      quant: quant,
    );
    final job = await downloadService.startDownload(
      server: server,
      request: request,
    );

    final updatedJobs = [...state.jobs];
    if (job.jobId.isNotEmpty) {
      updatedJobs.removeWhere((j) => j.jobId == job.jobId);
    }
    updatedJobs.insert(0, job);
    if (job.jobId.isNotEmpty) {
      _jobServerIds[job.jobId] = server.id;
    }
    _setJobs(updatedJobs);

    if (job.status == LmDownloadStatus.alreadyDownloaded ||
        job.status == LmDownloadStatus.completed) {
      await _notifyCompleted(job);
      ref.invalidate(availableModelsProvider(server.id));
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
        ref.invalidate(availableModelsProvider(server.id));
      } else if (updated.status == LmDownloadStatus.failed) {
        _pollers[jobId]?.cancel();
        _pollers.remove(jobId);
        await _notifyFailed(updated);
      }
    } on LmDownloadJobNotFoundException {
      _pollers[jobId]?.cancel();
      _pollers.remove(jobId);
      removeJob(jobId);
    } catch (_) {}
  }

  void removeJob(String jobId) {
    _jobServerIds.remove(jobId);
    final jobs = state.jobs.where((j) => j.jobId != jobId).toList();
    _setJobs(jobs);
  }

  void dismissFinishedJobs() {
    final jobs = state.jobs.where((j) => j.status.isActive).toList();
    _setJobs(jobs);
  }

  void _replaceJob(LmDownloadJob updated) {
    final jobs = [...state.jobs];
    final index = jobs.indexWhere((j) => j.jobId == updated.jobId);
    if (index >= 0) {
      jobs[index] = updated;
    } else {
      jobs.insert(0, updated);
    }
    _setJobs(jobs);
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
      body: job.errorMessage ?? job.displayName,
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
