import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/storage/entities.dart';
import 'package:localmind/core/storage/objectbox_store.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/objectbox.g.dart';

void main() {
  late _FakeServerBox fakeServerBox;
  late _FakeObjectBoxStore fakeStore;

  setUp(() {
    fakeServerBox = _FakeServerBox();
    fakeStore = _FakeObjectBoxStore(fakeServerBox);
  });

  test(
    'ServersNotifier._loadAll deduplicates servers with duplicate id and heals typeIndex in ObjectBox',
    () async {
      final now = DateTime(2026, 1, 1);

      // Seed duplicate on-device entities:
      // Entity 1: corrupted typeIndex 4 (shifted from onDevice to openRouter)
      final corruptedEntity = ServerEntity(
        internalId: 1,
        id: 'on-device',
        name: 'On-Device',
        typeIndex: 4,
        host: '',
        port: 0,
        createdAt: now,
        lastConnectedAt: now,
        statusIndex: 1,
      );
      // Entity 2: duplicate on-device inserted by bootstrap with typeIndex 5
      final duplicateEntity = ServerEntity(
        internalId: 2,
        id: 'on-device',
        name: 'On-Device',
        typeIndex: 5,
        host: '',
        port: 0,
        createdAt: now,
        lastConnectedAt: now,
        statusIndex: 1,
      );

      fakeServerBox.put(corruptedEntity);
      fakeServerBox.put(duplicateEntity);
      expect(fakeServerBox.count(), 2);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(fakeStore)],
      );
      addTearDown(container.dispose);

      final servers = await container.read(serversProvider.future);

      // Exactly one on-device server should be returned
      expect(servers.length, 1);
      final onDevice = servers.first;
      expect(onDevice.id, 'on-device');
      expect(onDevice.type, ServerType.onDevice);
      expect(onDevice.isOnDevice, isTrue);

      // The database itself should now only have 1 entity, with healed typeIndex 5
      expect(fakeServerBox.count(), 1);
      final persisted = fakeServerBox.getAll().first;
      expect(persisted.id, 'on-device');
      expect(persisted.typeIndex, ServerType.onDevice.index);
    },
  );

  test(
    'ServersNotifier._loadAll heals shifted typeIndex 4 when single on-device record exists',
    () async {
      final now = DateTime(2026, 1, 1);
      final corruptedEntity = ServerEntity(
        internalId: 1,
        id: 'on-device',
        name: 'On-Device',
        typeIndex: 4, // Was onDevice, shifted to openRouter
        host: '',
        port: 0,
        createdAt: now,
        lastConnectedAt: now,
        statusIndex: 1,
      );

      fakeServerBox.put(corruptedEntity);

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(fakeStore)],
      );
      addTearDown(container.dispose);

      final servers = await container.read(serversProvider.future);

      expect(servers.length, 1);
      expect(servers.first.type, ServerType.onDevice);
      expect(fakeServerBox.getAll().first.typeIndex, ServerType.onDevice.index);
    },
  );

  test(
    'ServersNotifier.addServer is idempotent and does not create duplicates for existing id',
    () async {
      final now = DateTime(2026, 1, 1);
      final server = Server(
        id: 'on-device',
        name: 'On-Device',
        type: ServerType.onDevice,
        host: '',
        port: 0,
        createdAt: now,
        lastConnectedAt: now,
        status: ConnectionStatus.connected,
      );

      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(fakeStore)],
      );
      addTearDown(container.dispose);

      // Call addServer twice
      await container.read(serversProvider.notifier).addServer(server);
      await container.read(serversProvider.notifier).addServer(server);

      final servers = await container.read(serversProvider.future);
      expect(servers.length, 1);
      expect(fakeServerBox.count(), 1);
    },
  );
}

class _FakeServerBox extends Fake implements Box<ServerEntity> {
  final List<ServerEntity> _entities;
  int _nextId = 1;

  _FakeServerBox([List<ServerEntity>? initial])
    : _entities = List<ServerEntity>.from(initial ?? []) {
    for (final e in _entities) {
      if (e.internalId == 0) {
        e.internalId = _nextId++;
      } else if (e.internalId >= _nextId) {
        _nextId = e.internalId + 1;
      }
    }
  }

  @override
  List<ServerEntity> getAll() => List<ServerEntity>.from(_entities);

  @override
  int put(ServerEntity entity, {PutMode mode = PutMode.put}) {
    if (entity.internalId == 0) {
      entity.internalId = _nextId++;
      _entities.add(entity);
    } else {
      final idx = _entities.indexWhere(
        (e) => e.internalId == entity.internalId,
      );
      if (idx >= 0) {
        _entities[idx] = entity;
      } else {
        _entities.add(entity);
      }
    }
    return entity.internalId;
  }

  @override
  bool remove(int id) {
    final before = _entities.length;
    _entities.removeWhere((e) => e.internalId == id);
    return _entities.length < before;
  }

  @override
  int count({int limit = 0}) => _entities.length;
}

class _FakeObjectBoxStore extends Fake implements ObjectBoxStore {
  _FakeObjectBoxStore(this.serverBox);

  @override
  final Box<ServerEntity> serverBox;
}
