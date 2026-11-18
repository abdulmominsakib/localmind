import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/cloud_sync/data/models/cloud_sync_models.dart';
import 'package:localmind/features/cloud_sync/services/cloud_sync_merge_service.dart';

void main() {
  final service = CloudSyncMergeService();

  CloudSyncSnapshot snapshot(
    String device,
    int revision,
    Map<String, dynamic> payload,
  ) => CloudSyncSnapshot(
    deviceId: device,
    revision: revision,
    updatedAt: DateTime.utc(2026, 7, 10, revision),
    payload: {
      'settings': <String, dynamic>{},
      'personas': <dynamic>[],
      'conversations': <dynamic>[],
      'messages': <dynamic>[],
      'savedMessages': <dynamic>[],
      'savedMessageFolders': <dynamic>[],
      'conversationFolders': <dynamic>[],
      ...payload,
    },
  );

  test('unions independent records', () async {
    final remote = snapshot('remote-device', 1, {
      'personas': [
        {'id': 'remote', 'name': 'Remote'},
      ],
    });
    final local = snapshot('local-device', 2, {
      'personas': [
        {'id': 'local', 'name': 'Local'},
      ],
    });

    final result = await service.merge(
      local: local,
      remote: remote,
      journal: const {},
    );

    expect(
      (result.snapshot.payload['personas'] as List)
          .map((item) => item['id'])
          .toSet(),
      {'remote', 'local'},
    );
    expect(result.conflictCount, 0);
  });

  test(
    'removes the local indicator preference from a legacy snapshot',
    () async {
      final remote = snapshot('remote-device', 3, {
        'settings': {'fontSize': 22.0, 'showPromptProcessingIndicator': true},
      });
      final local = snapshot('local-device', 1, {
        'settings': {'fontSize': 22.0},
      });

      final result = await service.merge(
        local: local,
        remote: remote,
        journal: {'payloadHash': await service.fingerprint(local.payload)},
      );

      expect(result.snapshot.payload['settings'], {'fontSize': 22.0});
      expect(
        await service.snapshotFingerprint(result.snapshot),
        isNot(await service.snapshotFingerprint(remote)),
      );
    },
  );

  test(
    'uses remote settings when linking a device for the first time',
    () async {
      final remote = snapshot('remote-device', 3, {
        'settings': {'fontSize': 22.0},
      });
      final local = snapshot('local-device', 1, {
        'settings': {'fontSize': 16.0},
      });

      final result = await service.merge(
        local: local,
        remote: remote,
        journal: const {},
      );

      expect(result.snapshot.payload['settings'], {'fontSize': 22.0});
    },
  );

  test('preserves conflicting persona and conversation branches', () async {
    final remote = snapshot('remote-device', 1, {
      'personas': [
        {'id': 'p1', 'name': 'Remote'},
      ],
      'conversations': [
        {'id': 'c1', 'title': 'Remote'},
      ],
      'messages': [
        {'id': 'm1', 'conversationId': 'c1', 'content': 'Remote'},
      ],
    });
    final local = snapshot('local-device', 2, {
      'personas': [
        {'id': 'p1', 'name': 'Local'},
      ],
      'conversations': [
        {'id': 'c1', 'title': 'Local'},
      ],
      'messages': [
        {'id': 'm1', 'conversationId': 'c1', 'content': 'Local'},
      ],
    });

    final result = await service.merge(
      local: local,
      remote: remote,
      journal: const {},
    );

    expect(result.conflictCount, 2);
    expect(result.snapshot.payload['personas'], hasLength(2));
    expect(result.snapshot.payload['conversations'], hasLength(2));
    expect(result.snapshot.payload['messages'], hasLength(2));
  });

  test(
    'merges edits to different conversations without false conflicts',
    () async {
      final base = snapshot('base-device', 1, {
        'conversations': [
          {'id': 'c1', 'title': 'One'},
          {'id': 'c2', 'title': 'Two'},
        ],
        'messages': [
          {'id': 'm1', 'conversationId': 'c1', 'content': 'One'},
          {'id': 'm2', 'conversationId': 'c2', 'content': 'Two'},
        ],
      });
      final remote = snapshot('remote-device', 2, {
        'conversations': [
          {'id': 'c1', 'title': 'Remote edit'},
          {'id': 'c2', 'title': 'Two'},
        ],
        'messages': base.payload['messages'],
      });
      final local = snapshot('local-device', 2, {
        'conversations': [
          {'id': 'c1', 'title': 'One'},
          {'id': 'c2', 'title': 'Local edit'},
        ],
        'messages': base.payload['messages'],
      });
      final journal = {
        'payloadHash': await service.fingerprint(base.payload),
        'remoteRevision': base.revision,
        'remoteDeviceId': base.deviceId,
        'recordHashes': await service.recordHashes(base.payload),
      };

      final result = await service.merge(
        local: local,
        remote: remote,
        journal: journal,
      );

      final conversations = {
        for (final item in result.snapshot.payload['conversations'] as List)
          item['id']: item['title'],
      };
      expect(conversations, {'c1': 'Remote edit', 'c2': 'Local edit'});
      expect(result.conflictCount, 0);
    },
  );

  test('applies tombstones after merging', () async {
    final remote = snapshot('remote-device', 1, {
      'personas': [
        {'id': 'deleted', 'name': 'Delete me'},
      ],
    });
    final local = CloudSyncSnapshot(
      deviceId: 'local-device',
      revision: 2,
      updatedAt: DateTime.utc(2026, 7, 10, 2),
      payload: snapshot('local-device', 2, {}).payload,
      tombstones: const {
        'personas': ['deleted'],
      },
    );

    final result = await service.merge(
      local: local,
      remote: remote,
      journal: const {},
    );
    expect(result.snapshot.payload['personas'], isEmpty);
  });

  test(
    'preserves an edit that races with a deletion as a conflict copy',
    () async {
      final base = snapshot('base-device', 1, {
        'personas': [
          {'id': 'p1', 'name': 'Original'},
        ],
        'conversations': [
          {'id': 'c1', 'title': 'Original'},
        ],
        'messages': [
          {'id': 'm1', 'conversationId': 'c1', 'content': 'Original'},
        ],
      });
      final remote = snapshot('remote-device', 2, {
        'personas': [
          {'id': 'p1', 'name': 'Edited'},
        ],
        'conversations': [
          {'id': 'c1', 'title': 'Edited'},
        ],
        'messages': [
          {'id': 'm1', 'conversationId': 'c1', 'content': 'Edited'},
        ],
      });
      final local = CloudSyncSnapshot(
        deviceId: 'local-device',
        revision: 2,
        updatedAt: DateTime.utc(2026, 7, 10, 2),
        payload: snapshot('local-device', 2, {}).payload,
        tombstones: const {
          'personas': ['p1'],
          'conversations': ['c1'],
        },
      );
      final journal = {
        'payloadHash': await service.fingerprint(base.payload),
        'remoteRevision': base.revision,
        'remoteDeviceId': base.deviceId,
        'recordHashes': await service.recordHashes(base.payload),
      };

      final result = await service.merge(
        local: local,
        remote: remote,
        journal: journal,
      );

      final personas = result.snapshot.payload['personas'] as List;
      final conversations = result.snapshot.payload['conversations'] as List;
      final messages = result.snapshot.payload['messages'] as List;
      expect(personas, hasLength(1));
      expect(personas.single['id'], startsWith('p1-conflict-'));
      expect(conversations, hasLength(1));
      expect(conversations.single['id'], startsWith('c1-conflict-'));
      expect(messages.single['conversationId'], conversations.single['id']);
      expect(result.conflictCount, 2);
    },
  );

  test('retains cumulative tombstones on a local-only fast path', () async {
    final remote = CloudSyncSnapshot(
      deviceId: 'remote-device',
      revision: 4,
      updatedAt: DateTime.utc(2026, 7, 10),
      payload: snapshot('remote-device', 4, {
        'settings': {'fontSize': 16.0},
      }).payload,
      tombstones: const {
        'personas': ['deleted-persona'],
      },
    );
    final local = CloudSyncSnapshot(
      deviceId: 'local-device',
      revision: 5,
      updatedAt: DateTime.utc(2026, 7, 10, 1),
      payload: snapshot('local-device', 5, {
        'settings': {'fontSize': 18.0},
      }).payload,
      tombstones: remote.tombstones,
    );
    final journal = {
      'payloadHash': await service.fingerprint(remote.payload),
      'remoteRevision': remote.revision,
      'remoteDeviceId': remote.deviceId,
    };

    final result = await service.merge(
      local: local,
      remote: remote,
      journal: journal,
    );

    expect(result.snapshot.tombstones, remote.tombstones);
    final withoutTombstones = CloudSyncSnapshot(
      deviceId: result.snapshot.deviceId,
      revision: result.snapshot.revision,
      updatedAt: result.snapshot.updatedAt,
      payload: result.snapshot.payload,
    );
    expect(
      await service.snapshotFingerprint(result.snapshot),
      isNot(await service.snapshotFingerprint(withoutTombstones)),
    );
  });
}
