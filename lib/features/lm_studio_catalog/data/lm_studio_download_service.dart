import 'package:dio/dio.dart';

import '../../servers/data/models/server.dart';
import 'catalog_models.dart';

class LmStudioDownloadService {
  LmStudioDownloadService(this._dio);

  final Dio _dio;

  Future<LmDownloadJob> startDownload({
    required Server server,
    required LmCatalogModel model,
    String? quantization,
  }) async {
    final body = <String, dynamic>{
      'model': model.catalogId,
      if (quantization != null && quantization.isNotEmpty)
        'quantization': quantization,
    };

    final response = await _dio.post<Map<String, dynamic>>(
      '${server.baseUrl}/api/v1/models/download',
      data: body,
      options: Options(headers: buildServerAuthHeaders(server)),
    );

    final data = response.data ?? {};
    return LmDownloadJob.fromJson(
      data,
      modelId: model.catalogId,
      displayName: model.displayName,
    );
  }

  Future<LmDownloadJob> fetchStatus({
    required Server server,
    required LmDownloadJob job,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${server.baseUrl}/api/v1/models/download/status/${Uri.encodeComponent(job.jobId)}',
      options: Options(headers: buildServerAuthHeaders(server)),
    );

    return LmDownloadJob.fromJson(
      response.data ?? {},
      modelId: job.modelId,
      displayName: job.displayName,
    );
  }
}
