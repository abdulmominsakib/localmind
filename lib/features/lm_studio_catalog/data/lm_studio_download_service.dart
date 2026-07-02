import 'package:dio/dio.dart';

import '../../servers/data/models/server.dart';
import 'catalog_models.dart';

class LmDownloadJobNotFoundException implements Exception {
  const LmDownloadJobNotFoundException(this.jobId);
  final String jobId;
}

class LmStudioDownloadService {
  LmStudioDownloadService(this._dio);

  final Dio _dio;

  LmDownloadRequest buildDownloadRequest({
    required LmCatalogModel model,
    required LmModelDetail detail,
    LmModelQuantOption? quant,
  }) {
    final hfUrl = detail.hfRepoId != null
        ? 'https://huggingface.co/${detail.hfRepoId}'
        : model.hfDownloadBaseUrl;

    if (hfUrl != null && quant != null) {
      return LmDownloadRequest(
        model: hfUrl,
        quantization: quant.quantization,
        displayName: '${model.displayLabel} ${quant.quantization}',
      );
    }

    if (hfUrl != null) {
      return LmDownloadRequest(
        model: hfUrl,
        displayName: model.displayLabel,
      );
    }

    if (model.source == LmCatalogSource.lmStudio) {
      return LmDownloadRequest(
        model: model.catalogId,
        displayName: model.displayLabel,
      );
    }

    return LmDownloadRequest(
      model: 'https://huggingface.co/${model.id}',
      quantization: quant?.quantization,
      displayName: model.displayLabel,
    );
  }

  Future<LmDownloadJob> startDownload({
    required Server server,
    required LmDownloadRequest request,
  }) async {
    final body = <String, dynamic>{
      'model': request.model,
      if (request.quantization != null && request.quantization!.isNotEmpty)
        'quantization': request.quantization,
    };

    final response = await _dio.post<Map<String, dynamic>>(
      '${server.baseUrl}/api/v1/models/download',
      data: body,
      options: Options(
        headers: buildServerAuthHeaders(server),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final data = response.data ?? {};
    if (response.statusCode != 200 || data['error'] != null) {
      final error = data['error'];
      final message = error is Map
          ? error['message']?.toString()
          : error?.toString();
      throw Exception(message ?? 'Download failed');
    }

    return LmDownloadJob.fromJson(
      data,
      modelId: request.model,
      displayName: request.displayName ?? request.model,
    );
  }

  Future<LmDownloadJob> fetchStatus({
    required Server server,
    required LmDownloadJob job,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '${server.baseUrl}/api/v1/models/download/status/${Uri.encodeComponent(job.jobId)}',
      options: Options(
        headers: buildServerAuthHeaders(server),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    final data = response.data ?? {};
    if (response.statusCode != 200 || data['error'] != null) {
      final error = data['error'];
      final type = error is Map ? error['type']?.toString() : null;
      if (type == 'job_not_found') {
        throw LmDownloadJobNotFoundException(job.jobId);
      }
      final message = error is Map
          ? error['message']?.toString()
          : error?.toString();
      throw Exception(message ?? 'Failed to fetch download status');
    }

    return LmDownloadJob.fromJson(
      data,
      modelId: job.modelId,
      displayName: job.displayName,
    );
  }
}
