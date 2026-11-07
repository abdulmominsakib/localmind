import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/huggingface_model_search_service.dart';
import 'package:localmind/features/on_device/data/models/huggingface_model_info.dart';

class _InfoInterceptor extends Interceptor {
  _InfoInterceptor(this.payload);
  final Map<String, dynamic> payload;
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(Response(requestOptions: options, statusCode: 200, data: payload));
  }
}

void main() {
  test('fetchModelInfo parses fields and fileOid', () async {
    final payload = {
      'id': 'org/repo',
      'sha': 'abc123',
      'lastModified': '2026-11-05T00:00:00.000Z',
      'pipeline_tag': 'text-generation',
      'library_name': 'transformers',
      'cardData': {'license': 'apache-2.0', 'language': ['en'], 'base_model': 'org/base'},
      'gguf': {'architecture': 'llama', 'context_length': 4096, 'total': 7.0},
      'tags': ['text-generation'],
      'siblings': [
        {'rfilename': 'model.gguf', 'blobId': 'blob-oid-1'},
      ],
    };
    final service = HuggingFaceModelSearchService(
      dio: Dio()..interceptors.add(_InfoInterceptor(payload)),
    );
    final info = await service.fetchModelInfo('org/repo', rfilename: 'model.gguf');
    expect(info, isNotNull);
    expect(info!.sha, 'abc123');
    expect(info.pipelineTag, 'text-generation');
    expect(info.license, 'apache-2.0');
    expect(info.architecture, 'llama');
    expect(info.contextLength, 4096);
    expect(info.fileOid, 'blob-oid-1');
    expect(info.languages, ['en']);
    expect(info.baseModel, 'org/base');
  });

  test('fetchModelInfo returns null on failure', () async {
    final service = HuggingFaceModelSearchService(
      dio: Dio()..interceptors.add(InterceptorsWrapper(
        onRequest: (o, h) => h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError)),
      )),
    );
    final info = await service.fetchModelInfo('org/repo');
    expect(info, isNull);
  });
}
