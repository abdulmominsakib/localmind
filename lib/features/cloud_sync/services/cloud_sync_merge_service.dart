import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../data/models/cloud_sync_models.dart';

class CloudSyncMergeResult {
  const CloudSyncMergeResult(this.snapshot, this.conflictCount);

  final CloudSyncSnapshot snapshot;
  final int conflictCount;
}

class CloudSyncMergeService {
  Future<String> fingerprint(Map<String, dynamic> payload) async {
    final canonical = _canonicalize(payload);
    final hash = await Sha256().hash(utf8.encode(jsonEncode(canonical)));
    return base64UrlEncode(hash.bytes).replaceAll('=', '');
  }

  Future<String> snapshotFingerprint(CloudSyncSnapshot snapshot) => _hashValue({
    'payload': snapshot.payload,
    'tombstones': snapshot.tombstones,
  });

  Future<Map<String, dynamic>> recordHashes(
    Map<String, dynamic> payload,
  ) async {
    final result = <String, dynamic>{};
    final messages = _groupByConversation(payload['messages']);
    for (final collection in const [
      'personas',
      'savedMessages',
      'savedMessageFolders',
      'conversationFolders',
    ]) {
      final hashes = <String, String>{};
      for (final item in _list(payload[collection])) {
        final id = item['id'] as String?;
        if (id != null) hashes[id] = await _hashValue(item);
      }
      result[collection] = hashes;
    }
    final conversationHashes = <String, String>{};
    for (final item in _list(payload['conversations'])) {
      final id = item['id'] as String?;
      if (id != null) {
        conversationHashes[id] = await _hashValue({
          'conversation': item,
          'messages': messages[id] ?? const [],
        });
      }
    }
    result['conversations'] = conversationHashes;
    return result;
  }

  Future<String> _hashValue(Map<String, dynamic> value) async {
    final hash = await Sha256().hash(
      utf8.encode(jsonEncode(_canonicalize(value))),
    );
    return base64UrlEncode(hash.bytes).replaceAll('=', '');
  }

  String? _baseHash(
    Map<String, dynamic> journal,
    String collection,
    String id,
  ) {
    final all = journal['recordHashes'];
    if (all is! Map || all[collection] is! Map) return null;
    return (all[collection] as Map)[id] as String?;
  }

  Map<String, dynamic> _canonicalize(Map<String, dynamic> payload) {
    dynamic normalize(dynamic value) {
      if (value is Map) {
        final keys = value.keys.map((e) => e.toString()).toList()..sort();
        return {for (final key in keys) key: normalize(value[key])};
      }
      if (value is List) {
        final normalized = value.map(normalize).toList();
        if (normalized.every((item) => item is Map && item['id'] is String)) {
          normalized.sort(
            (a, b) => (a['id'] as String).compareTo(b['id'] as String),
          );
        }
        return normalized;
      }
      return value;
    }

    return Map<String, dynamic>.from(normalize(payload) as Map);
  }

  Future<CloudSyncMergeResult> merge({
    required CloudSyncSnapshot local,
    required CloudSyncSnapshot? remote,
    required Map<String, dynamic> journal,
  }) async {
    if (remote == null) return CloudSyncMergeResult(local, 0);

    final remoteSettings = remote.payload['settings'];
    if (remoteSettings is Map &&
        remoteSettings.containsKey('showPromptProcessingIndicator')) {
      remote = CloudSyncSnapshot(
        deviceId: remote.deviceId,
        revision: remote.revision,
        updatedAt: remote.updatedAt,
        payload: {
          ...remote.payload,
          'settings': Map<String, dynamic>.from(remoteSettings)
            ..remove('showPromptProcessingIndicator'),
        },
        tombstones: remote.tombstones,
      );
    }

    final localHash = await fingerprint(local.payload);
    final lastHash = journal['payloadHash'] as String?;
    final lastRemoteRevision = journal['remoteRevision'] as int?;
    final localChanged = lastHash == null || localHash != lastHash;
    final remoteChanged =
        lastRemoteRevision == null ||
        remote.revision != lastRemoteRevision ||
        remote.deviceId != journal['remoteDeviceId'];

    if (!localChanged) return CloudSyncMergeResult(remote, 0);
    if (!remoteChanged) return CloudSyncMergeResult(local, 0);

    final payload = Map<String, dynamic>.from(remote.payload);
    var conflicts = 0;
    payload['settings'] = lastHash == null
        ? remote.payload['settings']
        : local.updatedAt.isAfter(remote.updatedAt)
        ? local.payload['settings']
        : remote.payload['settings'];

    final personas = _mapById(remote.payload['personas']);
    for (final item in _list(local.payload['personas'])) {
      final id = item['id'] as String?;
      if (id == null) continue;
      final existing = personas[id];
      if (existing == null) {
        personas[id] = item;
      } else if (!_same(existing, item)) {
        final base = _baseHash(journal, 'personas', id);
        final localRecordHash = await _hashValue(item);
        final remoteRecordHash = await _hashValue(existing);
        if (base != null && localRecordHash == base) continue;
        if (base != null && remoteRecordHash == base) {
          personas[id] = item;
          continue;
        }
        conflicts++;
        final copy = Map<String, dynamic>.from(item);
        copy['id'] = _conflictId(id, local);
        copy['name'] = '${copy['name'] ?? 'Persona'} (Conflict)';
        personas[copy['id'] as String] = copy;
      }
    }
    payload['personas'] = personas.values.toList();

    final remoteConversations = _mapById(remote.payload['conversations']);
    final localConversations = _mapById(local.payload['conversations']);
    final remoteMessages = _groupByConversation(remote.payload['messages']);
    final localMessages = _groupByConversation(local.payload['messages']);
    final mergedConversations = Map<String, Map<String, dynamic>>.from(
      remoteConversations,
    );
    final mergedMessages = _mapById(remote.payload['messages']);

    for (final entry in localConversations.entries) {
      final remoteConversation = remoteConversations[entry.key];
      if (remoteConversation == null) {
        mergedConversations[entry.key] = entry.value;
        for (final message in localMessages[entry.key] ?? const []) {
          mergedMessages[message['id'] as String] = message;
        }
        continue;
      }
      final localThread = localMessages[entry.key] ?? const [];
      final remoteThread = remoteMessages[entry.key] ?? const [];
      final hasConflict =
          !_same(remoteConversation, entry.value) ||
          !_sameList(remoteThread, localThread);
      if (!hasConflict) continue;

      final base = _baseHash(journal, 'conversations', entry.key);
      final localRecordHash = await _hashValue({
        'conversation': entry.value,
        'messages': localThread,
      });
      final remoteRecordHash = await _hashValue({
        'conversation': remoteConversation,
        'messages': remoteThread,
      });
      if (base != null && localRecordHash == base) continue;
      if (base != null && remoteRecordHash == base) {
        mergedConversations[entry.key] = entry.value;
        for (final message in remoteThread) {
          mergedMessages.remove(message['id']);
        }
        for (final message in localThread) {
          mergedMessages[message['id'] as String] = message;
        }
        continue;
      }

      conflicts++;
      final newConversationId = _conflictId(entry.key, local);
      final idMap = <String, String>{};
      for (final message in localThread) {
        final oldId = message['id'] as String;
        idMap[oldId] = _conflictId(oldId, local);
      }
      final copy = Map<String, dynamic>.from(entry.value)
        ..['id'] = newConversationId
        ..['title'] = '${entry.value['title'] ?? 'Chat'} (Conflict)'
        ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      mergedConversations[newConversationId] = copy;
      for (final message in localThread) {
        final cloned = Map<String, dynamic>.from(message)
          ..['id'] = idMap[message['id']]!
          ..['conversationId'] = newConversationId;
        final parent = message['parentMessageId'] as String?;
        if (parent != null) cloned['parentMessageId'] = idMap[parent];
        final variant = message['variantGroupId'] as String?;
        if (variant != null) {
          cloned['variantGroupId'] = _conflictId(variant, local);
        }
        mergedMessages[cloned['id'] as String] = cloned;
      }
    }
    payload['conversations'] = mergedConversations.values.toList();
    payload['messages'] = mergedMessages.values.toList();

    for (final collection in const [
      'conversationFolders',
      'savedMessageFolders',
      'savedMessages',
    ]) {
      final records = _mapById(remote.payload[collection]);
      for (final item in _list(local.payload[collection])) {
        final id = item['id'] as String?;
        if (id == null) continue;
        final existing = records[id];
        if (existing == null) {
          records[id] = item;
          continue;
        }
        if (_same(existing, item)) continue;
        final base = _baseHash(journal, collection, id);
        if (base != null && await _hashValue(existing) == base) {
          records[id] = item;
        }
      }
      payload[collection] = records.values.toList();
    }

    Future<bool> changedFromBase(
      String collection,
      String id,
      Map<String, dynamic> record,
    ) async {
      final base = _baseHash(journal, collection, id);
      return base != null && await _hashValue(record) != base;
    }

    final mergedPersonaRecords = _mapById(payload['personas']);
    for (final pair in [(local, remote), (remote, local)]) {
      final deletingSnapshot = pair.$1;
      final editedSnapshot = pair.$2;
      final editedPersonas = _mapById(editedSnapshot.payload['personas']);
      for (final id in _tombstoneIds(deletingSnapshot, 'personas')) {
        final edited = editedPersonas[id];
        if (edited == null || !await changedFromBase('personas', id, edited)) {
          continue;
        }
        final copy = Map<String, dynamic>.from(edited);
        copy['id'] = _conflictId(id, editedSnapshot);
        copy['name'] = '${copy['name'] ?? 'Persona'} (Conflict)';
        mergedPersonaRecords[copy['id'] as String] = copy;
        conflicts++;
      }
    }
    payload['personas'] = mergedPersonaRecords.values.toList();

    final conflictConversations = _mapById(payload['conversations']);
    final conflictMessages = _mapById(payload['messages']);
    for (final pair in [(local, remote), (remote, local)]) {
      final deletingSnapshot = pair.$1;
      final editedSnapshot = pair.$2;
      final editedConversations = _mapById(
        editedSnapshot.payload['conversations'],
      );
      final editedMessages = _groupByConversation(
        editedSnapshot.payload['messages'],
      );
      for (final id in _tombstoneIds(deletingSnapshot, 'conversations')) {
        final edited = editedConversations[id];
        if (edited == null) continue;
        final thread = editedMessages[id] ?? const [];
        if (!await changedFromBase('conversations', id, {
          'conversation': edited,
          'messages': thread,
        })) {
          continue;
        }
        _cloneConversationBranch(
          conversation: edited,
          messages: thread,
          source: editedSnapshot,
          conversations: conflictConversations,
          mergedMessages: conflictMessages,
        );
        conflicts++;
      }
    }
    payload['conversations'] = conflictConversations.values.toList();
    payload['messages'] = conflictMessages.values.toList();

    final tombstones = <String, dynamic>{};
    for (final source in [remote.tombstones, local.tombstones]) {
      for (final entry in source.entries) {
        final values =
            (tombstones[entry.key] as List?)?.whereType<String>().toSet() ??
            <String>{};
        if (entry.value is List) {
          values.addAll((entry.value as List).whereType<String>());
        }
        tombstones[entry.key] = values.toList();
      }
    }
    _applyTombstones(payload, tombstones);
    return CloudSyncMergeResult(
      CloudSyncSnapshot(
        deviceId: local.deviceId,
        revision: remote.revision >= local.revision
            ? remote.revision + 1
            : local.revision,
        updatedAt: DateTime.now().toUtc(),
        payload: payload,
        tombstones: tombstones,
      ),
      conflicts,
    );
  }

  String _conflictId(String id, CloudSyncSnapshot local) =>
      '$id-conflict-${local.deviceId.substring(0, 8)}-${local.revision}';

  Set<String> _tombstoneIds(CloudSyncSnapshot snapshot, String collection) =>
      snapshot.tombstones[collection] is List
      ? (snapshot.tombstones[collection] as List).whereType<String>().toSet()
      : <String>{};

  void _cloneConversationBranch({
    required Map<String, dynamic> conversation,
    required List<Map<String, dynamic>> messages,
    required CloudSyncSnapshot source,
    required Map<String, Map<String, dynamic>> conversations,
    required Map<String, Map<String, dynamic>> mergedMessages,
  }) {
    final oldConversationId = conversation['id'] as String;
    final newConversationId = _conflictId(oldConversationId, source);
    final idMap = <String, String>{
      for (final message in messages)
        message['id'] as String: _conflictId(message['id'] as String, source),
    };
    conversations[newConversationId] = Map<String, dynamic>.from(conversation)
      ..['id'] = newConversationId
      ..['title'] = '${conversation['title'] ?? 'Chat'} (Conflict)'
      ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    for (final message in messages) {
      final cloned = Map<String, dynamic>.from(message)
        ..['id'] = idMap[message['id']]!
        ..['conversationId'] = newConversationId;
      final parent = message['parentMessageId'] as String?;
      if (parent != null) cloned['parentMessageId'] = idMap[parent];
      final variant = message['variantGroupId'] as String?;
      if (variant != null) {
        cloned['variantGroupId'] = _conflictId(variant, source);
      }
      mergedMessages[cloned['id'] as String] = cloned;
    }
  }

  List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  Map<String, Map<String, dynamic>> _mapById(dynamic value) => {
    for (final item in _list(value))
      if (item['id'] is String) item['id'] as String: item,
  };

  Map<String, List<Map<String, dynamic>>> _groupByConversation(dynamic value) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final item in _list(value)) {
      final id = item['conversationId'] as String?;
      if (id != null) (result[id] ??= []).add(item);
    }
    for (final items in result.values) {
      items.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    }
    return result;
  }

  bool _same(Map<String, dynamic> a, Map<String, dynamic> b) =>
      jsonEncode(_canonicalize(a)) == jsonEncode(_canonicalize(b));

  bool _sameList(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) =>
      jsonEncode(a.map(_canonicalize).toList()) ==
      jsonEncode(b.map(_canonicalize).toList());

  void _applyTombstones(
    Map<String, dynamic> payload,
    Map<String, dynamic> tombstones,
  ) {
    for (final entry in tombstones.entries) {
      if (payload[entry.key] is! List || entry.value is! List) continue;
      final ids = (entry.value as List).whereType<String>().toSet();
      payload[entry.key] = (payload[entry.key] as List)
          .where((item) => item is! Map || !ids.contains(item['id']))
          .toList();
    }
    final deletedConversations = tombstones['conversations'] is List
        ? (tombstones['conversations'] as List).whereType<String>().toSet()
        : <String>{};
    if (deletedConversations.isNotEmpty && payload['messages'] is List) {
      payload['messages'] = (payload['messages'] as List)
          .where(
            (item) =>
                item is! Map ||
                !deletedConversations.contains(item['conversationId']),
          )
          .toList();
    }
  }
}
