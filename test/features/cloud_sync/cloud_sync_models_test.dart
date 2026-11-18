import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/cloud_sync/data/models/cloud_sync_models.dart';

void main() {
  test('S3 config validates HTTPS and explicit HTTP opt-in', () {
    expect(
      const S3SyncConfig(
        endpoint: 'https://minio.example.com',
        bucket: 'localmind',
      ).validate(),
      isNull,
    );
    expect(
      const S3SyncConfig(
        endpoint: 'http://192.168.1.2:9000',
        bucket: 'localmind',
      ).validate(),
      contains('insecure HTTP'),
    );
    expect(
      const S3SyncConfig(
        endpoint: 'http://192.168.1.2:9000',
        bucket: 'localmind',
        allowInsecureHttp: true,
      ).validate(),
      isNull,
    );
  });

  test('config JSON excludes credentials by construction', () {
    final json = const S3SyncConfig(
      endpoint: 'https://s3.example.com',
      bucket: 'bucket',
      enabled: true,
    ).toJson();
    expect(json, isNot(contains('secretAccessKey')));
    expect(S3SyncConfig.fromJson(json).enabled, isTrue);
  });

  Map<String, dynamic> validSnapshot() => {
    'schema': 1,
    'deviceId': 'device-12345678',
    'revision': 1,
    'updatedAt': DateTime.utc(2026, 7, 10).toIso8601String(),
    'tombstones': <String, dynamic>{},
    'payload': {
      'version': 1,
      'type': 'cloudSync',
      'settings': <String, dynamic>{'fontSize': 16.0},
      'conversations': [
        {
          'id': 'conversation',
          'isTemporary': false,
          'createdAt': DateTime.utc(2026, 7, 10).toIso8601String(),
          'updatedAt': DateTime.utc(2026, 7, 10).toIso8601String(),
        },
      ],
      'messages': [
        {
          'id': 'message',
          'conversationId': 'conversation',
          'createdAt': DateTime.utc(2026, 7, 10).toIso8601String(),
          'attachmentPaths': ['cloud://identifier/ZmlsZS50eHQ'],
        },
      ],
      'personas': <dynamic>[],
      'savedMessages': <dynamic>[],
      'savedMessageFolders': <dynamic>[],
      'conversationFolders': <dynamic>[],
    },
  };

  test('snapshot validation rejects incomplete or out-of-scope data', () {
    expect(CloudSyncSnapshot.fromJson(validSnapshot()).revision, 1);

    final missingCollection = validSnapshot();
    (missingCollection['payload'] as Map).remove('messages');
    expect(
      () => CloudSyncSnapshot.fromJson(missingCollection),
      throwsFormatException,
    );

    final secretSetting = validSnapshot();
    ((secretSetting['payload'] as Map)['settings'] as Map)['huggingFaceToken'] =
        'secret';
    expect(
      () => CloudSyncSnapshot.fromJson(secretSetting),
      throwsFormatException,
    );

    final localPath = validSnapshot();
    (((localPath['payload'] as Map)['messages'] as List).single
        as Map)['attachmentPaths'] = [
      '/private/file.txt',
    ];
    expect(() => CloudSyncSnapshot.fromJson(localPath), throwsFormatException);
  });

  test('snapshot validates optional prompts processed counters', () {
    final snapshot = validSnapshot();
    final conversation =
        ((snapshot['payload'] as Map)['conversations'] as List).single as Map;
    expect(CloudSyncSnapshot.fromJson(snapshot).revision, 1);

    for (final value in [0, 12, 0x7fffffffffffffff]) {
      conversation['promptsProcessed'] = value;
      expect(CloudSyncSnapshot.fromJson(snapshot).revision, 1);
    }

    for (final value in ['12', 12.5, -1]) {
      conversation['promptsProcessed'] = value;
      expect(() => CloudSyncSnapshot.fromJson(snapshot), throwsFormatException);
    }
  });
}
