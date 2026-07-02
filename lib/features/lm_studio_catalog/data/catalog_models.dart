class LmCatalogModel {
  const LmCatalogModel({
    required this.id,
    required this.owner,
    required this.name,
    required this.displayName,
    this.description,
    this.revisionNumber = 1,
    this.downloads = 0,
    this.likes = 0,
    this.updatedAt,
    this.isStaffPick = false,
    this.isVerified = false,
    this.metadata = const LmCatalogMetadata(),
    this.url,
    this.source = LmCatalogSource.lmStudio,
  });

  final String id;
  final String owner;
  final String name;
  final String displayName;
  final String? description;
  final int revisionNumber;
  final int downloads;
  final int likes;
  final DateTime? updatedAt;
  final bool isStaffPick;
  final bool isVerified;
  final LmCatalogMetadata metadata;
  final String? url;
  final LmCatalogSource source;

  String get catalogId => '$owner/$name';

  String get thumbnailUrl =>
      'https://lmstudio.ai/api/v1/artifacts/$owner/$name/revision/$revisionNumber?action=thumbnail';

  String get readmeUrl =>
      'https://lmstudio.ai/api/v1/artifacts/$owner/$name/revision/$revisionNumber?action=readme';

  factory LmCatalogModel.fromStaffPickJson(Map<String, dynamic> json) {
    final owner = json['owner']?.toString() ?? '';
    final name = json['name']?.toString() ?? '';
    final metadataJson = json['metadata'];
    final metadata = metadataJson is Map<String, dynamic>
        ? LmCatalogMetadata.fromJson(metadataJson)
        : const LmCatalogMetadata();

    return LmCatalogModel(
      id: '$owner/$name',
      owner: owner,
      name: name,
      displayName: _humanizeModelName(name),
      description: json['description']?.toString(),
      revisionNumber: (json['revisionNumber'] as num?)?.toInt() ?? 1,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likeCount'] as num?)?.toInt() ?? 0,
      updatedAt: _parseEpochMs(json['updatedAt']),
      isStaffPick: json['staffPickedAt'] != null,
      isVerified: true,
      metadata: metadata,
      url: json['url']?.toString(),
      source: LmCatalogSource.lmStudio,
    );
  }

  factory LmCatalogModel.fromHuggingFaceJson(Map<String, dynamic> json) {
    final modelId = json['modelId']?.toString() ?? json['id']?.toString() ?? '';
    final parts = modelId.split('/');
    final owner = parts.isNotEmpty ? parts.first : '';
    final name = parts.length > 1 ? parts.sublist(1).join('/') : modelId;
    final tags = (json['tags'] as List<dynamic>?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ??
        const [];

    return LmCatalogModel(
      id: modelId,
      owner: owner,
      name: name,
      displayName: _humanizeModelName(name),
      description: null,
      revisionNumber: 1,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      updatedAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      isStaffPick: false,
      isVerified: false,
      metadata: LmCatalogMetadata(
        compatibilityTypes: tags.contains('gguf') ? const ['gguf'] : const [],
        vision: tags.contains('vision') || tags.contains('multimodal'),
        reasoning: tags.contains('reasoning') || tags.contains('thinking'),
        trainedForToolUse:
            tags.contains('tool-use') || tags.contains('function-calling'),
      ),
      url: 'https://huggingface.co/$modelId',
      source: LmCatalogSource.huggingFace,
    );
  }

  bool matchesQuery(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    return id.toLowerCase().contains(q) ||
        displayName.toLowerCase().contains(q) ||
        owner.toLowerCase().contains(q) ||
        (description?.toLowerCase().contains(q) ?? false);
  }
}

class LmCatalogMetadata {
  const LmCatalogMetadata({
    this.type = 'llm',
    this.architectures = const [],
    this.compatibilityTypes = const [],
    this.paramsStrings = const [],
    this.minMemoryUsageBytes,
    this.trainedForToolUse = false,
    this.vision = false,
    this.reasoning = false,
    this.contextLengths = const [],
  });

  final String type;
  final List<String> architectures;
  final List<String> compatibilityTypes;
  final List<String> paramsStrings;
  final int? minMemoryUsageBytes;
  final bool trainedForToolUse;
  final bool vision;
  final bool reasoning;
  final List<int> contextLengths;

  factory LmCatalogMetadata.fromJson(Map<String, dynamic> json) {
    return LmCatalogMetadata(
      type: json['type']?.toString() ?? 'llm',
      architectures: _stringList(json['architectures']),
      compatibilityTypes: _stringList(json['compatibilityTypes']),
      paramsStrings: _stringList(json['paramsStrings']),
      minMemoryUsageBytes: (json['minMemoryUsageBytes'] as num?)?.toInt(),
      trainedForToolUse: json['trainedForToolUse'] == true,
      vision: json['vision'] == true,
      reasoning: json['reasoning'] == true,
      contextLengths: (json['contextLengths'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
    );
  }
}

enum LmCatalogSource { lmStudio, huggingFace }

enum MemoryCompatibility {
  fullGpuOffload,
  partialGpuOffload,
  likelyTooLarge,
  unknown,
}

class LmDownloadJob {
  const LmDownloadJob({
    required this.jobId,
    required this.modelId,
    required this.displayName,
    required this.status,
    this.totalSizeBytes,
    this.downloadedBytes,
    this.bytesPerSecond,
    this.startedAt,
    this.completedAt,
    this.estimatedCompletion,
    this.errorMessage,
  });

  final String jobId;
  final String modelId;
  final String displayName;
  final LmDownloadStatus status;
  final int? totalSizeBytes;
  final int? downloadedBytes;
  final int? bytesPerSecond;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? estimatedCompletion;
  final String? errorMessage;

  double? get progressFraction {
    if (totalSizeBytes == null ||
        totalSizeBytes! <= 0 ||
        downloadedBytes == null) {
      return null;
    }
    return (downloadedBytes! / totalSizeBytes!).clamp(0.0, 1.0);
  }

  LmDownloadJob copyWith({
    String? jobId,
    String? modelId,
    String? displayName,
    LmDownloadStatus? status,
    int? totalSizeBytes,
    int? downloadedBytes,
    int? bytesPerSecond,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? estimatedCompletion,
    String? errorMessage,
  }) {
    return LmDownloadJob(
      jobId: jobId ?? this.jobId,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      status: status ?? this.status,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      estimatedCompletion: estimatedCompletion ?? this.estimatedCompletion,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  factory LmDownloadJob.fromJson(
    Map<String, dynamic> json, {
    required String modelId,
    required String displayName,
  }) {
    return LmDownloadJob(
      jobId: json['job_id']?.toString() ?? '',
      modelId: modelId,
      displayName: displayName,
      status: LmDownloadStatus.fromApi(json['status']?.toString()),
      totalSizeBytes: (json['total_size_bytes'] as num?)?.toInt(),
      downloadedBytes: (json['downloaded_bytes'] as num?)?.toInt(),
      bytesPerSecond: (json['bytes_per_second'] as num?)?.toInt(),
      startedAt: _parseIso(json['started_at']),
      completedAt: _parseIso(json['completed_at']),
      estimatedCompletion: _parseIso(json['estimated_completion']),
    );
  }
}

enum LmDownloadStatus {
  downloading,
  paused,
  completed,
  failed,
  alreadyDownloaded;

  static LmDownloadStatus fromApi(String? value) {
    switch (value) {
      case 'downloading':
        return LmDownloadStatus.downloading;
      case 'paused':
        return LmDownloadStatus.paused;
      case 'completed':
        return LmDownloadStatus.completed;
      case 'failed':
        return LmDownloadStatus.failed;
      case 'already_downloaded':
        return LmDownloadStatus.alreadyDownloaded;
      default:
        return LmDownloadStatus.downloading;
    }
  }

  bool get isActive =>
      this == LmDownloadStatus.downloading || this == LmDownloadStatus.paused;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value.map((e) => e.toString()).toList();
}

DateTime? _parseEpochMs(dynamic value) {
  if (value == null) return null;
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return DateTime.tryParse(value.toString());
}

DateTime? _parseIso(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

String _humanizeModelName(String name) {
  return name
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.length <= 3 && part == part.toUpperCase()) return part;
        if (RegExp(r'^\d').hasMatch(part)) return part.toUpperCase();
        return part[0].toUpperCase() + part.substring(1);
      })
      .join(' ');
}
