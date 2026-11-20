import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/huggingface_model_search_service.dart';

class _CapturingInterceptor extends Interceptor {
  _CapturingInterceptor(this.captured);

  final Map<String, dynamic> captured;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    captured.addAll(options.queryParameters);
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: <Map<String, dynamic>>[],
      ),
    );
  }
}

void main() {
  group('HuggingFaceModelSearchService.searchModels', () {
    test('omits filter param when null/empty', () async {
      final captured = <String, dynamic>{};
      final service = HuggingFaceModelSearchService(
        dio: Dio()..interceptors.add(_CapturingInterceptor(captured)),
      );
      await service.searchModels(query: 'gemma');
      expect(captured.containsKey('filter'), isFalse);
      expect(captured['search'], 'gemma');
    });

    test('emits filter param when provided', () async {
      final captured = <String, dynamic>{};
      final service = HuggingFaceModelSearchService(
        dio: Dio()..interceptors.add(_CapturingInterceptor(captured)),
      );
      await service.searchModels(query: 'gemma', filter: 'gguf');
      expect(captured['filter'], 'gguf');
    });

    test('trims filter value', () async {
      final captured = <String, dynamic>{};
      final service = HuggingFaceModelSearchService(
        dio: Dio()..interceptors.add(_CapturingInterceptor(captured)),
      );
      await service.searchModels(query: 'gemma', filter: '  litert-lm  ');
      expect(captured['filter'], 'litert-lm');
    });

    test('ignores empty/whitespace filter', () async {
      final captured = <String, dynamic>{};
      final service = HuggingFaceModelSearchService(
        dio: Dio()..interceptors.add(_CapturingInterceptor(captured)),
      );
      await service.searchModels(query: 'gemma', filter: '   ');
      expect(captured.containsKey('filter'), isFalse);
    });

    test('passes through gguf/litert-lm/litertlm values', () async {
      for (final value in ['gguf', 'litert-lm', 'litertlm']) {
        final captured = <String, dynamic>{};
        final service = HuggingFaceModelSearchService(
          dio: Dio()..interceptors.add(_CapturingInterceptor(captured)),
        );
        await service.searchModels(query: '', filter: value);
        expect(captured['filter'], value);
      }
    });
  });
}
