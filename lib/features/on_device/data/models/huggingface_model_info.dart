
class HuggingFaceModelInfo {
  const HuggingFaceModelInfo({
    this.repoId,
    this.sha,
    this.lastModified,
    this.pipelineTag,
    this.libraryName,
    this.license,
    this.baseModel,
    this.architecture,
    this.contextLength,
    this.quantization,
    this.languages = const <String>[],
    this.modalities = const <String>[],
    this.fileOid,
    this.totalParameters,
  });

  final String? repoId;
  final String? sha;
  final DateTime? lastModified;
  final String? pipelineTag;
  final String? libraryName;
  final String? license;
  final String? baseModel;
  final String? architecture;
  final int? contextLength;
  final String? quantization;
  final List<String> languages;
  final List<String> modalities;
  final String? fileOid;
  final double? totalParameters;

  factory HuggingFaceModelInfo.fromJson(Map<String, dynamic> json, {String? rfilename}) {
    final cardData = json['cardData'] as Map<String, dynamic>?;
    // languages
    final langRaw = cardData?['language'];
    final languages = <String>[];
    if (langRaw is String) {
      languages.add(langRaw);
    } else if (langRaw is List) {
      for (final v in langRaw) {
        languages.add(v.toString());
      }
    }
    // base_model
    final baseRaw = cardData?['base_model'];
    String? baseModel;
    if (baseRaw is String) {
      baseModel = baseRaw;
    } else if (baseRaw is List && baseRaw.isNotEmpty) {
      baseModel = baseRaw.first.toString();
    }

    // gguf
    final gguf = json['gguf'] as Map<String, dynamic>?;
    final architecture = gguf?['architecture']?.toString();
    final contextLength = (gguf?['context_length'] as num?)?.toInt();
    final total = (gguf?['total'] as num?)?.toDouble();

    // license
    final license = (cardData?['license'] ?? json['license'])?.toString();

    // fileOid from siblings
    String? fileOid;
    if (rfilename != null) {
      final siblings = json['siblings'] as List<dynamic>?;
      if (siblings != null) {
        for (final s in siblings) {
          if (s is Map<String, dynamic>) {
            final name = (s['rfilename'] ?? s['path'])?.toString();
            if (name == rfilename) {
              fileOid = (s['blobId'] ?? s['lfs']?['sha256'])?.toString();
              break;
            }
          }
        }
      }
    }

    // modalities from tags
    final tags = (json['tags'] as List<dynamic>?)
            ?.map((t) => t.toString())
            .toList() ??
        const <String>[];
    final modalities = <String>[];
    for (final t in tags) {
      final lower = t.toLowerCase();
      if (lower.contains('vision') || lower.contains('image')) {
        if (!modalities.contains('vision')) modalities.add('vision');
      }
      if (lower.contains('audio')) {
        if (!modalities.contains('audio')) modalities.add('audio');
      }
      if (lower.contains('text')) {
        if (!modalities.contains('text')) modalities.add('text');
      }
    }
    if (modalities.isEmpty) modalities.add('text');

    return HuggingFaceModelInfo(
      repoId: json['id']?.toString() ?? json['modelId']?.toString(),
      sha: json['sha']?.toString(),
      lastModified: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'].toString())
          : null,
      pipelineTag: json['pipeline_tag']?.toString(),
      libraryName: json['library_name']?.toString(),
      license: license,
      baseModel: baseModel,
      architecture: architecture,
      contextLength: contextLength,
      quantization: null,
      languages: languages,
      modalities: modalities,
      fileOid: fileOid,
      totalParameters: total,
    );
  }

  Map<String, dynamic> toJson() => {
        'repoId': repoId,
        'sha': sha,
        'lastModified': lastModified?.toIso8601String(),
        'pipelineTag': pipelineTag,
        'libraryName': libraryName,
        'license': license,
        'baseModel': baseModel,
        'architecture': architecture,
        'contextLength': contextLength,
        'quantization': quantization,
        'languages': languages,
        'modalities': modalities,
        'fileOid': fileOid,
        'totalParameters': totalParameters,
      };
}
