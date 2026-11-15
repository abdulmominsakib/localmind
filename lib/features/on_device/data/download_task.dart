import 'dart:convert';
import 'dart:io';

/// Lifecycle states of a download-engine task.
///
/// `completed` means the byte transfer finished successfully; any
/// post-transfer processing (validation, publishing) by consumers is
/// reported back through the engine's state API.
enum DownloadTaskState { queued, running, paused, failed, completed, canceled }

/// Kind of payload a task transfers. `projector` tasks are dependent
/// follow-ups of a `gguf` task within the same import group.
enum DownloadTaskKind { gguf, projector }

/// One queued/running/finished transfer owned by the download engine.
class DownloadTask {
  final String id;
  final DownloadTaskKind kind;
  /// Import group this task belongs to; tasks of one group share it.
  final String groupId;
  /// Normalized resolve URL — never a signed CDN URL (signatures expire).
  final String url;
  /// Task that must reach `completed` before this one may start.
  final String? dependsOnTaskId;
  final bool requiresAuth;
  final DownloadTaskState state;
  final int receivedBytes;
  /// Expected total size; 0 until the server reports it.
  final int totalBytes;
  final String? etag;
  /// Final file path once published (consumers own this file).
  final String finalPath;
  final String partPath;
  final String? error;
  /// Task bytes are moved by the OS downloader (iOS URLSession / Android
  /// WorkManager) instead of the in-app dio streaming loop. Bookkeeping
  /// (sidecar, state machine, publish) stays with the engine.
  final bool osManaged;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DownloadTask({
    required this.id,
    required this.kind,
    required this.groupId,
    required this.url,
    required this.finalPath,
    required this.partPath,
    this.dependsOnTaskId,
    this.requiresAuth = false,
    this.osManaged = false,
    this.state = DownloadTaskState.queued,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.etag,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isTerminal =>
      state == DownloadTaskState.completed ||
      state == DownloadTaskState.canceled;

  DownloadTask copyWith({
    DownloadTaskState? state,
    int? receivedBytes,
    int? totalBytes,
    String? etag,
    String? error,
    bool clearError = false,
    bool? osManaged,
    DateTime? updatedAt,
  }) {
    return DownloadTask(
      id: id,
      kind: kind,
      groupId: groupId,
      url: url,
      finalPath: finalPath,
      partPath: partPath,
      dependsOnTaskId: dependsOnTaskId,
      requiresAuth: requiresAuth,
      osManaged: osManaged ?? this.osManaged,
      state: state ?? this.state,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      etag: etag ?? this.etag,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'groupId': groupId,
        'url': url,
        'dependsOnTaskId': dependsOnTaskId,
        'requiresAuth': requiresAuth,
        'osManaged': osManaged,
        'state': state.name,
        'receivedBytes': receivedBytes,
        'totalBytes': totalBytes,
        'etag': etag,
        'finalPath': finalPath,
        'partPath': partPath,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static DownloadTask fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      kind: DownloadTaskKind.values.byName(json['kind'] as String),
      groupId: json['groupId'] as String,
      url: json['url'] as String,
      dependsOnTaskId: json['dependsOnTaskId'] as String?,
      requiresAuth: json['requiresAuth'] as bool? ?? false,
      osManaged: json['osManaged'] as bool? ?? false,
      state: DownloadTaskState.values.byName(json['state'] as String),
      receivedBytes: json['receivedBytes'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int? ?? 0,
      etag: json['etag'] as String?,
      finalPath: json['finalPath'] as String,
      partPath: json['partPath'] as String,
      error: json['error'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// Resume metadata bound to one partial file. `offset` is the durable
/// high-water mark: bytes beyond it may exist in the file but are treated
/// as unverified (see [resolveOffset]).
class DownloadSidecar {
  /// Normalized resolve URL — never the signed CDN URL.
  final String sourceUrl;
  final String etag;
  final int totalBytes;
  final int offset;

  const DownloadSidecar({
    required this.sourceUrl,
    required this.etag,
    required this.totalBytes,
    required this.offset,
  });

  /// Identity match ignores the URL: the resolve URL is stable, but ETag and
  /// total size must agree with what the server currently serves.
  bool matches({required String? etag, required int? totalBytes}) {
    if (totalBytes != null && this.totalBytes != 0 && totalBytes != this.totalBytes) {
      return false;
    }
    if (etag != null && this.etag.isNotEmpty && etag != this.etag) {
      return false;
    }
    return true;
  }

  /// Durable offset after reconciling with the partial file's real length:
  /// - `part.length > offset`: extra unflushed bytes are truncated away.
  /// - `part.length < offset`: a data hole exists (sidecar rename can hit
  ///   disk before data blocks after a power loss) — the caller restarts
  ///   from byte 0 rather than resuming into a corrupt file.
  static Future<int> resolveOffset({
    required DownloadSidecar sidecar,
    required File partFile,
  }) async {
    var partLength = 0;
    if (await partFile.exists()) {
      partLength = await partFile.length();
    }
    if (partLength < sidecar.offset) {
      return -1; // torn write: caller must restart from byte 0
    }
    return sidecar.offset;
  }

  Future<void> save(String sidecarPath) async {
    final tmp = '$sidecarPath.tmp';
    final file = File(tmp);
    await file.writeAsString(json.encode({
      'sourceUrl': sourceUrl,
      'etag': etag,
      'totalBytes': totalBytes,
      'offset': offset,
    }), flush: true);
    final target = File(sidecarPath);
    if (await target.exists()) {
      await target.delete();
    }
    await file.rename(sidecarPath);
  }

  static Future<DownloadSidecar?> load(String sidecarPath) async {
    final file = File(sidecarPath);
    if (!await file.exists()) {
      return null;
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return DownloadSidecar(
        sourceUrl: json['sourceUrl'] as String,
        etag: json['etag'] as String? ?? '',
        totalBytes: json['totalBytes'] as int? ?? 0,
        offset: json['offset'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String sidecarPath) async {
    final file = File(sidecarPath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
