import 'dart:io';

import 'package:dio/dio.dart';
import 'models/huggingface_model_info.dart';

class HuggingFaceModelSearchResult {
  const HuggingFaceModelSearchResult({
    required this.repoId,
    required this.downloads,
    required this.likes,
    this.tags = const <String>[],
    this.createdAt,
    this.pipelineTag,
    this.libraryName,
  });

  final String repoId;
  final int downloads;
  final int likes;
  final List<String> tags;
  final DateTime? createdAt;
  final String? pipelineTag;
  final String? libraryName;

  String get name => repoId.split('/').last;
}

class HuggingFaceModelFile {
  const HuggingFaceModelFile({
    required this.repoId,
    required this.path,
    required this.size,
  });

  final String repoId;
  final String path;
  final int size;

  String get name => path.split('/').last;

  String get downloadUrl {
    final encodedPath = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return 'https://huggingface.co/$repoId/resolve/main/$encodedPath';
  }
}

class HuggingFaceModelSearchService {
  HuggingFaceModelSearchService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Supported filter values (Hugging Face `filter` query param):
  /// `gguf`, `litert-lm`, `litertlm`. Only one value is honored by the API
  /// (chaining does not AND); callers merge client-side for "Both".
  Future<List<HuggingFaceModelSearchResult>> searchModels({
    required String query,
    String? author,
    String? filter,
    String? token,
    CancelToken? cancelToken,
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    final params = <String, dynamic>{
      'limit': limit,
      'sort': 'downloads',
      'direction': -1,
    };
    if (trimmed.isNotEmpty) {
      params['search'] = trimmed;
    }
    if (author != null && author.trim().isNotEmpty) {
      params['author'] = author.trim();
    }
    if (filter != null && filter.trim().isNotEmpty) {
      params['filter'] = filter.trim();
    }

    final response = await _dio.get(
      'https://huggingface.co/api/models',
      queryParameters: params,
      options: _options(token),
      cancelToken: cancelToken,
    );

    final data = response.data;
    if (data is! List) return const <HuggingFaceModelSearchResult>[];

    return data
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final createdRaw = json['createdAt'] ?? json['created_at'];
          DateTime? createdAt;
          if (createdRaw is String) {
            createdAt = DateTime.tryParse(createdRaw);
          }
          return HuggingFaceModelSearchResult(
            repoId: (json['modelId'] ?? json['id'] ?? '').toString(),
            downloads: (json['downloads'] as num?)?.toInt() ?? 0,
            likes: (json['likes'] as num?)?.toInt() ?? 0,
            tags: (json['tags'] as List<dynamic>?)
                    ?.map((tag) => tag.toString())
                    .toList() ??
                const <String>[],
            createdAt: createdAt,
            pipelineTag: (json['pipeline_tag'] ?? json['pipelineTag'])
                ?.toString(),
            libraryName: (json['library_name'] ?? json['libraryName'])
                ?.toString(),
          );
        })
        .where((result) => result.repoId.isNotEmpty)
        .toList();
  }

  Future<List<HuggingFaceModelFile>> listFiles({
    required String repoId,
    required String extension,
    String? token,
    CancelToken? cancelToken,
  }) async {
    final normalizedExtension = extension.toLowerCase();
    final response = await _dio.get(
      'https://huggingface.co/api/models/$repoId/tree/main',
      queryParameters: const {'recursive': 'true'},
      options: _options(token),
      cancelToken: cancelToken,
    );

    final data = response.data;
    if (data is! List) return const <HuggingFaceModelFile>[];

    return data
        .whereType<Map<String, dynamic>>()
        .where((json) => json['type'] == 'file')
        .map((json) {
          final path = (json['path'] ?? '').toString();
          return HuggingFaceModelFile(
            repoId: repoId,
            path: path,
            size: (json['size'] as num?)?.toInt() ?? 0,
          );
        })
        .where((file) => file.path.toLowerCase().endsWith(normalizedExtension))
        .toList();
  }

  final Map<String, HuggingFaceModelInfo> _infoCache = <String, HuggingFaceModelInfo>{};

  /// Best-effort fetch of extended model metadata. Returns cached result for
  /// the session when available. Never throws; returns null on failure.
  Future<HuggingFaceModelInfo?> fetchModelInfo(
    String repoId, {
    String? rfilename,
    String? token,
  }) async {
    if (_infoCache.containsKey(repoId)) {
      return _infoCache[repoId];
    }
    try {
      final response = await _dio.get(
        'https://huggingface.co/api/models/$repoId',
        queryParameters: const {'blobs': 'true'},
        options: _options(token).copyWith(
          receiveTimeout: const Duration(seconds: 15),
        ),
        cancelToken: null,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;
      final info = HuggingFaceModelInfo.fromJson(data, rfilename: rfilename);
      _infoCache[repoId] = info;
      return info;
    } catch (_) {
      return null;
    }
  }

  Options _options(String? token) {
    return Options(
      headers: {
        if (token != null && token.isNotEmpty)
          HttpHeaders.authorizationHeader: 'Bearer $token',
      },
      followRedirects: true,
      receiveTimeout: const Duration(minutes: 2),
      validateStatus: (status) => status != null && status >= 200 && status < 400,
    );
  }
}