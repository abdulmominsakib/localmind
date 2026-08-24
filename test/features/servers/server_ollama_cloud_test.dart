import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/constants/app_constants.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/data/models/server.dart';

void main() {
  group('Server base URL & endpoints for Ollama Cloud', () {
    Server makeCloudServer({String? apiKey}) {
      return Server(
        id: 'cloud-1',
        name: 'Ollama Cloud',
        type: ServerType.ollamaCloud,
        host: AppConstants.ollamaCloudBaseUrl,
        port: AppConstants.ollamaCloudDefaultPort,
        apiKey: apiKey,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );
    }

    test('baseUrl resolves to https://ollama.com', () {
      final server = makeCloudServer();
      expect(server.baseUrl, 'https://ollama.com');
    });

    test('displayAddress renders as ollama.com', () {
      final server = makeCloudServer();
      expect(server.displayAddress, 'ollama.com');
    });

    test('chat endpoint uses /api/chat on ollama.com', () {
      final server = makeCloudServer();
      expect(server.chatEndpoint, 'https://ollama.com/api/chat');
    });

    test('models endpoint uses /api/tags on ollama.com', () {
      final server = makeCloudServer();
      expect(server.modelsEndpoint, 'https://ollama.com/api/tags');
    });

    test('running models endpoint is empty for cloud (no /api/ps)', () {
      final server = makeCloudServer();
      expect(server.runningModelsEndpoint, isEmpty);
    });

    test('load/unload endpoints are empty for cloud', () {
      final server = makeCloudServer();
      expect(server.loadModelEndpoint, isEmpty);
      expect(server.unloadModelEndpoint, isEmpty);
    });

    test('api key is sent as Bearer authorization header', () {
      final server = makeCloudServer(apiKey: 'test-key-123');
      expect(server.authHeaders, {'Authorization': 'Bearer test-key-123'});
    });

    test('no Authorization header when api key is missing', () {
      final server = makeCloudServer();
      expect(server.authHeaders, isEmpty);
    });

    test('isOllamaCloud and isOllamaFamily getters work', () {
      final cloud = makeCloudServer();
      expect(cloud.isOllamaCloud, isTrue);
      expect(cloud.isOllamaFamily, isTrue);

      final local = Server(
        id: 'local-1',
        name: 'Local',
        type: ServerType.ollama,
        host: 'localhost',
        port: 11434,
        createdAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );
      expect(local.isOllamaCloud, isFalse);
      expect(local.isOllamaFamily, isTrue);
    });
  });

  group('buildServerBaseUrl ollamaCloud short-circuits', () {
    test('returns https://ollama.com regardless of host', () {
      final url = buildServerBaseUrl(
        'some-host.example',
        12345,
        ServerType.ollamaCloud,
      );
      expect(url, 'https://ollama.com');
    });
  });

  group('displayServerAddress for ollamaCloud', () {
    test('returns ollama.com', () {
      final display = displayServerAddress(
        'localhost',
        11434,
        ServerType.ollamaCloud,
      );
      expect(display, 'ollama.com');
    });
  });
}
