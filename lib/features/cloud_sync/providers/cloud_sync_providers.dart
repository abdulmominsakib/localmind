import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/services/data_backup_service.dart';
import '../../conversations/providers/conversation_providers.dart';
import '../../personas/providers/personas_providers.dart';
import '../../saved_messages/providers/saved_message_providers.dart';
import '../../settings/data/models/app_settings.dart';
import '../data/models/cloud_sync_models.dart';
import '../data/repositories/cloud_sync_local_repository.dart';
import '../data/repositories/s3_cloud_sync_repository.dart';
import '../services/cloud_sync_crypto_service.dart';
import '../services/cloud_sync_merge_service.dart';
import '../services/cloud_attachment_reference_resolver.dart';

final cloudSyncLocalRepositoryProvider = Provider<CloudSyncLocalRepository>(
  (ref) => CloudSyncLocalRepository(ref.watch(sharedPreferencesProvider)),
);

final cloudSyncCryptoServiceProvider = Provider<CloudSyncCryptoService>(
  (ref) => CloudSyncCryptoService(),
);

final cloudSyncMergeServiceProvider = Provider<CloudSyncMergeService>(
  (ref) => CloudSyncMergeService(),
);

final cloudAttachmentReferenceResolverProvider =
    Provider<CloudAttachmentReferenceResolver>(
      (ref) => const CloudAttachmentReferenceResolver(),
    );

final cloudSyncControllerProvider =
    NotifierProvider<CloudSyncController, CloudSyncStatus>(
      CloudSyncController.new,
    );

class CloudSyncController extends Notifier<CloudSyncStatus> {
  Timer? _debounce;
  Timer? _retryTimer;
  bool _running = false;
  bool _pending = false;
  bool _applyingRemote = false;
  int _retryIndex = 0;
  int _operationGeneration = 0;

  bool get isApplyingRemote => _applyingRemote;

  CloudSyncLocalRepository get _local =>
      ref.read(cloudSyncLocalRepositoryProvider);
  CloudSyncCryptoService get _crypto =>
      ref.read(cloudSyncCryptoServiceProvider);
  CloudSyncMergeService get _merge => ref.read(cloudSyncMergeServiceProvider);
  CloudAttachmentReferenceResolver get _attachmentReferenceResolver =>
      ref.read(cloudAttachmentReferenceResolverProvider);

  @override
  CloudSyncStatus build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _retryTimer?.cancel();
    });
    final config = _local.loadConfig();
    return CloudSyncStatus(
      phase: config?.enabled == true
          ? CloudSyncPhase.ready
          : CloudSyncPhase.disabled,
      lastSyncedAt: _local.loadLastSync(),
    );
  }

  S3SyncConfig? get config => _local.loadConfig();

  Future<void> testConnection(
    S3SyncConfig config,
    CloudSyncCredentials credentials,
  ) => S3CloudSyncRepository(
    config: config,
    credentials: credentials,
  ).testConnection();

  Future<void> configure({
    required S3SyncConfig config,
    required CloudSyncCredentials credentials,
    required String passphrase,
  }) async {
    final validation = config.validate();
    if (validation != null) {
      throw CloudSyncFailure(CloudSyncFailureKind.validation, validation);
    }
    final enabledConfig = config.copyWith(enabled: true);
    final remoteRepository = S3CloudSyncRepository(
      config: enabledConfig,
      credentials: credentials,
    );
    state = state.copyWith(
      phase: CloudSyncPhase.syncing,
      message: 'Testing S3 connection…',
    );
    try {
      await remoteRepository.testConnection();
      final remote = await remoteRepository.readState();
      final salt = remote == null
          ? _crypto.newSalt()
          : _crypto.extractSalt(remote.bytes);
      final masterKey = await _crypto.deriveMasterKey(passphrase, salt);
      if (remote != null) {
        await _crypto.decryptState(remote.bytes, masterKey);
      }
      await _local.saveConfig(enabledConfig);
      await _local.saveSecrets(
        credentials: credentials,
        masterKey: masterKey,
        salt: salt,
      );
      state = state.copyWith(
        phase: CloudSyncPhase.ready,
        message: 'Cloud sync enabled.',
      );
      await syncNow(rethrowErrors: true);
    } catch (error) {
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        message: error.toString(),
      );
      rethrow;
    }
  }

  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {
    if (_applyingRemote || config?.enabled != true) return;
    _debounce?.cancel();
    _debounce = Timer(delay, () => unawaited(syncNow()));
  }

  Future<void> syncNow({bool rethrowErrors = false}) async {
    if (_running || !ref.mounted) {
      _pending = true;
      return;
    }
    final config = _local.loadConfig();
    if (config == null || !config.enabled) return;
    final credentials = await _local.loadCredentials();
    if (!ref.mounted) return;
    final masterKey = await _local.loadMasterKey();
    if (!ref.mounted) return;
    final salt = await _local.loadSalt();
    if (!ref.mounted) return;
    if (credentials == null || masterKey == null || salt == null) {
      if (ref.mounted) {
        state = state.copyWith(
          phase: CloudSyncPhase.locked,
          message: 'Cloud sync must be unlocked again on this device.',
        );
      }
      return;
    }

    final generation = _operationGeneration;
    _running = true;
    state = state.copyWith(
      phase: CloudSyncPhase.syncing,
      message: 'Syncing encrypted data…',
      warnings: const [],
    );
    try {
      final warnings = await _performSync(
        config,
        credentials,
        masterKey,
        salt,
        generation,
      );
      if (!ref.mounted) return;
      _ensureActive(generation);
      _retryIndex = 0;
      _retryTimer?.cancel();
      state = CloudSyncStatus(
        phase: CloudSyncPhase.synced,
        lastSyncedAt: DateTime.now(),
        message: 'Encrypted sync is up to date.',
        conflictCount: state.conflictCount,
        warnings: warnings,
      );
    } catch (error) {
      if (!ref.mounted) return;
      if (error is CloudSyncFailure &&
          error.kind == CloudSyncFailureKind.cancelled) {
        return;
      }
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        message: error.toString(),
      );
      _scheduleRetry();
      if (rethrowErrors) rethrow;
    } finally {
      _running = false;
      if (_pending && ref.mounted) {
        _pending = false;
        scheduleSync(delay: Duration.zero);
      }
    }
  }

  void _scheduleRetry() {
    const delays = [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 2),
    ];
    if (_retryIndex >= delays.length || config?.enabled != true) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(delays[_retryIndex++], () => unawaited(syncNow()));
  }

  Future<List<String>> _performSync(
    S3SyncConfig config,
    CloudSyncCredentials credentials,
    List<int> masterKey,
    List<int> salt,
    int generation,
  ) async {
    final repository = S3CloudSyncRepository(
      config: config,
      credentials: credentials,
    );
    final journal = await _local.loadJournal();
    final payload = DataBackupService().exportCloudSync(
      ref.read(databaseProvider).store,
      ref.read(settingsProvider).toJson(),
    );
    final warnings = <String>[];
    await _prepareAttachments(
      payload,
      repository,
      masterKey,
      salt,
      warnings,
      journal,
      generation,
    );
    _ensureActive(generation);
    final deviceId = _local.getOrCreateDeviceId();
    final revision = (journal['localRevision'] as int? ?? 0) + 1;
    final local = CloudSyncSnapshot(
      deviceId: deviceId,
      revision: revision,
      updatedAt: DateTime.now().toUtc(),
      payload: payload,
      tombstones: _buildTombstones(payload, journal),
    );

    for (var attempt = 0; attempt < 3; attempt++) {
      _ensureActive(generation);
      final remoteObject = await repository.readState();
      _ensureActive(generation);
      if (remoteObject != null && remoteObject.etag == null) {
        throw const CloudSyncFailure(
          CloudSyncFailureKind.incompatibleServer,
          'The S3 state object is missing the ETag required for safe sync.',
        );
      }
      CloudSyncSnapshot? remote;
      if (remoteObject != null) {
        final clear = await _crypto.decryptState(remoteObject.bytes, masterKey);
        remote = CloudSyncSnapshot.fromJson(
          jsonDecode(utf8.decode(clear)) as Map<String, dynamic>,
        );
      }
      final result = await _merge.merge(
        local: local,
        remote: remote,
        journal: journal,
      );
      try {
        final remoteHash = remote == null
            ? null
            : await _merge.snapshotFingerprint(remote);
        final mergedStateHash = await _merge.snapshotFingerprint(
          result.snapshot,
        );
        final mergedPayloadHash = await _merge.fingerprint(
          result.snapshot.payload,
        );
        var etag = remoteObject?.etag;
        if (remoteHash != mergedStateHash || remote == null) {
          _ensureActive(generation);
          final encrypted = await _crypto.encryptState(
            utf8.encode(result.snapshot.encode()),
            masterKey: masterKey,
            salt: salt,
          );
          etag = await repository.writeState(
            encrypted,
            expectedEtag: remoteObject?.etag,
            createOnly: remoteObject == null,
          );
          _ensureActive(generation);
        }
        _ensureActive(generation);
        await _applySnapshot(
          result.snapshot,
          repository,
          masterKey,
          warnings,
          generation,
        );
        _ensureActive(generation);
        final now = DateTime.now().toUtc();
        await _local.saveJournal({
          'localRevision': result.snapshot.revision,
          'remoteRevision': result.snapshot.revision,
          'remoteDeviceId': result.snapshot.deviceId,
          'payloadHash': mergedPayloadHash,
          'etag': etag,
          'lastSyncedAt': now.toIso8601String(),
          'ids': _snapshotIds(result.snapshot.payload),
          'recordHashes': await _merge.recordHashes(result.snapshot.payload),
          'tombstones': result.snapshot.tombstones,
          'attachmentRefs': _attachmentRefs(result.snapshot.payload),
        });
        state = state.copyWith(conflictCount: result.conflictCount);
        return warnings;
      } on CloudSyncFailure catch (error) {
        if (error.kind != CloudSyncFailureKind.conflict || attempt == 2) {
          rethrow;
        }
      }
    }
    return warnings;
  }

  Map<String, dynamic> _buildTombstones(
    Map<String, dynamic> payload,
    Map<String, dynamic> journal,
  ) {
    final previous = journal['ids'] is Map
        ? Map<String, dynamic>.from(journal['ids'] as Map)
        : const <String, dynamic>{};
    final current = _snapshotIds(payload);
    final result = <String, dynamic>{
      if (journal['tombstones'] is Map)
        for (final entry in (journal['tombstones'] as Map).entries)
          entry.key.toString(): entry.value is List
              ? List<String>.from((entry.value as List).whereType<String>())
              : <String>[],
    };
    for (final collection in current.keys) {
      final oldIds = previous[collection] is List
          ? (previous[collection] as List).whereType<String>().toSet()
          : <String>{};
      final currentIds = (current[collection] as List)
          .whereType<String>()
          .toSet();
      final deleted = oldIds.difference(currentIds);
      if (deleted.isNotEmpty) {
        final cumulative =
            (result[collection] as List?)?.whereType<String>().toSet() ??
            <String>{};
        cumulative.addAll(deleted);
        result[collection] = cumulative.toList();
      }
    }
    return result;
  }

  Map<String, dynamic> _snapshotIds(Map<String, dynamic> payload) => {
    for (final collection in const [
      'conversations',
      'messages',
      'personas',
      'savedMessages',
      'savedMessageFolders',
      'conversationFolders',
    ])
      collection: payload[collection] is List
          ? (payload[collection] as List)
                .whereType<Map>()
                .map((item) => item['id'])
                .whereType<String>()
                .toList()
          : <String>[],
  };

  Map<String, dynamic> _attachmentRefs(Map<String, dynamic> payload) => {
    for (final message in (payload['messages'] as List).whereType<Map>())
      if (message['id'] is String && message['attachmentPaths'] is List)
        message['id'] as String: (message['attachmentPaths'] as List)
            .whereType<String>()
            .where((path) => path.startsWith('cloud://'))
            .toList(),
  };

  void _ensureActive(int generation) {
    if (generation != _operationGeneration) {
      throw const CloudSyncFailure(
        CloudSyncFailureKind.cancelled,
        'Cloud sync was cancelled.',
      );
    }
  }

  Future<void> _prepareAttachments(
    Map<String, dynamic> payload,
    S3CloudSyncRepository repository,
    List<int> masterKey,
    List<int> salt,
    List<String> warnings,
    Map<String, dynamic> journal,
    int generation,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final attachmentsDir = p.normalize(p.join(appDir.path, 'attachments'));
    final messages = payload['messages'];
    if (messages is! List) return;
    for (final raw in messages.whereType<Map>()) {
      _ensureActive(generation);
      final paths = raw['attachmentPaths'];
      if (paths is! List) continue;
      final messageId = raw['id'] as String?;
      final previousRefs =
          messageId != null &&
              journal['attachmentRefs'] is Map &&
              (journal['attachmentRefs'] as Map)[messageId] is List
          ? ((journal['attachmentRefs'] as Map)[messageId] as List)
                .whereType<String>()
                .toList()
          : <String>[];
      final refs = <String>[];
      for (var index = 0; index < paths.length; index++) {
        final value = paths[index];
        if (value is! String) continue;
        if (value.startsWith('cloud://')) {
          refs.add(value);
          continue;
        }
        final normalized = p.normalize(value);
        if (!p.isWithin(attachmentsDir, normalized)) {
          _preserveUnavailableAttachment(
            refs,
            previousRefs,
            value,
            index,
            warnings,
          );
          continue;
        }
        final file = File(normalized);
        if (!await file.exists()) {
          _preserveUnavailableAttachment(
            refs,
            previousRefs,
            value,
            index,
            warnings,
          );
          continue;
        }
        final clear = await file.readAsBytes();
        final identifier = await _crypto.attachmentIdentifier(clear, masterKey);
        final key = repository.attachmentKey(identifier);
        if (!await repository.objectExists(key)) {
          _ensureActive(generation);
          final encrypted = await _crypto.encryptAttachment(
            clear,
            masterKey: masterKey,
            salt: salt,
          );
          try {
            await repository.writeObject(key, encrypted, createOnly: true);
          } on CloudSyncFailure catch (error) {
            if (error.kind != CloudSyncFailureKind.conflict) rethrow;
          }
        }
        final name = base64UrlEncode(
          utf8.encode(p.basename(normalized)),
        ).replaceAll('=', '');
        refs.add('cloud://$identifier/$name');
      }
      raw['attachmentPaths'] = refs;
    }
  }

  void _preserveUnavailableAttachment(
    List<String> refs,
    List<String> previousRefs,
    String localPath,
    int index,
    List<String> warnings,
  ) {
    final previous = _attachmentReferenceResolver.findPreviousReference(
      previousReferences: previousRefs,
      localPath: localPath,
      index: index,
    );
    if (previous == null) {
      throw const CloudSyncFailure(
        CloudSyncFailureKind.corruptedData,
        'A local attachment is unavailable and has no prior cloud reference.',
      );
    }
    refs.add(previous);
    warnings.add('Preserved an unavailable attachment from cloud history.');
  }

  Future<void> _applySnapshot(
    CloudSyncSnapshot snapshot,
    S3CloudSyncRepository repository,
    List<int> masterKey,
    List<String> warnings,
    int generation,
  ) async {
    final payload = Map<String, dynamic>.from(snapshot.payload);
    await _materializeAttachments(payload, repository, masterKey);
    _ensureActive(generation);
    AppSettings? importedSettings;
    final remoteSettings = payload['settings'];
    if (remoteSettings is Map) {
      final current = ref.read(settingsProvider);
      final merged = <String, dynamic>{
        ...current.toMap(),
        ...Map<String, dynamic>.from(remoteSettings),
        'huggingFaceToken': current.huggingFaceToken,
        'defaultServerId': current.defaultServerId,
        'hasCompletedOnboarding': current.hasCompletedOnboarding,
        'hasAskedForNotifications': current.hasAskedForNotifications,
      };
      try {
        importedSettings = AppSettings.fromMap(merged);
      } catch (_) {
        throw const CloudSyncFailure(
          CloudSyncFailureKind.corruptedData,
          'The encrypted cloud settings are invalid.',
        );
      }
    }
    _applyingRemote = true;
    try {
      await DataBackupService().importCloudSync(
        ref.read(databaseProvider).store,
        payload,
      );
      _ensureActive(generation);
      // Defer both the settings update and the async provider invalidations
      // until after the current build frame. If a subscriber widget (for
      // example SettingsViews) is rebuilt because settings changed, watching
      // the invalidated async providers inside the build can flush them and
      // cause Riverpod to call setState on UncontrolledProviderScope during
      // build, which throws.
      //
      // By moving the settings update into the post-frame callback alongside
      // the invalidations, every dependent rebuild happens on a subsequent
      // frame where the providers are already in their AsyncLoading state,
      // so reads no longer trigger an invalidation mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!ref.mounted) return;
        if (importedSettings != null) {
          await ref
              .read(settingsProvider.notifier)
              .updateSettings(importedSettings);
          if (!ref.mounted) return;
        }
        ref.invalidate(conversationsProvider);
        ref.invalidate(personasNotifierProvider);
        ref.invalidate(savedMessagesProvider);
        ref.invalidate(savedMessageFoldersProvider);
      });
    } finally {
      _applyingRemote = false;
    }
  }

  Future<void> _materializeAttachments(
    Map<String, dynamic> payload,
    S3CloudSyncRepository repository,
    List<int> masterKey,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'attachments', 'cloud-sync'));
    await dir.create(recursive: true);
    final messages = payload['messages'];
    if (messages is! List) return;
    for (final raw in messages.whereType<Map>()) {
      final paths = raw['attachmentPaths'];
      if (paths is! List) continue;
      final localPaths = <String>[];
      for (final value in paths.whereType<String>()) {
        final match = RegExp(
          r'^cloud://([A-Za-z0-9_-]+)/([A-Za-z0-9_-]+)$',
        ).firstMatch(value);
        if (match == null) continue;
        final identifier = match.group(1)!;
        final encodedName = match.group(2)!;
        final padded = encodedName.padRight(
          encodedName.length + ((4 - encodedName.length % 4) % 4),
          '=',
        );
        final decodedName = utf8.decode(base64Url.decode(padded));
        final safeName = p.basename(decodedName);
        final destination = File(p.join(dir.path, '$identifier-$safeName'));
        if (!await destination.exists()) {
          final remote = await repository.readObject(
            repository.attachmentKey(identifier),
          );
          if (remote == null) {
            throw const CloudSyncFailure(
              CloudSyncFailureKind.corruptedData,
              'A required encrypted attachment is missing from S3.',
            );
          }
          final clear = await _crypto.decryptAttachment(
            remote.bytes,
            masterKey,
          );
          await destination.writeAsBytes(clear, flush: true);
        }
        localPaths.add(destination.path);
      }
      raw['attachmentPaths'] = localPaths;
    }
  }

  Future<void> disconnect() async {
    _operationGeneration++;
    _debounce?.cancel();
    _retryTimer?.cancel();
    await _local.disconnect();
    state = const CloudSyncStatus();
  }
}
