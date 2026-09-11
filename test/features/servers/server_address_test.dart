import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/servers/data/models/server.dart';

void main() {
  group('Server address parsing', () {
    test('builds baseUrl for a bare host and port', () {
      final server = Server(
        id: '1',
        name: 'Local',
        type: ServerType.openAICompatible,
        host: 'localhost',
        port: 8080,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'http://localhost:8080');
    });

    test('preserves an explicit http URL without doubling the port', () {
      final server = Server(
        id: '1',
        name: 'Local',
        type: ServerType.openAICompatible,
        host: 'http://localhost:8080',
        port: 1234,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'http://localhost:8080');
      expect(server.displayAddress, 'http://localhost:8080');
    });

    test('accepts https URLs and keeps the configured port when missing', () {
      final server = Server(
        id: '1',
        name: 'Secure',
        type: ServerType.openAICompatible,
        host: 'https://localhost',
        port: 8443,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'https://localhost:8443');
      expect(server.displayAddress, 'https://localhost:8443');
    });

    test('keeps a host that already includes a port', () {
      final server = Server(
        id: '1',
        name: 'Local',
        type: ServerType.openAICompatible,
        host: 'localhost:8080',
        port: 1234,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'http://localhost:8080');
      expect(server.displayAddress, 'localhost:8080');
    });

    test('accepts a bare subdomain with no path', () {
      final server = Server(
        id: '1',
        name: 'Remote Ollama',
        type: ServerType.ollama,
        host: 'ollama.example.com',
        port: 11434,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'http://ollama.example.com:11434');
      expect(server.pathPrefix, isNull);
    });

    test('accepts https subdomain with no path', () {
      final server = Server(
        id: '1',
        name: 'Secure Ollama',
        type: ServerType.ollama,
        host: 'https://ollama.example.com',
        port: 11434,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'https://ollama.example.com:11434');
      expect(server.pathPrefix, isNull);
    });

    test(
      'Ollama server with explicit pathPrefix produces correct endpoints',
      () {
        final server = Server(
          id: '1',
          name: 'Reverse Proxy',
          type: ServerType.ollama,
          host: 'https://ai.example.com',
          port: 11434,
          pathPrefix: '/ollama',
          createdAt: DateTime(2026, 1, 1),
          lastConnectedAt: DateTime(2026, 1, 1),
        );

        expect(server.baseUrl, 'https://ai.example.com:11434');
        expect(server.pathPrefix, '/ollama');
        expect(
          server.modelsEndpoint,
          'https://ai.example.com:11434/ollama/api/tags',
        );
        expect(
          server.chatEndpoint,
          'https://ai.example.com:11434/ollama/api/chat',
        );
      },
    );

    test('trailing slash in pathPrefix is normalized via apiPathPrefix', () {
      final server = Server(
        id: '1',
        name: 'Trailing slash',
        type: ServerType.ollama,
        host: 'https://ai.example.com',
        port: 11434,
        pathPrefix: '/ollama/',
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.apiPathPrefix, '/ollama');
      expect(
        server.modelsEndpoint,
        'https://ai.example.com:11434/ollama/api/tags',
      );
    });

    test('root path becomes empty pathPrefix', () {
      final server = Server(
        id: '1',
        name: 'Root path',
        type: ServerType.ollama,
        host: 'https://ai.example.com',
        port: 11434,
        pathPrefix: '',
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.pathPrefix, '');
      expect(server.baseUrl, 'https://ai.example.com:11434');
      expect(server.modelsEndpoint, 'https://ai.example.com:11434/api/tags');
    });

    test('explicit port in host overrides default port', () {
      final server = Server(
        id: '1',
        name: 'Custom port',
        type: ServerType.ollama,
        host: 'https://ai.example.com:8443',
        port: 11434,
        pathPrefix: '/ollama',
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'https://ai.example.com:8443');
      expect(server.pathPrefix, '/ollama');
    });

    test('OpenAI-compatible with pathPrefix produces correct endpoints', () {
      final server = Server(
        id: '1',
        name: 'OpenAI proxy',
        type: ServerType.openAICompatible,
        host: 'https://ai.example.com',
        port: 8080,
        pathPrefix: '/openai',
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'https://ai.example.com:8080');
      expect(server.pathPrefix, '/openai');
      expect(
        server.modelsEndpoint,
        'https://ai.example.com:8080/openai/v1/models',
      );
      expect(
        server.chatEndpoint,
        'https://ai.example.com:8080/openai/v1/chat/completions',
      );
      expect(server.displayAddress, 'https://ai.example.com:8080/openai');
    });

    test('OpenAI-compatible with /v1 pathPrefix avoids double /v1', () {
      final server = Server(
        id: '1',
        name: 'OpenAI direct v1',
        type: ServerType.openAICompatible,
        host: 'https://ai.example.com',
        port: 8080,
        pathPrefix: '/v1',
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.modelsEndpoint, 'https://ai.example.com:8080/v1/models');
      expect(
        server.chatEndpoint,
        'https://ai.example.com:8080/v1/chat/completions',
      );
    });

    test(
      'OpenAI-compatible with nested /proxy/v1 pathPrefix avoids double /v1',
      () {
        final server = Server(
          id: '1',
          name: 'OpenAI nested proxy',
          type: ServerType.openAICompatible,
          host: 'https://ai.example.com',
          port: 8080,
          pathPrefix: '/proxy/v1',
          createdAt: DateTime(2026, 1, 1),
          lastConnectedAt: DateTime(2026, 1, 1),
        );

        expect(
          server.modelsEndpoint,
          'https://ai.example.com:8080/proxy/v1/models',
        );
        expect(
          server.chatEndpoint,
          'https://ai.example.com:8080/proxy/v1/chat/completions',
        );
      },
    );

    test('LM Studio with pathPrefix produces correct endpoints', () {
      final server = Server(
        id: '1',
        name: 'LM Studio proxy',
        type: ServerType.lmStudio,
        host: 'https://ai.example.com',
        port: 1234,
        pathPrefix: '/lmstudio',
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(
        server.modelsEndpoint,
        'https://ai.example.com:1234/lmstudio/api/v1/models',
      );
      expect(
        server.chatEndpoint,
        'https://ai.example.com:1234/lmstudio/api/v1/chat',
      );
      expect(server.displayAddress, 'https://ai.example.com:1234/lmstudio');
    });

    test('rejects URL with query string', () {
      expect(parseServerAddressInput('https://ai.example.com?foo=bar'), isNull);
    });

    test('rejects URL with fragment', () {
      expect(parseServerAddressInput('https://ai.example.com#frag'), isNull);
    });

    test('normalizeServerPathPrefix converts root slash to empty', () {
      expect(normalizeServerPathPrefix('/'), '');
    });

    test('normalizeServerPathPrefix strips trailing slash', () {
      expect(normalizeServerPathPrefix('/ollama/'), '/ollama');
    });

    test('extractPathPrefix returns empty for no path', () {
      final uri = Uri.parse('https://example.com');
      expect(extractPathPrefix(uri), '');
    });

    test('extractPathPrefix returns empty for root slash', () {
      final uri = Uri.parse('https://example.com/');
      expect(extractPathPrefix(uri), '');
    });

    test('extractPathPrefix returns path for valid prefix', () {
      final uri = Uri.parse('https://example.com/ollama');
      expect(extractPathPrefix(uri), '/ollama');
    });

    test('local IP still works as before', () {
      final server = Server(
        id: '1',
        name: 'Local',
        type: ServerType.openAICompatible,
        host: '192.168.1.100',
        port: 8080,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'http://192.168.1.100:8080');
      expect(server.pathPrefix, isNull);
    });

    test('existing bare host without port still works', () {
      final server = Server(
        id: '1',
        name: 'Local',
        type: ServerType.openAICompatible,
        host: 'localhost',
        port: 8080,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.baseUrl, 'http://localhost:8080');
    });
  });
}
