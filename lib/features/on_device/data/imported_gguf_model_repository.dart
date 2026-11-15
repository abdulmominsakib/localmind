import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'dart:async';

// The engine field is wired through the named constructor parameter.
// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logger/app_logger.dart';
import 'download_engine.dart';
import 'os_download_bridge.dart';
import 'download_task.dart';
import 'models/on_device_model.dart';

class ImportedGgufModelMetadata {
  static const _unset = Object();

  final String id;
  final String name;
  final String filePath;
  final String? projectorPath;
  final int fileSizeBytes;
  final DateTime importedAt;
  final OnDeviceImportedSource source;
  final String? sourceUrl;
  final bool? reasoningEnabled;

  const ImportedGgufModelMetadata({
    required this.id,
    required this.name,
    required this.filePath,
    this.projectorPath,
    required this.fileSizeBytes,
    required this.importedAt,
    required this.source,
    this.sourceUrl,
    this.reasoningEnabled,
  });

  String get fileName => p.basename(filePath);
  String? get projectorFileName =>
      projectorPath != null && projectorPath!.isNotEmpty
      ? p.basename(projectorPath!)
      : null;

  String get sourceLabel {
    switch (source) {
      case OnDeviceImportedSource.localFile:
        return 'Local file';
      case OnDeviceImportedSource.huggingFace:
        return 'Hugging Face';
    }
  }

  int get estimatedMinRamMb {
    final fileSizeMb = fileSizeBytes / (1024 * 1024);
    return max(2048, (fileSizeMb * 1.3).ceil());
  }

  ImportedGgufModelMetadata copyWith({
    String? id,
    String? name,
    String? filePath,
    Object? projectorPath = _unset,
    int? fileSizeBytes,
    DateTime? importedAt,
    OnDeviceImportedSource? source,
    String? sourceUrl,
    bool? reasoningEnabled,
  }) {
    return ImportedGgufModelMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: filePath ?? this.filePath,
      projectorPath: identical(projectorPath, _unset)
          ? this.projectorPath
          : projectorPath as String?,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      importedAt: importedAt ?? this.importedAt,
      source: source ?? this.source,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
    );
  }

  OnDeviceModel toOnDeviceModel() {
    final isHuggingFace = source == OnDeviceImportedSource.huggingFace;
    final hasProjector =
        projectorPath != null && projectorPath!.trim().isNotEmpty;
    return OnDeviceModel(
      id: id,
      name: name,
      huggingFaceUrl: isHuggingFace ? (sourceUrl ?? '') : '',
      fileSizeBytes: fileSizeBytes,
      license: sourceLabel,
      description: isHuggingFace
          ? 'Imported GGUF model from Hugging Face for local llama.cpp inference.'
          : 'Imported GGUF model from a local file for local llama.cpp inference.',
      minRamMb: estimatedMinRamMb,
      parameterLabel: 'GGUF',
      bestFor: 'Local GGUF inference',
      languagesLabel: 'Local',
      backendNote: 'llama.cpp',
      isCpuOnly: true,
      runtime: OnDeviceModelRuntime.llamaCpp,
      format: OnDeviceModelFormat.gguf,
      localPath: filePath,
      projectorPath: projectorPath,
      supportsVision: hasProjector,
      importedAt: importedAt,
      isImported: true,
      importedSource: source,
      reasoningEnabled: reasoningEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'filePath': filePath,
      'projectorPath': projectorPath,
      'fileSizeBytes': fileSizeBytes,
      'importedAt': importedAt.toIso8601String(),
      'source': source.name,
      'sourceUrl': sourceUrl,
      'reasoningEnabled': reasoningEnabled,
    };
  }

  factory ImportedGgufModelMetadata.fromJson(Map<String, dynamic> json) {
    return ImportedGgufModelMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      filePath: json['filePath'] as String,
      projectorPath: json['projectorPath'] as String?,
      fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
      importedAt: DateTime.parse(json['importedAt'] as String),
      source: _sourceFromJson(json['source']),
      sourceUrl: json['sourceUrl'] as String?,
      reasoningEnabled: json['reasoningEnabled'] as bool?,
    );
  }

  static OnDeviceImportedSource _sourceFromJson(dynamic value) {
    if (value is String) {
      return OnDeviceImportedSource.values.firstWhere(
        (source) => source.name == value,
        orElse: () => OnDeviceImportedSource.localFile,
      );
    }
    return OnDeviceImportedSource.localFile;
  }
}

/// Handle to one enqueued Hugging Face import group.
class HuggingFaceImportGroup {
  final String groupId;
  final String name;
  final String modelTaskId;
  final String? projectorTaskId;
  final bool hasProjector;

  const HuggingFaceImportGroup({
    required this.groupId,
    required this.name,
    required this.modelTaskId,
    required this.projectorTaskId,
    required this.hasProjector,
  });
}

/// Legacy awaiter for one import group (progress + final metadata).
class _GroupWaiter {
  final Completer<ImportedGgufModelMetadata> completer =
      Completer<ImportedGgufModelMetadata>();
  final void Function(int receivedBytes, int totalBytes)? onProgress;

  _GroupWaiter({this.onProgress});
}

/// Import group tracked until every task is published.
class _PendingImport {
  final String groupId;
  final String name;
  final String sourceUrl;
  final String modelFinalPath;
  final String? projectorFinalPath;
  bool modelPublished = false;
  bool projectorPublished = false;
  String? publishedProjectorPath;

  _PendingImport({
    required this.groupId,
    required this.name,
    required this.sourceUrl,
    required this.modelFinalPath,
    required this.projectorFinalPath,
  });

  bool get hasProjector => projectorFinalPath != null;
}

class ImportedGgufModelRepository {
  static const _storageKey = 'imported_gguf_models_v1';
  static const _storageDirName = 'imported_gguf_models';

  final SharedPreferences _prefs;
  // The engine owns HTTP transfers; dio is retained for legacy call sites.
  // ignore: unused_field
  final Dio _dio;
  final Random _random;
  final Future<Directory> Function()? modelsDirectoryProvider;
  final DownloadEngine? _engine;
  final OsDownloadBridge? _osBridge;

  /// Imports mid-flight, keyed by group id (== metadata id). Published files
  /// stay on disk per task; metadata persists only when the whole group is
  /// published, and any failure rolls published files back.
  final Map<String, _PendingImport> _pendingImports = {};
  final Map<String, _GroupWaiter> _groupWaiters = {};

  ImportedGgufModelRepository(
    this._prefs,
    this._dio, {
    Random? random,
    this.modelsDirectoryProvider,
    DownloadEngine? engine,
    OsDownloadBridge? osBridge,
  }) : _random = random ?? Random.secure(),
       _engine = engine,
       _osBridge = osBridge {
    _engine
      ?..registerPostTransfer(_handleImportTask)
      ..registerTaskFailureHandler(_handleImportFailure);
  }

  List<ImportedGgufModelMetadata> load() {
    final encoded = _prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return [];

    final decoded = json.decode(encoded) as List<dynamic>;
    return decoded
        .map(
          (item) =>
              ImportedGgufModelMetadata.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> updateReasoning(String modelId, bool? enabled) async {
    final models = load();
    final index = models.indexWhere((model) => model.id == modelId);
    if (index < 0) throw StateError('Imported model no longer exists');
    models[index] = ImportedGgufModelMetadata.fromJson({
      ...models[index].toJson(),
      'reasoningEnabled': enabled,
    });
    await saveAll(models);
  }

  static bool isProjectorFileName(String name) {
    final lower = name.toLowerCase();
    return lower.contains('mmproj') || lower.contains('projector');
  }

  Future<List<ImportedGgufModelMetadata>> loadExisting() async {
    final models = load();
    final existing = <ImportedGgufModelMetadata>[];
    var hasChanges = false;

    for (final model in models) {
      if (await File(model.filePath).exists()) {
        if (model.projectorPath != null &&
            !await File(model.projectorPath!).exists()) {
          existing.add(model.copyWith(projectorPath: null));
          hasChanges = true;
        } else {
          existing.add(model);
        }
      } else {
        hasChanges = true;
        if (model.projectorPath != null) {
          final proj = File(model.projectorPath!);
          if (await proj.exists()) {
            await proj.delete();
          }
        }
      }
    }

    if (hasChanges || existing.length != models.length) {
      await saveAll(existing);
    }

    return existing;
  }

  Future<ImportedGgufModelMetadata> importFromPath(
    String sourcePath, {
    String? projectorPath,
  }) async {
    final source = File(sourcePath);
    if (!sourcePath.toLowerCase().endsWith('.gguf')) {
      throw const FormatException(
        'Only GGUF models are supported for this import.',
      );
    }
    if (!await source.exists()) {
      throw FileSystemException(
        'Selected model file does not exist',
        sourcePath,
      );
    }

    final originalName = p.basename(sourcePath);
    if (isProjectorFileName(originalName) && projectorPath == null) {
      throw const FormatException(
        'The selected file appears to be a multimodal vision projector (mmproj), '
        'not a standalone model. Please select the main model file or attach this '
        'projector to an existing model.',
      );
    }

    String? resolvedProjectorPath = projectorPath;
    if (resolvedProjectorPath == null) {
      try {
        final parentDir = source.parent;
        if (parentDir.existsSync()) {
          final candidates = parentDir
              .listSync()
              .whereType<File>()
              .where(
                (f) =>
                    f.path.toLowerCase().endsWith('.gguf') &&
                    isProjectorFileName(p.basename(f.path)),
              )
              .map((file) => file.path)
              .toList();
          resolvedProjectorPath = _uniqueProjectorForModel(
            sourcePath,
            candidates,
            allowSingleFallback: true,
          );
        }
      } catch (_) {}
    }

    final dir = await _modelsDirectory();
    final id = _createId(originalName);
    final fileName = '$id-${_sanitizeFileName(originalName)}';
    final target = File(p.join(dir.path, fileName));
    File? targetProjector;

    try {
      await source.copy(target.path);
      await _validateGgufFile(target);

      if (resolvedProjectorPath != null) {
        final projSource = File(resolvedProjectorPath);
        if (await projSource.exists() &&
            projSource.path.toLowerCase().endsWith('.gguf')) {
          final projOriginalName = p.basename(resolvedProjectorPath);
          final projFileName =
              '$id-mmproj-${_sanitizeFileName(projOriginalName)}';
          targetProjector = File(p.join(dir.path, projFileName));
          await projSource.copy(targetProjector.path);
          await _validateGgufFile(targetProjector);
        }
      }

      final metadata = ImportedGgufModelMetadata(
        id: id,
        name: _displayNameFromFileName(originalName),
        filePath: target.path,
        projectorPath: targetProjector?.path,
        fileSizeBytes: await target.length(),
        importedAt: DateTime.now(),
        source: OnDeviceImportedSource.localFile,
      );

      final current = load();
      await saveAll([...current, metadata]);
      return metadata;
    } catch (_) {
      if (await target.exists()) {
        await target.delete();
      }
      if (targetProjector != null && await targetProjector.exists()) {
        await targetProjector.delete();
      }
      rethrow;
    }
  }

  Future<List<ImportedGgufModelMetadata>> importFromPaths(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return [];
    if (paths.length == 1) {
      return [await importFromPath(paths.single)];
    }

    final projectors = paths
        .where((filePath) => isProjectorFileName(p.basename(filePath)))
        .toList();
    final models = paths
        .where((filePath) => !isProjectorFileName(p.basename(filePath)))
        .toList();

    if (models.isEmpty && projectors.isNotEmpty) {
      throw const FormatException(
        'All selected files appear to be vision projectors (mmproj). '
        'Please select a main model file or attach these projectors to existing models.',
      );
    }

    final projectorByModel = <String, String>{};
    for (final projector in projectors) {
      final matchingModels = models
          .where((model) => _pathsShareProjectorTokens(model, projector))
          .toList(growable: false);
      final String matchedModel;
      if (matchingModels.length == 1) {
        matchedModel = matchingModels.single;
      } else if (models.length == 1 && projectors.length == 1) {
        matchedModel = models.single;
      } else {
        throw FormatException(
          matchingModels.isEmpty
              ? 'Could not match ${p.basename(projector)} to a selected model. '
                    'Import the model first, then attach the projector manually.'
              : '${p.basename(projector)} matches more than one selected model. '
                    'Import the models separately and attach the projector manually.',
        );
      }
      if (projectorByModel.containsKey(matchedModel)) {
        throw FormatException(
          'More than one projector was selected for ${p.basename(matchedModel)}. '
          'Choose one projector and attach any replacement later.',
        );
      }
      projectorByModel[matchedModel] = projector;
    }

    final results = <ImportedGgufModelMetadata>[];
    for (final modelPath in models) {
      results.add(
        await importFromPath(
          modelPath,
          projectorPath: projectorByModel[modelPath],
        ),
      );
    }

    return results;
  }

  Future<ImportedGgufModelMetadata> attachProjector(
    String modelId,
    String projectorSourcePath,
  ) async {
    final projSource = File(projectorSourcePath);
    if (!projectorSourcePath.toLowerCase().endsWith('.gguf')) {
      throw const FormatException('Only GGUF projector files are supported.');
    }
    if (!await projSource.exists()) {
      throw FileSystemException(
        'Selected projector file does not exist',
        projectorSourcePath,
      );
    }

    final models = load();
    final index = models.indexWhere((m) => m.id == modelId);
    if (index < 0) {
      throw StateError('Imported model no longer exists');
    }

    final dir = await _modelsDirectory();
    final projOriginalName = p.basename(projectorSourcePath);
    final projFileName =
        '$modelId-mmproj-${_createId(projOriginalName)}-'
        '${_sanitizeFileName(projOriginalName)}';
    final targetProjector = File(p.join(dir.path, projFileName));
    final stagedProjector = File('${targetProjector.path}.part');
    var metadataSaved = false;

    try {
      await projSource.copy(stagedProjector.path);
      await _validateGgufFile(stagedProjector);
      await stagedProjector.rename(targetProjector.path);

      final oldProjPath = models[index].projectorPath;
      final updated = models[index].copyWith(
        projectorPath: targetProjector.path,
      );
      models[index] = updated;
      await saveAll(models);
      metadataSaved = true;

      if (oldProjPath != null && oldProjPath != targetProjector.path) {
        final oldProj = File(oldProjPath);
        if (await oldProj.exists() && p.isWithin(dir.path, oldProj.path)) {
          try {
            await oldProj.delete();
          } catch (_) {
            // Metadata already points at the validated replacement. A stale
            // file is safer than rolling back to a missing projector.
          }
        }
      }
      return updated;
    } catch (_) {
      if (!metadataSaved && await targetProjector.exists()) {
        await targetProjector.delete();
      }
      rethrow;
    } finally {
      if (await stagedProjector.exists()) {
        await stagedProjector.delete();
      }
    }
  }

  Future<ImportedGgufModelMetadata> removeProjector(String modelId) async {
    final models = load();
    final index = models.indexWhere((m) => m.id == modelId);
    if (index < 0) {
      throw StateError('Imported model no longer exists');
    }

    final oldProjPath = models[index].projectorPath;
    final updated = models[index].copyWith(projectorPath: null);
    models[index] = updated;
    await saveAll(models);

    if (oldProjPath != null) {
      try {
        final dir = await _modelsDirectory();
        final oldProj = File(oldProjPath);
        if (await oldProj.exists() && p.isWithin(dir.path, oldProj.path)) {
          await oldProj.delete();
        }
      } catch (_) {
        // The model is already safely detached in metadata. A stale file can
        // be cleaned up later without breaking the model entry.
      }
    }
    return updated;
  }

/// Enqueues a Hugging Face GGUF import (plus its optional projector) as a
/// download-engine task group. Fire-and-forget: progress and terminal states
/// arrive through [DownloadEngine.changes]; metadata persists once every
/// task of the group is published.
Future<HuggingFaceImportGroup> enqueueHuggingFaceImport({
  required String sourceUrl,
  String? projectorUrl,
  String? token,
  bool osBackground = false,
}) async {
  // Validate inputs before requiring the engine so URL-only errors surface
  // even in mis-wired contexts.
  final engine = _requireEngine();
  final normalizedUrl = _normalizeHuggingFaceGgufUrl(sourceUrl);
  final originalName = _fileNameFromUri(normalizedUrl);
  final dir = await _modelsDirectory();
  final id = _createId(originalName);
  final modelFinalPath = p.join(dir.path, '$id-${_sanitizeFileName(originalName)}');
  String? projectorFinalPath;
  if (projectorUrl != null && projectorUrl.trim().isNotEmpty) {
    final normalizedProjector = _normalizeHuggingFaceGgufUrl(projectorUrl.trim());
    final projOriginalName = _fileNameFromUri(normalizedProjector);
    projectorFinalPath =
        p.join(dir.path, '$id-mmproj-${_sanitizeFileName(projOriginalName)}');
  }

  final modelTask = await engine.enqueue(
    kind: DownloadTaskKind.gguf,
    groupId: id,
    url: normalizedUrl.toString(),
    finalPath: modelFinalPath,
    partPath: '$modelFinalPath.part',
    requiresAuth: token != null && token.isNotEmpty,
    authToken: token,
  );
  String? projectorTaskId;
  if (projectorFinalPath != null) {
    final projectorTask = await engine.enqueue(
      kind: DownloadTaskKind.projector,
      groupId: id,
      url: projectorUrl!.trim(),
      finalPath: projectorFinalPath,
      partPath: '$projectorFinalPath.part',
      dependsOnTaskId: modelTask.id,
      requiresAuth: token != null && token.isNotEmpty,
      authToken: token,
    );
    projectorTaskId = projectorTask.id;
  }

  if (osBackground) {
    // Hand the model transfer to the OS downloader; on hand-off failure the
    // task silently continues on the in-app path (spec fallback).
    await _engine!.delegateToOs(
      modelTask.id,
      handOff: (payload) => _osBridge!.handOff(payload),
    );
  }
  _pendingImports[id] = _PendingImport(
    groupId: id,
    name: _displayNameFromFileName(originalName),
    sourceUrl: normalizedUrl.toString(),
    modelFinalPath: modelFinalPath,
    projectorFinalPath: projectorFinalPath,
  );
  return HuggingFaceImportGroup(
    groupId: id,
    name: _displayNameFromFileName(originalName),
    modelTaskId: modelTask.id,
    projectorTaskId: projectorTaskId,
    hasProjector: projectorFinalPath != null,
  );
}

/// Post-transfer hook: validates the downloaded GGUF, renames it into place
/// and persists metadata once the whole import group is published.
Future<void> _handleImportTask(DownloadTask task) async {
  final pending = _pendingImports[task.groupId];
  if (pending == null) {
    // The import group was deleted mid-chain: discard the result as an
    // orphan file cleanup and let the task complete with a warning.
    final part = File(task.partPath);
    if (await part.exists()) await part.delete();
    Log.warning(
      'Import group ${task.groupId} disappeared; discarded ${task.kind.name} result',
    );
    return;
  }
  final file = File(task.partPath);
  await _validateGgufFile(file);
  await file.rename(task.finalPath);
  if (task.kind == DownloadTaskKind.gguf) {
    pending.modelPublished = true;
  } else {
    pending.projectorPublished = true;
    pending.publishedProjectorPath = task.finalPath;
  }
  if (pending.modelPublished &&
      (!pending.hasProjector || pending.projectorPublished)) {
    final metadata = ImportedGgufModelMetadata(
      id: pending.groupId,
      name: pending.name,
      filePath: pending.modelFinalPath,
      projectorPath: pending.publishedProjectorPath,
      fileSizeBytes: await File(pending.modelFinalPath).length(),
      importedAt: DateTime.now(),
      source: OnDeviceImportedSource.huggingFace,
      sourceUrl: pending.sourceUrl,
    );
    final models = load().where((m) => m.id != pending.groupId).toList();
    await saveAll([...models, metadata]);
    _pendingImports.remove(pending.groupId);
    _groupWaiters.remove(pending.groupId)?.completer.complete(metadata);
  }
}

/// Failure hook: rolls published files of the group back so storage stays
/// clean, matching the previous all-or-nothing import behavior.
Future<void> _handleImportFailure(DownloadTask task, Object error) async {
  final pending = _pendingImports[task.groupId];
  if (pending == null) return;
  if (pending.modelPublished && await File(pending.modelFinalPath).exists()) {
    await File(pending.modelFinalPath).delete();
  }
  if (pending.publishedProjectorPath != null &&
      await File(pending.publishedProjectorPath!).exists()) {
    await File(pending.publishedProjectorPath!).delete();
  }
  _pendingImports.remove(pending.groupId);
  await _engine?.deleteGroup(pending.groupId);
  Log.error('Import group ${task.groupId} failed: $error');
  _groupWaiters.remove(pending.groupId)?.completer.completeError(error);
}

DownloadEngine _requireEngine() {
  final engine = _engine;
  if (engine == null) {
    throw StateError('Download engine is not wired to this repository');
  }
  return engine;
}

/// Legacy-compatible Hugging Face import: enqueues through the engine and
/// awaits the whole group, forwarding progress and honoring [cancelToken].
Future<ImportedGgufModelMetadata> importFromHuggingFaceUrl(
  String sourceUrl, {
  String? projectorUrl,
  String? token,
  void Function(int receivedBytes, int totalBytes)? onProgress,
  CancelToken? cancelToken,
}) async {
  final engine = _requireEngine();
  final group = await enqueueHuggingFaceImport(
    sourceUrl: sourceUrl,
    projectorUrl: projectorUrl,
    token: token,
  );
  if (cancelToken != null && cancelToken.isCancelled) {
    await engine.deleteGroup(group.groupId);
    _pendingImports.remove(group.groupId);
    throw const HttpException('GGUF import canceled.');
  }
  final waiter = _GroupWaiter(onProgress: onProgress);
  _groupWaiters[group.groupId] = waiter;
  if (cancelToken != null) {
    unawaited(
      cancelToken.whenCancel.then((_) {
        unawaited(engine.cancel(group.modelTaskId));
        final projector = group.projectorTaskId;
        if (projector != null) unawaited(engine.cancel(projector));
        if (!waiter.completer.isCompleted) {
          waiter.completer
              .completeError(const HttpException('GGUF import canceled.'));
        }
      }),
    );
  }
  // Progress lives on engine changes; completion/errors arrive through the
  // waiter registered above (state-emission order independent).
  final progressSub = engine.changes.listen((tasks) {
    if (onProgress == null || waiter.completer.isCompleted) return;
    final groupTasks = tasks.where((t) => t.groupId == group.groupId);
    for (final t in groupTasks) {
      if (t.totalBytes > 0) {
        onProgress(t.receivedBytes, t.totalBytes);
      }
    }
  });
  try {
    return await waiter.completer.future;
  } finally {
    await progressSub.cancel();
    _groupWaiters.remove(group.groupId);
  }
}

  Future<void> delete(String id) async {
    await _engine?.deleteGroup(id);
    final current = load();
    final kept = <ImportedGgufModelMetadata>[];

    for (final model in current) {
      if (model.id == id) {
        final file = File(model.filePath);
        if (await file.exists()) {
          await file.delete();
        }
        if (model.projectorPath != null) {
          final projFile = File(model.projectorPath!);
          if (await projFile.exists()) {
            await projFile.delete();
          }
        }
      } else {
        kept.add(model);
      }
    }

    await saveAll(kept);
  }

  Future<void> saveAll(List<ImportedGgufModelMetadata> models) async {
    final encoded = json.encode(models.map((m) => m.toJson()).toList());
    if (!await _prefs.setString(_storageKey, encoded)) {
      throw StateError('Could not save imported models');
    }
  }

  Future<Directory> _modelsDirectory() async {
    final provided = modelsDirectoryProvider;
    if (provided != null) {
      final dir = await provided();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, _storageDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String? _uniqueProjectorForModel(
    String modelPath,
    List<String> projectorPaths, {
    required bool allowSingleFallback,
  }) {
    if (projectorPaths.isEmpty) return null;
    final matches = projectorPaths
        .where((path) => _pathsShareProjectorTokens(modelPath, path))
        .toList(growable: false);
    if (matches.length == 1) return matches.single;
    if (matches.isEmpty && allowSingleFallback && projectorPaths.length == 1) {
      return projectorPaths.single;
    }
    return null;
  }

  bool _pathsShareProjectorTokens(String modelPath, String projectorPath) {
    final modelBase = p.basenameWithoutExtension(modelPath).toLowerCase();
    final projectorBase = p
        .basenameWithoutExtension(projectorPath)
        .toLowerCase();
    final sharedTokens = modelBase
        .split(RegExp(r'[-_.]'))
        .where((token) => token.length > 2)
        .where(
          (token) =>
              token != 'model' &&
              token != 'instruct' &&
              token != 'chat' &&
              token != 'gguf',
        );
    return sharedTokens.any(projectorBase.contains);
  }

  Uri _normalizeHuggingFaceGgufUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter a Hugging Face GGUF URL.');
    }

    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'https://huggingface.co/$trimmed';

    final uri = Uri.parse(withScheme);
    final host = uri.host.toLowerCase();
    if (!_isAllowedHuggingFaceHost(host)) {
      throw const FormatException(
        'Only official Hugging Face GGUF URLs are supported.',
      );
    }

    if (uri.scheme.toLowerCase() != 'https') {
      throw const FormatException(
        'Use an HTTPS Hugging Face URL for GGUF import.',
      );
    }

    final normalizedSegments = [...uri.pathSegments];
    final blobIndex = normalizedSegments.indexOf('blob');
    if (blobIndex != -1) {
      normalizedSegments[blobIndex] = 'resolve';
    }

    final normalizedUri = uri.replace(pathSegments: normalizedSegments);
    final fileName = _fileNameFromUri(normalizedUri);
    if (!fileName.toLowerCase().endsWith('.gguf')) {
      throw const FormatException(
        'The Hugging Face URL must point directly to a .gguf file.',
      );
    }
    return normalizedUri;
  }

  String _fileNameFromUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      throw const FormatException('Unable to determine the GGUF file name.');
    }

    final fileName = Uri.decodeComponent(segments.last);
    if (!fileName.toLowerCase().endsWith('.gguf')) {
      throw const FormatException('Unable to determine the GGUF file name.');
    }
    return fileName;
  }

  bool _isAllowedHuggingFaceHost(String host) {
    return host == 'huggingface.co' ||
        host == 'www.huggingface.co' ||
        host == 'hf.co';
  }

  Future<void> _validateGgufFile(File file) async {
    final bytes = await file.openRead(0, 4).expand((chunk) => chunk).toList();
    final isGguf =
        bytes.length == 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x47 &&
        bytes[2] == 0x55 &&
        bytes[3] == 0x46;

    if (!isGguf) {
      throw const FormatException(
        'The selected file is not a valid GGUF model.',
      );
    }
  }

  String _createId(String fileName) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'gguf-$micros-$suffix';
  }

  String _sanitizeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (sanitized.toLowerCase().endsWith('.gguf')) return sanitized;
    return '$sanitized.gguf';
  }

  String _displayNameFromFileName(String fileName) {
    final withoutExtension = fileName.replaceFirst(
      RegExp(r'\.gguf$', caseSensitive: false),
      '',
    );
    return withoutExtension
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
