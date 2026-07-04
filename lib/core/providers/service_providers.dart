import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../constants/app_constants.dart';
import '../../features/servers/data/server_api_service.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: Duration(milliseconds: AppConstants.connectionTimeoutMs),
      receiveTimeout: Duration(milliseconds: AppConstants.receiveTimeoutMs),
    ),
  );
  dio.interceptors.add(RedirectInterceptor(dio));
  return dio;
});

final serverApiServiceProvider = Provider<ServerApiService>((ref) {
  return ServerApiService(ref.read(dioProvider));
});

class RedirectInterceptor extends Interceptor {
  final Dio _dio;

  RedirectInterceptor(this._dio);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final statusCode = response.statusCode;
    if (statusCode == 307 || statusCode == 308) {
      final location = response.headers.value('location');
      if (location != null) {
        try {
          final redirectedResponse = await _performRedirect(response.requestOptions, location);
          return handler.resolve(redirectedResponse);
        } catch (_) {
          return handler.next(response);
        }
      }
    }
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    if (response != null && (response.statusCode == 307 || response.statusCode == 308)) {
      final location = response.headers.value('location');
      if (location != null) {
        try {
          final redirectedResponse = await _performRedirect(err.requestOptions, location);
          return handler.resolve(redirectedResponse);
        } catch (e) {
          if (e is DioException) {
            return handler.next(e);
          }
          return handler.next(DioException(
            requestOptions: err.requestOptions,
            error: e,
            type: DioExceptionType.unknown,
          ));
        }
      }
    }
    super.onError(err, handler);
  }

  Future<Response<dynamic>> _performRedirect(RequestOptions requestOptions, String location) async {
    var redirectUrl = location;
    final originalUri = requestOptions.uri;
    if (!redirectUrl.startsWith('http://') && !redirectUrl.startsWith('https://')) {
      final baseUri = Uri.parse(requestOptions.path);
      redirectUrl = baseUri.resolve(redirectUrl).toString();
    }

    final extra = Map<String, dynamic>.from(requestOptions.extra);
    final redirectCount = (extra['redirectCount'] as int? ?? 0) + 1;
    if (redirectCount > 5) {
      throw DioException(
        requestOptions: requestOptions,
        error: 'Too many redirects',
        type: DioExceptionType.unknown,
      );
    }
    extra['redirectCount'] = redirectCount;

    // Never replay credentials (API keys, auth tokens) to a different
    // origin than the one the caller actually configured — a redirect
    // response (e.g. from a compromised or misconfigured server) must not
    // be able to exfiltrate them to an arbitrary host.
    final redirectUri = Uri.parse(redirectUrl);
    final sameOrigin = redirectUri.scheme == originalUri.scheme &&
        redirectUri.host == originalUri.host &&
        redirectUri.port == originalUri.port;
    final headers = Map<String, dynamic>.from(requestOptions.headers);
    if (!sameOrigin) {
      headers.removeWhere(
        (key, _) => key.toLowerCase() == 'authorization',
      );
    }

    return _dio.request(
      redirectUrl,
      data: requestOptions.data,
      queryParameters: requestOptions.queryParameters,
      options: Options(
        method: requestOptions.method,
        headers: headers,
        contentType: requestOptions.contentType,
        responseType: requestOptions.responseType,
        extra: extra,
      ),
    );
  }
}

