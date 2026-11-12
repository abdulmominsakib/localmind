@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'engine_test.dart' show MockLlamaBackend;

void main() {
  late Directory cache;
  late HttpServer modelHost;
  late HttpServer adapterHost;
  final adapterRequests = <HttpHeaders>[];

  Future<HttpServer> serve(List<HttpHeaders>? requests) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests?.add(request.headers);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentLength = 4
        ..add(const [1, 2, 3, 4]);
      await request.response.close();
    });
    return server;
  }

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('llamadart_lora_auth_');
    adapterRequests.clear();
    modelHost = await serve(null);
    adapterHost = await serve(adapterRequests);
  });

  tearDown(() async {
    await modelHost.close(force: true);
    await adapterHost.close(force: true);
    await cache.delete(recursive: true);
  });

  ModelSource on(HttpServer server, String file) =>
      ModelSource.url(Uri.parse('http://127.0.0.1:${server.port}/$file'));

  Future<void> load(LoraAdapterConfig adapter) async {
    final engine = LlamaEngine(MockLlamaBackend());
    addTearDown(engine.dispose);
    await engine.loadModelSource(
      on(modelHost, 'model.gguf'),
      options: ModelLoadOptions(
        cacheDirectory: cache.path,
        bearerToken: 'MODEL-HOST-TOKEN',
        headers: const {'X-Model-Host': 'model-secret'},
      ),
      modelParams: ModelParams(loras: [adapter]),
    );
  }

  test("an adapter host never receives the model load's bearer token or "
      'headers', () async {
    await load(LoraAdapterConfig.source(on(adapterHost, 'adapter.gguf')));

    expect(adapterRequests, isNotEmpty);
    for (final headers in adapterRequests) {
      expect(headers.value(HttpHeaders.authorizationHeader), isNull);
      expect(headers.value('X-Model-Host'), isNull);
    }
    final cached = cache
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last);
    expect(cached, containsAll(['model.gguf', 'adapter.gguf']));
  });

  test("an adapter host receives only the adapter's own credentials", () async {
    await load(
      LoraAdapterConfig.source(
        on(adapterHost, 'adapter.gguf'),
        download: ModelLoadOptions(
          cacheDirectory: cache.path,
          bearerToken: 'ADAPTER-TOKEN',
        ),
      ),
    );

    expect(adapterRequests, isNotEmpty);
    for (final headers in adapterRequests) {
      expect(
        headers.value(HttpHeaders.authorizationHeader),
        'Bearer ADAPTER-TOKEN',
      );
      expect(headers.value('X-Model-Host'), isNull);
    }
  });

  test('the resolved draft config crosses an isolate without the caller\'s '
      'download options', () async {
    final draft = File(p.join(cache.path, 'draft.gguf'))..writeAsBytesSync([1]);
    final token = _PortCancelToken();
    addTearDown(token.port.close);
    final backend = _IsolateBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel(p.join(cache.path, 'model.gguf'));

    await engine
        .generate(
          'hi',
          params: GenerationParams(
            speculativeDecodingConfig: SpeculativeDecodingConfig.draftSimple(
              draftModel: ModelSource.path(draft.path),
              draftModelDownload: ModelLoadOptions(cancelToken: token),
            ),
          ),
        )
        .drain<void>();

    expect(backend.draftPathInIsolate, p.normalize(p.absolute(draft.path)));
  });

  test('a config without a draft model crosses an isolate without the '
      "caller's download options", () async {
    final backend = _IsolateBackend();
    final engine = LlamaEngine(backend);
    addTearDown(engine.dispose);
    await engine.loadModel(p.join(cache.path, 'model.gguf'));

    for (final config in [
      SpeculativeDecodingConfig.mtp(
        draftModelDownload: ModelLoadOptions(cancelToken: _CompleterToken()),
      ),
      SpeculativeDecodingConfig(
        strategies: const [SpeculativeDecodingStrategy.ngramSimple],
        draftModelDownload: ModelLoadOptions(cancelToken: _CompleterToken()),
      ),
    ]) {
      await engine
          .generate(
            'hi',
            params: GenerationParams(speculativeDecodingConfig: config),
          )
          .drain<void>();
      expect(backend.crossedIsolate, isTrue);
      backend.crossedIsolate = false;
    }
  });
}

/// A caller token that, like one built on a port, cannot cross an isolate.
class _PortCancelToken extends ModelDownloadCancelToken {
  final RawReceivePort port = RawReceivePort();
}

/// Copies the request into another isolate, as the llama.cpp worker does.
class _IsolateBackend extends MockLlamaBackend {
  String? draftPathInIsolate;
  bool crossedIsolate = false;

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) async* {
    draftPathInIsolate = await Isolate.run(
      () => params.speculativeDecodingConfig!.draftModelPath,
    );
    crossedIsolate = true;
    yield* super.generate(contextHandle, prompt, params, parts: parts);
  }
}

/// A caller token holding a completer, which cannot cross an isolate.
class _CompleterToken extends ModelDownloadCancelToken {
  final Completer<void> done = Completer<void>();
}
