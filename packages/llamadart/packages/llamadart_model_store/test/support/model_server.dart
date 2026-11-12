import 'dart:io';

/// A local HTTP server for model files, counting the requests per path.
final class ModelServer {
  ModelServer._(this._server);

  /// Starts a server for [files], keyed by path such as `/model.gguf`.
  static Future<ModelServer> start(Map<String, List<int>> files) async {
    final server = ModelServer._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._files.addAll(files);
    server._server.listen(server._handle);
    return server;
  }

  final HttpServer _server;
  final Map<String, List<int>> _files = <String, List<int>>{};

  /// Requests received per path.
  final Map<String, int> requests = <String, int>{};

  /// Paths whose requests from now on get `503 Service Unavailable`.
  final Set<String> failing = <String>{};

  /// Requests for a path wait for its gate before the server answers.
  final Map<String, Future<void>> gates = <String, Future<void>>{};

  /// Headers of every request received.
  final List<HttpHeaders> requestHeaders = <HttpHeaders>[];

  /// The URL of [path] on this server.
  Uri url(String path, {Map<String, String>? query}) => Uri(
    scheme: 'http',
    host: _server.address.host,
    port: _server.port,
    path: path,
    queryParameters: query,
  );

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests[path] = (requests[path] ?? 0) + 1;
    requestHeaders.add(request.headers);
    final fail = failing.contains(path);
    await gates[path];
    final body = _files[path];
    if (fail) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
    } else if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.contentLength = body.length;
      request.response.headers.set(HttpHeaders.etagHeader, '"${body.length}"');
      request.response.add(body);
    }
    await request.response.close();
  }

  /// Stops the server.
  Future<void> close() => _server.close(force: true);
}
