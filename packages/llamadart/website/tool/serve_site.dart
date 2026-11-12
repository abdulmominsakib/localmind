// Serves the finalized site like GitHub Pages: `/route` maps to
// `route.html`, then `route/index.html`, and unknown paths get `404.html`.
//
//   dart run tool/serve_site.dart [--port 8080] [build/jaspr]
import 'dart:io';

import 'package:path/path.dart' as p;

const _types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.xml': 'application/xml',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
};

Future<void> main(List<String> args) async {
  var port = 8080;
  var root = 'build/jaspr';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--port') {
      port = int.parse(args[++i]);
    } else {
      root = args[i];
    }
  }
  final base = Directory(root).absolute.path;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('[docs] Serving $root at http://localhost:$port');
  await for (final request in server) {
    final path = p.normalize(
      Uri.decodeComponent(request.uri.path).substring(1),
    );
    File? file;
    for (final candidate in [path, '$path.html', p.join(path, 'index.html')]) {
      final f = File(p.join(base, candidate));
      if (p.isWithin(base, f.path) || f.path == base) {
        if (f.existsSync()) {
          file = f;
          break;
        }
      }
    }
    final response = request.response;
    if (file == null) {
      response.statusCode = HttpStatus.notFound;
      file = File(p.join(base, '404.html'));
    }
    response.headers.contentType = ContentType.parse(
      _types[p.extension(file.path)] ?? 'application/octet-stream',
    );
    await response.addStream(file.openRead());
    await response.close();
  }
}
