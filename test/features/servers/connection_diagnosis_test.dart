import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/data/models/connection_diagnosis.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/data/server_api_service.dart';

/// Answers each request by the first matching path suffix: an int is an
/// HTTP status, a [DioExceptionType] is a transport failure.
class _ProbeInterceptor extends Interceptor {
  _ProbeInterceptor(this.routes, {this.fallback = DioExceptionType.unknown});

  final Map<String, Object> routes;
  final Object fallback;
  final List<String> paths = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    paths.add(options.uri.path);
    final outcome =
        routes.entries
            .where((e) => options.uri.path.endsWith(e.key))
            .map((e) => e.value)
            .firstOrNull ??
        fallback;
    if (outcome is int) {
      final response = Response(
        requestOptions: options,
        statusCode: outcome,
        data: {'data': []},
      );
      if (outcome >= 500) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: response,
            type: DioExceptionType.badResponse,
          ),
        );
      } else {
        handler.resolve(response);
      }
      return;
    }
    handler.reject(
      DioException(
        requestOptions: options,
        type: outcome as DioExceptionType,
        message: 'Connection refused',
      ),
    );
  }
}

Server _server(ServerType type, {String? apiKey}) => Server(
  id: 's',
  name: 'Test',
  type: type,
  host: '192.168.1.20',
  port: type == ServerType.ollama ? 11434 : 1234,
  apiKey: apiKey,
  createdAt: DateTime(2026),
  lastConnectedAt: DateTime(2026),
);

Future<ConnectionDiagnosis> _diagnose(
  Server server,
  _ProbeInterceptor interceptor,
) => ServerApiService(
  Dio()..interceptors.add(interceptor),
).diagnoseConnection(server);

void main() {
  test('refused socket on every endpoint reports unreachable', () async {
    final result = await _diagnose(
      _server(ServerType.ollama),
      _ProbeInterceptor(const {}, fallback: DioExceptionType.connectionError),
    );
    expect(result.ok, isFalse);
    expect(result.failure, ConnectionFailureKind.unreachable);
  });

  test('timeout is reported separately from a refused socket', () async {
    final result = await _diagnose(
      _server(ServerType.ollama),
      _ProbeInterceptor(const {}, fallback: DioExceptionType.connectionTimeout),
    );
    expect(result.failure, ConnectionFailureKind.timeout);
  });

  test('an HTTP answer outranks socket failures on other endpoints', () async {
    final result = await _diagnose(
      _server(ServerType.ollama),
      _ProbeInterceptor(const {
        '/api/tags': 401,
        '/api/version': DioExceptionType.connectionError,
      }),
    );
    expect(result.failure, ConnectionFailureKind.unauthorized);
    expect(result.statusCode, 401);
  });

  test('404 everywhere reports a route mismatch', () async {
    final result = await _diagnose(
      _server(ServerType.ollama),
      _ProbeInterceptor(const {'/api/tags': 404, '/api/version': 404}),
    );
    expect(result.failure, ConnectionFailureKind.notFound);
  });

  test('5xx is an unexpected status with its code', () async {
    final result = await _diagnose(
      _server(ServerType.ollama),
      _ProbeInterceptor(const {'/api/tags': 502, '/api/version': 502}),
    );
    expect(result.failure, ConnectionFailureKind.unexpectedStatus);
    expect(result.statusCode, 502);
  });

  test('LM Studio native API reachable is a clean success', () async {
    final result = await _diagnose(
      _server(ServerType.lmStudio),
      _ProbeInterceptor(const {'/api/v1/models': 200}),
    );
    expect(result.ok, isTrue);
    expect(result.nativeApiUnavailable, isFalse);
  });

  test('LM Studio proxy serving only /v1 is flagged', () async {
    final result = await _diagnose(
      _server(ServerType.lmStudio),
      _ProbeInterceptor(const {'/api/v1/models': 404, '/v1/models': 200}),
    );
    expect(result.ok, isTrue);
    expect(result.nativeApiUnavailable, isTrue);
  });

  test('Standard Compute without a key fails before any request', () async {
    final interceptor = _ProbeInterceptor(const {});
    final result = await _diagnose(
      _server(ServerType.standardCompute, apiKey: ''),
      interceptor,
    );
    expect(result.failure, ConnectionFailureKind.missingApiKey);
    expect(interceptor.paths, isEmpty);
  });

  test('testConnection still returns the boolean outcome', () async {
    final service = ServerApiService(
      Dio()..interceptors.add(_ProbeInterceptor(const {'/api/tags': 200})),
    );
    expect(await service.testConnection(_server(ServerType.ollama)), isTrue);
  });
}
