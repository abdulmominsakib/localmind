class LmCatalogModel {
  const LmCatalogModel({
    required this.id,
    required this.owner,
    required this.name,
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
    this.hfRepoId,
  });

  final String id;
  final String owner;
  final String name;
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
  /// Hugging Face repo used for quant listing / HF downloads.
  final String? hfRepoId;

  String get catalogId => '$owner/$name';

  String get displayLabel => name;

  String get thumbnailUrl =>
      'https://lmstudio.ai/api/v1/artifacts/$owner/$name/revision/$revisionNumber?action=thumbnail';

  String get manifestUrl =>
      'https://lmstudio.ai/api/v1/artifacts/$owner/$name/revision/-1?manifest=true';

  String get readmeUrl =>
      'https://lmstudio.ai/api/v1/artifacts/$owner/$name/revision/$revisionNumber?action=readme';

  String? get hfDownloadBaseUrl {
    final repo = hfRepoId ?? (source == LmCatalogSource.huggingFace ? id : null);
    if (repo == null || repo.isEmpty) return null;
    return 'https://huggingface.co/$repo';
  }

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
      description: null,
      revisionNumber: 1,
      downloads: (json['downloads'] as num?)?.toInt() ?? 0,
      likes: (json['likes'] as num?)?.toInt() ?? 0,
      updatedAt: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'].toString())
          : (json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'].toString())
              : null),
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
      hfRepoId: modelId,
    );
  }

  LmCatalogModel copyWith({
    String? hfRepoId,
    int? downloads,
    int? likes,
    LmCatalogMetadata? metadata,
  }) {
    return LmCatalogModel(
      id: id,
      owner: owner,
      name: name,
      description: description,
      revisionNumber: revisionNumber,
      downloads: downloads ?? this.downloads,
      likes: likes ?? this.likes,
      updatedAt: updatedAt,
      isStaffPick: isStaffPick,
      isVerified: isVerified,
      metadata: metadata ?? this.metadata,
      url: url,
      source: source,
      hfRepoId: hfRepoId ?? this.hfRepoId,
    );
  }

  bool matchesQuery(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return true;
    return id.toLowerCase().contains(q) ||
        name.toLowerCase().contains(q) ||
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

class LmArtifactManifest {
  const LmArtifactManifest({
    this.hfRepoId,
    this.downloadCount,
    this.readme,
  });

  final String? hfRepoId;
  final int? downloadCount;
  final String? readme;

  factory LmArtifactManifest.fromJson(Map<String, dynamic> json) {
    String? hfRepo;
    final manifest = json['manifest'];
    if (manifest is Map<String, dynamic>) {
      final deps = manifest['dependencies'] as List<dynamic>?;
      if (deps != null) {
        for (final dep in deps) {
          if (dep is! Map<String, dynamic>) continue;
          final sources = dep['sources'] as List<dynamic>?;
          if (sources == null) continue;
          for (final source in sources) {
            if (source is! Map<String, dynamic>) continue;
            if (source['type']?.toString() != 'huggingface') continue;
            final user = source['user']?.toString();
            final repo = source['repo']?.toString();
            if (user != null && repo != null) {
              hfRepo = '$user/$repo';
              break;
            }
          }
          if (hfRepo != null) break;
        }
      }
    }

    return LmArtifactManifest(
      hfRepoId: hfRepo,
      downloadCount: (json['downloadCount'] as num?)?.toInt(),
    );
  }
}

class LmModelQuantOption {
  const LmModelQuantOption({
    required this.fileName,
    required this.quantization,
    required this.sizeBytes,
  });

  final String fileName;
  final String quantization;
  final int sizeBytes;

  static List<LmModelQuantOption> fromHfTree(List<dynamic> tree) {
    final options = <LmModelQuantOption>[];
    for (final entry in tree) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['type']?.toString() != 'file') continue;
      final path = entry['path']?.toString() ?? '';
      if (!path.toLowerCase().endsWith('.gguf')) continue;
      // mmproj files are multimodal projector weights, not standalone
      // model quants — they can't be selected/downloaded on their own.
      if (path.toLowerCase().contains('mmproj')) continue;
      final quant = extractQuantization(path);
      if (quant == null) continue;
      final size = _fileSize(entry);
      if (size <= 0) continue;
      options.add(
        LmModelQuantOption(
          fileName: path,
          quantization: quant,
          sizeBytes: size,
        ),
      );
    }
    options.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    return options;
  }

  /// Preferred quant order used to pick a sensible default/recommended
  /// option when the user hasn't picked one explicitly.
  static const preferredQuantOrder = ['Q4_K_M', 'Q4_K_S', 'Q4_0', 'Q5_K_M'];

  static LmModelQuantOption? recommended(List<LmModelQuantOption> quants) {
    if (quants.isEmpty) return null;
    for (final preferred in preferredQuantOrder) {
      final match =
          quants.where((q) => q.quantization == preferred).firstOrNull;
      if (match != null) return match;
    }
    return quants.first;
  }

  static int _fileSize(Map<String, dynamic> entry) {
    final lfs = entry['lfs'];
    if (lfs is Map && lfs['size'] is num) {
      return (lfs['size'] as num).toInt();
    }
    if (entry['size'] is num) {
      return (entry['size'] as num).toInt();
    }
    return 0;
  }

  static String? extractQuantization(String fileName) {
    final base = fileName.split('/').last;
    final patterns = [
      RegExp(r'-((?:iQ|IQ|Q|F|BF)\d[\w_]*)\.gguf$', caseSensitive: false),
      RegExp(r'\.((?:iQ|IQ|Q|F|BF)\d[\w_]*)\.gguf$', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(base);
      if (match != null) {
        return match.group(1)?.toUpperCase();
      }
    }
    return null;
  }
}

class LmModelDetail {
  const LmModelDetail({
    required this.model,
    this.readme,
    this.quants = const [],
    this.hfRepoId,
  });

  final LmCatalogModel model;
  final String? readme;
  final List<LmModelQuantOption> quants;
  final String? hfRepoId;
}

class LmDownloadRequest {
  const LmDownloadRequest({
    required this.model,
    this.quantization,
    this.displayName,
  });

  /// Catalog id (`owner/name`) or full Hugging Face model URL.
  final String model;
  final String? quantization;
  final String? displayName;
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
      errorMessage: json['error'] is Map
          ? (json['error'] as Map)['message']?.toString()
          : null,
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

class HfSearchPage {
  const HfSearchPage({
    required this.models,
    this.nextUrl,
  });

  final List<LmCatalogModel> models;
  final String? nextUrl;
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
