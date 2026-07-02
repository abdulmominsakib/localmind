import 'package:dio/dio.dart';

import '../../../core/logger/app_logger.dart';
import 'catalog_models.dart';

class LmStudioCatalogService {
  LmStudioCatalogService(this._dio);

  final Dio _dio;

  static const _staffPicksUrl =
      'https://lmstudio.ai/api/v1/models?action=staff-picks';

  static const _hfModelsBase = 'https://huggingface.co/api/models';

  Future<List<LmCatalogModel>> fetchStaffPicks() async {
    try {
      final response = await _dio.get<List<dynamic>>(_staffPicksUrl);
      final data = response.data;
      if (data == null) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(LmCatalogModel.fromStaffPickJson)
          .toList();
    } catch (e) {
      Log.warning('Failed to fetch LM Studio staff picks: $e');
      rethrow;
    }
  }

  Future<HfSearchPage> searchHuggingFace({
    String query = '',
    int limit = 50,
    String? nextUrl,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty && nextUrl == null) {
      return const HfSearchPage(models: []);
    }

    try {
      final Response<List<dynamic>> response;
      if (nextUrl != null) {
        response = await _dio.get<List<dynamic>>(nextUrl);
      } else {
        response = await _dio.get<List<dynamic>>(
          _hfModelsBase,
          queryParameters: {
            'search': trimmed,
            'filter': 'gguf',
            'sort': 'likes',
            'direction': '-1',
            'limit': limit,
          },
        );
      }

      final data = response.data ?? [];
      final models = data
          .whereType<Map<String, dynamic>>()
          .map(LmCatalogModel.fromHuggingFaceJson)
          .toList();

      final next = _parseNextLink(response.headers.value('link'));
      return HfSearchPage(models: models, nextUrl: next);
    } catch (e) {
      Log.warning('Failed to search Hugging Face GGUF models: $e');
      rethrow;
    }
  }

  String? _parseNextLink(String? linkHeader) {
    if (linkHeader == null || linkHeader.isEmpty) return null;
    for (final part in linkHeader.split(',')) {
      final trimmed = part.trim();
      if (!trimmed.contains('rel="next"')) continue;
      final match = RegExp(r'<([^>]+)>').firstMatch(trimmed);
      return match?.group(1);
    }
    return null;
  }

  Future<LmArtifactManifest> fetchArtifactManifest(LmCatalogModel model) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(model.manifestUrl);
      return LmArtifactManifest.fromJson(response.data ?? {});
    } catch (e) {
      Log.debug('Failed to fetch manifest for ${model.id}: $e');
      return const LmArtifactManifest();
    }
  }

  Future<String?> fetchLmStudioReadme(LmCatalogModel model) async {
    try {
      final response = await _dio.get<dynamic>(model.readmeUrl);
      final data = response.data;
      if (data is String) {
        final trimmed = data.trim();
        if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
          return _decodeJsonString(trimmed);
        }
        return trimmed;
      }
      if (data is Map && data['readme'] is String) {
        return data['readme'] as String;
      }
      return data?.toString();
    } catch (e) {
      Log.debug('Failed to fetch LM Studio readme for ${model.id}: $e');
      return null;
    }
  }

  String _decodeJsonString(String raw) {
    try {
      if (raw.startsWith('"') && raw.endsWith('"')) {
        return raw
            .substring(1, raw.length - 1)
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\');
      }
    } catch (_) {}
    return raw;
  }

  Future<Map<String, dynamic>?> fetchHfModelInfo(String repoId) async {
    try {
      // HF expects owner/repo in the path — encoding the slash returns 400.
      final response = await _dio.get<Map<String, dynamic>>(
        '$_hfModelsBase/$repoId',
      );
      return response.data;
    } catch (e) {
      Log.debug('Failed to fetch HF model info for $repoId: $e');
      return null;
    }
  }

  Future<List<LmModelQuantOption>> fetchHfQuants(String repoId) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        'https://huggingface.co/api/models/$repoId/tree/main',
      );
      final quants = LmModelQuantOption.fromHfTree(response.data ?? []);
      Log.debug('Fetched ${quants.length} quants for $repoId');
      return quants;
    } catch (e) {
      Log.debug('Failed to fetch HF quants for $repoId: $e');
      return const [];
    }
  }

  Future<String?> fetchHfReadme(String repoId) async {
    try {
      final response = await _dio.get<String>(
        'https://huggingface.co/$repoId/raw/main/README.md',
        options: Options(responseType: ResponseType.plain),
      );
      return response.data;
    } catch (e) {
      Log.debug('Failed to fetch HF readme for $repoId: $e');
      return null;
    }
  }

  Future<LmModelDetail> fetchModelDetail(LmCatalogModel model) async {
    String? hfRepo = model.hfRepoId;
    String? readme;
    List<LmModelQuantOption> quants = const [];

    if (model.source == LmCatalogSource.lmStudio) {
      final manifest = await fetchArtifactManifest(model);
      hfRepo ??= manifest.hfRepoId;
      readme = await fetchLmStudioReadme(model);
    } else {
      hfRepo ??= model.id;
      final info = await fetchHfModelInfo(hfRepo);
      readme = await fetchHfReadme(hfRepo);
      if (info != null) {
        readme ??= info['cardData'] is Map
            ? (info['cardData'] as Map)['description']?.toString()
            : null;
      }
    }

    if (hfRepo != null && hfRepo.isNotEmpty) {
      quants = await fetchHfQuants(hfRepo);
    }

    return LmModelDetail(
      model: model.copyWith(hfRepoId: hfRepo),
      readme: readme,
      quants: quants,
      hfRepoId: hfRepo,
    );
  }

  Future<List<LmCatalogModel>> searchCatalog({
    required String query,
    required List<LmCatalogModel> staffPicks,
  }) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return staffPicks;

    final staffMatches =
        staffPicks.where((model) => model.matchesQuery(trimmed)).toList();

    List<LmCatalogModel> community = [];
    try {
      final page = await searchHuggingFace(query: trimmed);
      community = page.models;
    } catch (_) {}

    final staffIds = staffMatches.map((m) => m.id).toSet();
    community = community.where((m) => !staffIds.contains(m.id)).toList();

    return [...staffMatches, ...community];
  }
}
