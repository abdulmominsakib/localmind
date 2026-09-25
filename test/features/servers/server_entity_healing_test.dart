import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/storage/entities.dart';
import 'package:localmind/features/servers/data/models/server.dart';

void main() {
  group('ServerEntity.resolveServerType', () {
    test(
      'resolves on-device server when typeIndex was 4 before Ollama Cloud was inserted',
      () {
        // Prior to Ollama Cloud (commit 51996bb), onDevice had index 4.
        // After inserting Ollama Cloud at index 3, index 4 became openRouter.
        // Existing on-device records in ObjectBox have typeIndex: 4.
        final type = ServerEntity.resolveServerType(
          typeIndex: 4,
          id: 'on-device',
          name: 'On-Device',
          host: '',
          port: 0,
        );

        expect(type, ServerType.onDevice);
      },
    );

    test('resolves on-device server by id even if typeIndex is unexpected', () {
      final type = ServerEntity.resolveServerType(
        typeIndex: 99,
        id: 'on-device',
        name: 'Custom On Device',
        host: '',
        port: 0,
      );

      expect(type, ServerType.onDevice);
    });

    test(
      'resolves on-device server created with timestamp id from onboarding',
      () {
        final type = ServerEntity.resolveServerType(
          typeIndex: 4,
          id: '1720000000000',
          name: 'On-Device',
          host: '',
          port: 0,
        );

        expect(type, ServerType.onDevice);
      },
    );

    test(
      'resolves on-device server with empty host and port 0 without API key',
      () {
        final type = ServerEntity.resolveServerType(
          typeIndex: 4,
          id: 'custom-local',
          name: 'Local inference',
          host: '',
          port: 0,
        );

        expect(type, ServerType.onDevice);
      },
    );

    test(
      'resolves openRouter server when typeIndex was 3 before Ollama Cloud was inserted',
      () {
        // Prior to Ollama Cloud, openRouter had index 3.
        // When Ollama Cloud was inserted at index 3, existing OpenRouter records
        // were deserialized as ollamaCloud.
        final type = ServerEntity.resolveServerType(
          typeIndex: 3,
          id: 'openrouter-1',
          name: 'OpenRouter',
          host: 'https://openrouter.ai/api/v1',
          port: 443,
          apiKey: 'sk-or-v1-testkey',
        );

        expect(type, ServerType.openRouter);
      },
    );

    test(
      'resolves openRouter server by sk-or apiKey even with generic host',
      () {
        final type = ServerEntity.resolveServerType(
          typeIndex: 3,
          id: 'openrouter-2',
          name: 'Cloud AI',
          host: 'https://openrouter.ai',
          port: 443,
          apiKey: 'sk-or-testkey',
        );

        expect(type, ServerType.openRouter);
      },
    );

    test('resolves ollamaCloud correctly when host points to ollama.com', () {
      final type = ServerEntity.resolveServerType(
        typeIndex: 3,
        id: 'ollama-cloud-1',
        name: 'Ollama Cloud',
        host: 'https://ollama.com',
        port: 443,
      );

      expect(type, ServerType.ollamaCloud);
    });

    test('preserves standard server types by valid typeIndex', () {
      expect(
        ServerEntity.resolveServerType(
          typeIndex: 0,
          id: 'lm-studio',
          name: 'LM Studio',
          host: 'localhost',
          port: 1234,
        ),
        ServerType.lmStudio,
      );

      expect(
        ServerEntity.resolveServerType(
          typeIndex: 1,
          id: 'oai-compat',
          name: 'Custom OpenAI',
          host: 'http://localhost:8000',
          port: 8000,
        ),
        ServerType.openAICompatible,
      );

      expect(
        ServerEntity.resolveServerType(
          typeIndex: 2,
          id: 'ollama-local',
          name: 'Ollama',
          host: 'http://localhost:11434',
          port: 11434,
        ),
        ServerType.ollama,
      );

      expect(
        ServerEntity.resolveServerType(
          typeIndex: 5,
          id: 'on-device-new',
          name: 'On-Device',
          host: '',
          port: 0,
        ),
        ServerType.onDevice,
      );

      expect(
        ServerEntity.resolveServerType(
          typeIndex: 6,
          id: 'requesty-1',
          name: 'Requesty',
          host: 'router.requesty.ai',
          port: 443,
        ),
        ServerType.requesty,
      );
    });
  });

  group('ServerEntity.toDomain healing', () {
    test('heals corrupted on-device entity to ServerType.onDevice', () {
      final now = DateTime(2026, 1, 1);
      final entity = ServerEntity(
        id: 'on-device',
        name: 'On-Device',
        typeIndex: 4, // Was onDevice, shifted to openRouter
        host: '',
        port: 0,
        createdAt: now,
        lastConnectedAt: now,
        statusIndex: 1,
      );

      final domain = entity.toDomain();
      expect(domain.id, 'on-device');
      expect(domain.type, ServerType.onDevice);
      expect(domain.isOnDevice, isTrue);
    });

    test('heals shifted OpenRouter entity to ServerType.openRouter', () {
      final now = DateTime(2026, 1, 1);
      final entity = ServerEntity(
        id: 'or-server',
        name: 'OpenRouter Cloud',
        typeIndex: 3, // Was openRouter, shifted to ollamaCloud
        host: 'https://openrouter.ai/api/v1',
        port: 443,
        apiKey: 'sk-or-v1-abcdef',
        createdAt: now,
        lastConnectedAt: now,
        statusIndex: 1,
      );

      final domain = entity.toDomain();
      expect(domain.type, ServerType.openRouter);
      expect(domain.isOnDevice, isFalse);
    });
  });

  group('Server.isOnDevice', () {
    test('returns true for ServerType.onDevice', () {
      final server = Server(
        id: 'custom-id',
        name: 'On-Device',
        type: ServerType.onDevice,
        host: '',
        port: 0,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.isOnDevice, isTrue);
    });

    test('returns true for id on-device even if type was corrupted', () {
      final server = Server(
        id: 'on-device',
        name: 'On-Device',
        type: ServerType.openRouter,
        host: '',
        port: 0,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.isOnDevice, isTrue);
    });

    test('returns false for remote servers', () {
      final server = Server(
        id: 'cloud-server',
        name: 'OpenRouter',
        type: ServerType.openRouter,
        host: 'https://openrouter.ai',
        port: 443,
        createdAt: DateTime(2026, 1, 1),
        lastConnectedAt: DateTime(2026, 1, 1),
      );

      expect(server.isOnDevice, isFalse);
    });
  });
}
