import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/inference/local_inference.dart';
import 'package:localmind/features/local_api/data/local_api_server.dart';

void main() {
  late _FakeInference inference;
  late InferenceCoordinator coordinator;
  late LocalApiServer server;
  late HttpClient client;
  late int port;
  const key = 'test-only-key';

  setUp(() async {
    inference = _FakeInference();
    coordinator = InferenceCoordinator();
    server = LocalApiServer(
      inference: inference,
      coordinator: coordinator,
      apiKey: key,
    );
    port = await server.start(port: 0, lan: false);
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  Future<({int status, String body, String? contentType})> call(
    String path, {
    String? token = key,
    Object? body,
    String? raw,
  }) async {
    final request = await client.openUrl(
      body != null || raw != null ? 'POST' : 'GET',
      Uri.parse('http://127.0.0.1:$port/v1/$path'),
    );
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    if (body != null || raw != null) {
      request.headers.contentType = ContentType.json;
      request.write(raw ?? jsonEncode(body));
    }
    final response = await request.close();
    return (
      status: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
      contentType: response.headers.contentType?.mimeType,
    );
  }

  const textRequest = {
    'model': 'local-model',
    'messages': [
      {'role': 'user', 'content': 'Hi'},
    ],
  };

  test(
    'model discovery requires a key and rotation revokes the previous key',
    () async {
      expect((await call('models', token: null)).status, 401);
      expect((await call('models', token: 'wrong')).status, 401);
      final valid = await call('models');
      expect(valid.status, 200);
      expect(jsonDecode(valid.body)['data'].single['id'], 'local-model');

      server.rotateKey('replacement');
      expect((await call('models')).status, 401);
      expect((await call('models', token: 'replacement')).status, 200);
    },
  );

  test(
    'validates model selection, inputs and request size before inference',
    () async {
      expect((await call('chat/completions', raw: '{')).status, 400);
      expect(
        (await call('chat/completions', raw: 'a' * (512 * 1024 + 1))).status,
        413,
      );
      expect(
        (await call(
          'chat/completions',
          body: {...textRequest, 'model': 'wrong'},
        )).status,
        404,
      );
      inference.model = null;
      expect((await call('chat/completions', body: textRequest)).status, 503);
      expect(inference.requests, isEmpty);
    },
  );

  test(
    'returns a stateless text completion and reports native token exhaustion',
    () async {
      inference.events = (_, _) async* {
        yield const InferenceText('Hel');
        yield const InferenceText('lo');
        yield const InferenceFinished(length: true);
      };
      final response = await call('chat/completions', body: textRequest);
      final choice = jsonDecode(response.body)['choices'].single;
      expect(response.status, 200);
      expect(choice['message']['content'], 'Hello');
      expect(choice['finish_reason'], 'length');

      await call(
        'chat/completions',
        body: {
          ...textRequest,
          'messages': [
            {'role': 'user', 'content': 'New prompt'},
          ],
        },
      );
      expect(inference.requests.last.messages.single.text, 'New prompt');
    },
  );

  test(
    'streams a function call and accepts its correlated tool result',
    () async {
      final tools = [
        {
          'type': 'function',
          'function': {
            'name': 'lookup_budget',
            'parameters': {'type': 'object', 'properties': <String, Object>{}},
          },
        },
      ];
      inference.events = (request, _) async* {
        if (request.tools.isEmpty) {
          expect(request.messages.last.role, InferenceRole.tool);
          yield InferenceText('The budget is ${request.messages.last.text}.');
        } else {
          yield const InferenceCall(InferenceToolCall('lookup_budget', '{}'));
        }
      };
      final initial = await call(
        'chat/completions',
        body: {...textRequest, 'tools': tools, 'stream': true},
      );
      expect(initial.status, 200);
      expect(initial.contentType, 'text/event-stream');
      final lines = initial.body
          .split('\n')
          .where((line) => line.startsWith('data: '))
          .toList();
      expect(lines.removeLast(), 'data: [DONE]');
      final choices = lines
          .map((line) => jsonDecode(line.substring(6))['choices'].single)
          .toList();
      expect(choices.first['delta']['role'], 'assistant');
      expect(choices.last['finish_reason'], 'tool_calls');
      final tool = Map<String, dynamic>.from(
        choices[1]['delta']['tool_calls'].single,
      )..remove('index');
      final messages = [
        {'role': 'user', 'content': 'Hi'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [tool],
        },
        {'role': 'tool', 'tool_call_id': tool['id'], 'content': '42'},
      ];
      final followUp = await call(
        'chat/completions',
        body: {
          'model': 'local-model',
          'messages': messages,
          'tools': tools,
          'tool_choice': 'none',
        },
      );
      expect(followUp.status, 200);
      expect(
        jsonDecode(followUp.body)['choices'].single['message']['content'],
        'The budget is 42.',
      );

      final invalid = await call(
        'chat/completions',
        body: {
          'model': 'local-model',
          'messages': [
            ...messages.take(2),
            {...messages.last, 'tool_call_id': 'unknown'},
          ],
        },
      );
      expect(invalid.status, 400);

      inference.model = const LocalInferenceModel(
        'local-model',
        supportsTools: false,
        supportsSampling: true,
      );
      final unsupported = await call(
        'chat/completions',
        body: {...textRequest, 'tools': tools},
      );
      expect(unsupported.status, 400);
      expect(
        jsonDecode(unsupported.body)['error']['code'],
        'unsupported_tools',
      );
    },
  );

  test(
    'a competing chat lease rejects new inference without queueing',
    () async {
      final lease = coordinator.tryAcquire()!;
      try {
        final response = await call('chat/completions', body: textRequest);
        expect(response.status, 429);
        expect(inference.requests, isEmpty);
      } finally {
        lease.release();
      }
      expect((await call('chat/completions', body: textRequest)).status, 200);
    },
  );

  for (final streaming in [false, true]) {
    test(
      'a disconnected client cancels inference (streaming: $streaming)',
      () async {
        final started = Completer<void>();
        final cancelled = Completer<void>();
        final upstream = StreamController<InferenceEvent>();
        inference.events = (_, cancellation) async* {
          final iterator = StreamIterator(upstream.stream);
          try {
            started.complete();
            while (await cancellation.moveNext(iterator)) {
              yield iterator.current;
            }
          } finally {
            await iterator.cancel();
            if (cancellation.isCancelled) cancelled.complete();
          }
        };
        final pending = call(
          'chat/completions',
          body: {...textRequest, 'stream': streaming},
        ).then<void>((_) {}, onError: (Object _) {});
        await started.future;
        client.close(force: true);
        await cancelled.future.timeout(const Duration(seconds: 3));
        await upstream.close();
        await pending;
      },
    );
  }

  test(
    'shutdown waits for inference cleanup before a model transition',
    () async {
      final started = Completer<void>();
      final cancelling = Completer<void>();
      final allowCleanup = Completer<void>();
      final upstream = StreamController<InferenceEvent>();
      inference.events = (_, cancellation) async* {
        final iterator = StreamIterator(upstream.stream);
        try {
          started.complete();
          while (await cancellation.moveNext(iterator)) {
            yield iterator.current;
          }
        } finally {
          cancelling.complete();
          await allowCleanup.future;
          await iterator.cancel();
        }
      };

      final response = call(
        'chat/completions',
        body: textRequest,
      ).then<void>((_) {}, onError: (Object _) {});
      await started.future;
      var transitioned = false;
      final transition = coordinator.transition(
        () async => transitioned = true,
      );
      final stop = server.stop();
      await cancelling.future;
      expect(transitioned, isFalse);
      expect(coordinator.tryAcquire(), isNull);
      allowCleanup.complete();
      await stop;
      await transition;
      await upstream.close();
      await response;
      expect(transitioned, isTrue);
    },
  );
}

class _FakeInference implements LocalInference {
  @override
  LocalInferenceModel? model = const LocalInferenceModel(
    'local-model',
    supportsTools: true,
    supportsSampling: true,
  );
  final requests = <InferenceRequest>[];
  Stream<InferenceEvent> Function(InferenceRequest, InferenceCancellation)
  events = (_, _) => Stream.value(const InferenceText('Hello'));

  @override
  Stream<InferenceEvent> generate(
    InferenceRequest request,
    InferenceCancellation cancellation,
  ) {
    requests.add(request);
    return events(request, cancellation);
  }
}
