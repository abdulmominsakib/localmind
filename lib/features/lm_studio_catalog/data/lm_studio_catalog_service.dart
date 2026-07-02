import 'package:dio/dio.dart';

import '../../../core/logger/app_logger.dart';
import 'catalog_models.dart';

class LmStudioCatalogService {
  LmStudioCatalogService(this._dio);

  final Dio _dio;

  static const _staffPicksUrl =
      'https://lmstudio.ai/api/v1/models?action=staff-picks';

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

  Future<List<LmCatalogModel>> searchHuggingFace({
    required String query,
    int limit = 30,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final response = await _dio.get<List<dynamic>>(
        'https://huggingface.co/api/models',
        queryParameters: {
          'search': trimmed,
          'filter': 'gguf',
          'sort': 'likes',
          'direction': '-1',
          'limit': limit,
        },
      );
      final data = response.data;
      if (data == null) return [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(LmCatalogModel.fromHuggingFaceJson)
          .toList();
    } catch (e) {
      Log.warning('Failed to search Hugging Face GGUF models: $e');
      rethrow;
    }
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
      community = await searchHuggingFace(query: trimmed);
    } catch (_) {}

    final staffIds = staffMatches.map((m) => m.id).toSet();
    community = community.where((m) => !staffIds.contains(m.id)).toList();

    return [...staffMatches, ...community];
  }

  Future<String?> fetchReadme(LmCatalogModel model) async {
    if (model.source != LmCatalogSource.lmStudio) return null;
    try {
      final response = await _dio.get<dynamic>(model.readmeUrl);
      final data = response.data;
      if (data is String) return data;
      if (data is Map && data['readme'] is String) {
        return data['readme'] as String;
      }
      return data?.toString();
    } catch (e) {
      Log.debug('Failed to fetch readme for ${model.id}: $e');
      return null;
    }
  }
}
