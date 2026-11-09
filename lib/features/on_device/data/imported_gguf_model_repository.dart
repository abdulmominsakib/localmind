import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/async_mutex.dart';
import 'download_operation_store.dart';
import 'download_task_gateway.dart';
import 'models/download_operation.dart';
import '../../../core/logger/app_logger.dart';
import '../utils/model_quantization_parser.dart';
import '../../../core/utils/hugging_face_url.dart';

import 'models/on_device_model.dart';
import '../utils/model_param_size_parser.dart';
import 'huggingface_model_search_service.dart';

class ImportedGgufModelMetadata {
  static const _unset = Object();

  final String id;
  final String name;
  final String? filePath;
  final String? projectorPath;
  final int fileSizeBytes;
  final DateTime importedAt;
  final OnDeviceImportedSource source;
  final String? sourceUrl;
  final bool? reasoningEnabled;
  // Hugging Face metadata (Phase 4)
  final String? repoId;
  final String? rfilename;
  final String? revision;
  final String? fileOid;
  final DateTime? lastModified;
  final String? latestFileOid;
  final DateTime? latestLastModified;
  final DateTime? lastCheckedAt;
  final String? pipelineTag;
  final String? libraryName;
  final String? license;
  final String? baseModel;
  final String? architecture;
  final int? contextLength;
  final String? quantization;
  final List<String> languages;
  final List<String> modalities;
  final String? parameterLabelOverride;
  final bool? updateAvailable;
  final String? latestRevision;

  const ImportedGgufModelMetadata({
    required this.id,
    required this.name,
    this.filePath,
    this.projectorPath,
    required this.fileSizeBytes,
    required this.importedAt,
    required this.source,
    this.sourceUrl,
    this.reasoningEnabled,
    this.repoId,
    this.rfilename,
    this.revision,
    this.fileOid,
    this.lastModified,
    this.latestFileOid,
    this.latestLastModified,
    this.lastCheckedAt,
    this.pipelineTag,
    this.libraryName,
    this.license,
    this.baseModel,
    this.architecture,
    this.contextLength,
    this.quantization,
    this.languages = const <String>[],
    this.modalities = const <String>[],
    this.parameterLabelOverride,
    this.updateAvailable,
    this.latestRevision,
  });

  String get fileName {
    if (filePath != null && filePath!.isNotEmpty) {
      return p.basename(filePath!);
    }
    if (sourceUrl != null && sourceUrl!.isNotEmpty) {
      return Uri.parse(sourceUrl!).pathSegments.last;
    }
    return '$id.gguf';
  }

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
    Object? filePath = _unset,
    Object? projectorPath = _unset,
    int? fileSizeBytes,
    DateTime? importedAt,
    OnDeviceImportedSource? source,
    Object? sourceUrl = _unset,
    bool? reasoningEnabled,
    Object? repoId = _unset,
    Object? rfilename = _unset,
    Object? revision = _unset,
    Object? fileOid = _unset,
    Object? lastModified = _unset,
    Object? latestFileOid = _unset,
    Object? latestLastModified = _unset,
    Object? lastCheckedAt = _unset,
    Object? pipelineTag = _unset,
    Object? libraryName = _unset,
    Object? license = _unset,
    Object? baseModel = _unset,
    Object? architecture = _unset,
    Object? contextLength = _unset,
    Object? quantization = _unset,
    List<String>? languages,
    List<String>? modalities,
    Object? parameterLabelOverride = _unset,
    Object? updateAvailable = _unset,
    Object? latestRevision = _unset,
  }) {
    return ImportedGgufModelMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: identical(filePath, _unset)
          ? this.filePath
          : filePath as String?,
      projectorPath: identical(projectorPath, _unset)
          ? this.projectorPath
          : projectorPath as String?,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      importedAt: importedAt ?? this.importedAt,
      source: source ?? this.source,
      sourceUrl: identical(sourceUrl, _unset)
          ? this.sourceUrl
          : sourceUrl as String?,
      reasoningEnabled: reasoningEnabled ?? this.reasoningEnabled,
      repoId: identical(repoId, _unset) ? this.repoId : repoId as String?,
      rfilename: identical(rfilename, _unset) ? this.rfilename : rfilename as String?,
      revision: identical(revision, _unset) ? this.revision : revision as String?,
      fileOid: identical(fileOid, _unset) ? this.fileOid : fileOid as String?,
      lastModified: identical(lastModified, _unset)
          ? this.lastModified
          : lastModified as DateTime?,
      latestFileOid: identical(latestFileOid, _unset)
          ? this.latestFileOid
          : latestFileOid as String?,
      latestLastModified: identical(latestLastModified, _unset)
          ? this.latestLastModified
          : latestLastModified as DateTime?,
      lastCheckedAt: identical(lastCheckedAt, _unset)
          ? this.lastCheckedAt
          : lastCheckedAt as DateTime?,
      pipelineTag: identical(pipelineTag, _unset) ? this.pipelineTag : pipelineTag as String?,
      libraryName: identical(libraryName, _unset) ? this.libraryName : libraryName as String?,
      license: identical(license, _unset) ? this.license : license as String?,
      baseModel: identical(baseModel, _unset) ? this.baseModel : baseModel as String?,
      architecture: identical(architecture, _unset) ? this.architecture : architecture as String?,
      contextLength: identical(contextLength, _unset)
          ? this.contextLength
          : contextLength as int?,
      quantization: identical(quantization, _unset) ? this.quantization : quantization as String?,
      languages: languages ?? this.languages,
      modalities: modalities ?? this.modalities,
      parameterLabelOverride: identical(parameterLabelOverride, _unset)
          ? this.parameterLabelOverride
          : parameterLabelOverride as String?,
      updateAvailable: identical(updateAvailable, _unset)
          ? this.updateAvailable
          : updateAvailable as bool?,
      latestRevision: identical(latestRevision, _unset)
          ? this.latestRevision
          : latestRevision as String?,
    );
  }

  OnDeviceModel toOnDeviceModel() {
    final isHuggingFace = source == OnDeviceImportedSource.huggingFace;
    final hasProjector =
        projectorPath != null && projectorPath!.trim().isNotEmpty;
    final langs = languages.isNotEmpty
        ? languages.join(', ')
        : 'Local';
    return OnDeviceModel(
      id: id,
      name: name,
      huggingFaceUrl: isHuggingFace ? (sourceUrl ?? '') : '',
      fileSizeBytes: fileSizeBytes,
      license: license ?? sourceLabel,
      description: isHuggingFace
          ? 'Imported GGUF model from Hugging Face for local llama.cpp inference.'
          : 'Imported GGUF model from a local file for local llama.cpp inference.',
      minRamMb: estimatedMinRamMb,
      parameterLabel: parameterLabelOverride ?? 'GGUF',
      bestFor: 'Local GGUF inference',
      languagesLabel: langs,
      backendNote: 'llama.cpp',
      isCpuOnly: true,
      runtime: OnDeviceModelRuntime.llamaCpp,
      format: OnDeviceModelFormat.gguf,
      localPath: filePath,
      projectorPath: projectorPath,
      supportsVision: hasProjector,
      modality: hasProjector ? 'vision' : 'text',
      quantization: quantization ?? parseQuantization(name),
      repoId: repoId,
      updateAvailable: updateAvailable ?? false,
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
      'repoId': repoId,
      'rfilename': rfilename,
      'revision': revision,
      'fileOid': fileOid,
      'lastModified': lastModified?.toIso8601String(),
      'latestFileOid': latestFileOid,
      'latestLastModified': latestLastModified?.toIso8601String(),
      'lastCheckedAt': lastCheckedAt?.toIso8601String(),
      'pipelineTag': pipelineTag,
      'libraryName': libraryName,
      'license': license,
      'baseModel': baseModel,
      'architecture': architecture,
      'contextLength': contextLength,
      'quantization': quantization,
      'languages': languages,
      'modalities': modalities,
      'parameterLabelOverride': parameterLabelOverride,
      'updateAvailable': updateAvailable,
      'latestRevision': latestRevision,
    };
  }

  factory ImportedGgufModelMetadata.fromJson(Map<String, dynamic> json) {
    final langs = json['languages'];
    final mods = json['modalities'];
    return ImportedGgufModelMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      filePath: json['filePath'] as String?,
      projectorPath: json['projectorPath'] as String?,
      fileSizeBytes: (json['fileSizeBytes'] as num).toInt(),
      importedAt: DateTime.parse(json['importedAt'] as String),
      source: _sourceFromJson(json['source']),
      sourceUrl: json['sourceUrl'] as String?,
      reasoningEnabled: json['reasoningEnabled'] as bool?,
      repoId: json['repoId'] as String?,
      rfilename: json['rfilename'] as String?,
      revision: json['revision'] as String?,
      fileOid: json['fileOid'] as String?,
      lastModified: json['lastModified'] != null
          ? DateTime.tryParse(json['lastModified'] as String)
          : null,
      latestFileOid: json['latestFileOid'] as String?,
      latestLastModified: json['latestLastModified'] != null
          ? DateTime.tryParse(json['latestLastModified'] as String)
          : null,
      lastCheckedAt: json['lastCheckedAt'] != null
          ? DateTime.tryParse(json['lastCheckedAt'] as String)
          : null,
      pipelineTag: json['pipelineTag'] as String?,
      libraryName: json['libraryName'] as String?,
      license: json['license'] as String?,
      baseModel: json['baseModel'] as String?,
      architecture: json['architecture'] as String?,
      contextLength: (json['contextLength'] as num?)?.toInt(),
      quantization: json['quantization'] as String?,
      languages: langs is List
          ? langs.map((e) => e.toString()).toList()
          : const <String>[],
      modalities: mods is List
          ? mods.map((e) => e.toString()).toList()
          : const <String>[],
      parameterLabelOverride: json['parameterLabelOverride'] as String?,
      updateAvailable: json['updateAvailable'] as bool?,
      latestRevision: json['latestRevision'] as String?,
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

class ImportedGgufModelRepository {
  static const _storageKey = 'imported_gguf_models_v1';
  static const _storageDirName = 'imported_gguf_models';

  final SharedPreferences _prefs;
  final Dio _dio;
  final Random _random;
  final Future<Directory> Function()? modelsDirectoryProvider;
  final DownloadOperationStore? operations;
  final DownloadTaskGateway? gateway;
  final AsyncMutex _mutex = AsyncMutex();
  Future<void>? _reconcileFuture;
  final Map<String, AsyncMutex> _downloadMutexes = <String, AsyncMutex>{};
  final Map<String, _GgufDownloadAttempt> _ggufAttempts =
      <String, _GgufDownloadAttempt>{};
  final Map<String, DownloadTask> _activeGgufTasks = <String, DownloadTask>{};
  int _ggufAttemptCounter = 0;

  ImportedGgufModelRepository(
    this._prefs,
    this._dio, {
    Random? random,
    this.modelsDirectoryProvider,
    this.operations,
    this.gateway,
  }) : _random = random ?? Random.secure();

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

  Future<void> updateReasoning(String modelId, bool? enabled) {
    return _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((model) => model.id == modelId);
      if (index < 0) throw StateError('Imported model no longer exists');
      models[index] = ImportedGgufModelMetadata.fromJson({
        ...models[index].toJson(),
        'reasoningEnabled': enabled,
      });
      await _saveAllUnlocked(models);
    });
  }

  static bool isProjectorFileName(String name) {
    final lower = name.toLowerCase();
    return lower.contains('mmproj') || lower.contains('projector');
  }

  Future<List<ImportedGgufModelMetadata>> loadExisting() async {
    // Snapshot paths under the lock, then do file I/O outside the lock.
    final firstModels = await _mutex.run(() async => load());
    final fileExists = <String, bool>{};
    final projectorExists = <String, bool>{};
    for (final model in firstModels) {
      if (model.filePath != null && model.filePath!.isNotEmpty) {
        fileExists[model.id] = await File(model.filePath!).exists();
      }
      if (model.projectorPath != null && model.projectorPath!.isNotEmpty) {
        projectorExists[model.id] = await File(model.projectorPath!).exists();
      }
    }
    // Delete projectors when the model file is missing and projector exists.
    for (final model in firstModels) {
      if (model.filePath != null &&
          model.filePath!.isNotEmpty &&
          fileExists[model.id] != true &&
          model.projectorPath != null &&
          projectorExists[model.id] == true) {
        try {
          await File(model.projectorPath!).delete();
        } catch (_) {}
      }
    }

    return _mutex.run(() async {
      // Re-read current metadata under the lock so concurrent writes are not
      // clobbered by a stale snapshot.
      final models = load();
      final existing = <ImportedGgufModelMetadata>[];
      var hasChanges = false;

      for (final model in models) {
        // Backfill repo metadata from sourceUrl when missing (best-effort).
        var working = model;
        if (working.sourceUrl != null && working.sourceUrl!.isNotEmpty &&
            (working.repoId == null || working.rfilename == null || working.revision == null)) {
          try {
            final parsed = parseHuggingFaceUrlMetadata(working.sourceUrl!);
            working = working.copyWith(
              repoId: working.repoId ?? parsed.repoId,
              rfilename: working.rfilename ?? parsed.rfilename,
              revision: working.revision ?? parsed.revision,
            );
            if (working.repoId != model.repoId ||
                working.rfilename != model.rfilename ||
                working.revision != model.revision) {
              hasChanges = true;
            }
          } catch (_) {
            // Best-effort; leave nulls.
          }
        }

        if (working.filePath == null || working.filePath!.isEmpty) {
          existing.add(working);
          continue;
        }
        final exists = fileExists.containsKey(working.id)
            ? fileExists[working.id]!
            : await File(working.filePath!).exists();
        if (exists) {
          final projExists = projectorExists.containsKey(working.id)
              ? projectorExists[working.id]!
              : (working.projectorPath != null && working.projectorPath!.isNotEmpty
                  ? await File(working.projectorPath!).exists()
                  : false);
          if (working.projectorPath != null &&
              working.projectorPath!.isNotEmpty &&
              !projExists) {
            existing.add(working.copyWith(projectorPath: null));
            hasChanges = true;
          } else {
            existing.add(working);
          }
        } else {
          hasChanges = true;
        }
      }

      if (hasChanges || existing.length != models.length) {
        await _saveAllUnlocked(existing);
      }

      return existing;
    });
  }

  Future<ImportedGgufModelMetadata> importFromPath(
    String sourcePath, {
    String? projectorPath,
  }) {
    return _mutex.run(() async {
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
      final displayName = _displayNameFromFileName(originalName);
      final existing = load().where((model) => model.name == displayName);
      if (existing.isNotEmpty) {
        return existing.first;
      }

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
        await _saveAllUnlocked([...current, metadata]);
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
    });
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
  ) {
    return _mutex.run(() async {
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
        await _saveAllUnlocked(models);
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
    });
  }

  Future<ImportedGgufModelMetadata> removeProjector(String modelId) {
    return _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((m) => m.id == modelId);
      if (index < 0) {
        throw StateError('Imported model no longer exists');
      }

      final oldProjPath = models[index].projectorPath;
      final updated = models[index].copyWith(projectorPath: null);
      models[index] = updated;
      await _saveAllUnlocked(models);

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
    });
  }

  Future<ImportedGgufModelMetadata> importFromHuggingFaceUrl(
    String sourceUrl, {
    String? projectorUrl,
    String? token,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
  }) {
    return _mutex.run(() async {
      final normalizedUrl = _normalizeHuggingFaceGgufUrl(sourceUrl);
      // Dedupe by sourceUrl or (repoId, rfilename).
      final segs = normalizedUrl.pathSegments;
      final repoId = segs.length >= 2 ? '${segs[0]}/${segs[1]}' : null;
      final rfilename = segs.isNotEmpty ? segs.last : null;
      final existing = load().where((m) {
        if (m.sourceUrl == normalizedUrl.toString()) { return true; }
        if (repoId != null && rfilename != null &&
            m.repoId == repoId && m.rfilename == rfilename) { return true; }
        return false;
      }).firstOrNull;
      if (existing != null) return existing;

      final originalName = _fileNameFromUri(normalizedUrl);
      final dir = await _modelsDirectory();
      final id = _createId(originalName);
      final fileName = '$id-${_sanitizeFileName(originalName)}';
      final targetPath = p.join(dir.path, fileName);
      final tempPath = '$targetPath.part';
      final tempFile = File(tempPath);
      final targetFile = File(targetPath);

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      File? targetProjectorFile;
      var metadataSaved = false;

      try {
        await _dio.download(
          normalizedUrl.toString(),
          tempPath,
          cancelToken: cancelToken,
          onReceiveProgress: onProgress,
          options: Options(
            headers: {
              if (token != null && token.isNotEmpty)
                HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            followRedirects: true,
            receiveTimeout: const Duration(hours: 12),
            sendTimeout: const Duration(minutes: 5),
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        );

        if (!await tempFile.exists() || await tempFile.length() <= 0) {
          throw const FileSystemException(
            'The downloaded GGUF file was empty or missing.',
          );
        }

        await _validateGgufFile(tempFile);
        await tempFile.rename(targetPath);

        if (projectorUrl != null && projectorUrl.trim().isNotEmpty) {
          final normalizedProjUrl = _normalizeHuggingFaceGgufUrl(
            projectorUrl.trim(),
          );
          final projOriginalName = _fileNameFromUri(normalizedProjUrl);
          final projFileName =
              '$id-mmproj-${_sanitizeFileName(projOriginalName)}';
          final projTargetPath = p.join(dir.path, projFileName);
          final projTempPath = '$projTargetPath.part';
          final projTempFile = File(projTempPath);
          targetProjectorFile = File(projTargetPath);

          if (await projTempFile.exists()) {
            await projTempFile.delete();
          }

          try {
            await _dio.download(
              normalizedProjUrl.toString(),
              projTempPath,
              cancelToken: cancelToken,
              options: Options(
                headers: {
                  if (token != null && token.isNotEmpty)
                    HttpHeaders.authorizationHeader: 'Bearer $token',
                },
                followRedirects: true,
                receiveTimeout: const Duration(hours: 12),
                sendTimeout: const Duration(minutes: 5),
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 400,
              ),
            );

            if (!await projTempFile.exists() ||
                await projTempFile.length() <= 0) {
              throw const FileSystemException(
                'The downloaded projector GGUF file was empty or missing.',
              );
            }

            await _validateGgufFile(projTempFile);
            await projTempFile.rename(projTargetPath);
          } finally {
            if (await projTempFile.exists()) {
              await projTempFile.delete();
            }
          }
        }

        final metadata0 = ImportedGgufModelMetadata(
          id: id,
          name: _displayNameFromFileName(originalName),
          filePath: targetFile.path,
          projectorPath: targetProjectorFile?.path,
          fileSizeBytes: await targetFile.length(),
          importedAt: DateTime.now(),
          source: OnDeviceImportedSource.huggingFace,
          sourceUrl: normalizedUrl.toString(),
          repoId: repoId,
          rfilename: rfilename,
          revision: (segs.length >= 5 && segs[2].toLowerCase() == 'resolve' && segs[3].toLowerCase() != 'main') ? segs[3] : null,
        );
        final metadata = await _enrichGgufMetadata(metadata0, token);

        final current = load();
        await _saveAllUnlocked([...current, metadata]);
        metadataSaved = true;
        return metadata;
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) {
          throw const HttpException('GGUF import canceled.');
        }
        throw HttpException(_friendlyDioError(e));
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        if (!metadataSaved) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          if (targetProjectorFile != null &&
              await targetProjectorFile.exists()) {
            await targetProjectorFile.delete();
          }
        }
      }
    });
  }

  Future<ImportedGgufModelMetadata> addFromUrl(
    String sourceUrl, {
    String? projectorUrl,
    String? token,
  }) {
    return _mutex.run(() async {
      final normalizedUrl = _normalizeHuggingFaceGgufUrl(sourceUrl);
      final existing = load().where(
        (model) => model.sourceUrl == normalizedUrl.toString(),
      );
      if (existing.isNotEmpty) {
        return existing.first;
      }

      final originalName = _fileNameFromUri(normalizedUrl);
      final id = _createId(originalName);

      int fileSizeBytes = 0;
      try {
        final response = await _dio.head(
          normalizedUrl.toString(),
          options: Options(
            headers: {
              if (token != null && token.isNotEmpty)
                HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            followRedirects: true,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 400,
          ),
        );
        final length = response.headers.value(HttpHeaders.contentLengthHeader);
        if (length != null) {
          fileSizeBytes = int.tryParse(length) ?? 0;
        }
      } catch (_) {
        // Size is optional for deferred entries.
      }

      final segs = normalizedUrl.pathSegments;
      final parsedRepoId = segs.length >= 2 ? '${segs[0]}/${segs[1]}' : null;
      // Use the full repository-relative path (not just the basename) so that
      // files with the same basename in different subdirectories do not collide.
      String parsedRfilename = originalName;
      final resolveIdx = segs.indexWhere((s) => s.toLowerCase() == 'resolve');
      if (resolveIdx >= 0 && resolveIdx + 2 < segs.length) {
        parsedRfilename = segs.sublist(resolveIdx + 2).map(Uri.decodeComponent).join('/');
      } else if (resolveIdx >= 0 && resolveIdx + 1 < segs.length && segs.length > resolveIdx + 1) {
        // No explicit revision segment; treat the rest as the path.
        parsedRfilename = segs.sublist(resolveIdx + 1).map(Uri.decodeComponent).join('/');
      }
      if (parsedRfilename.isEmpty) parsedRfilename = originalName;
      String? parsedRevision;
      if (segs.length >= 5 && segs[2].toLowerCase() == 'resolve' &&
          segs[3].toLowerCase() != 'main') {
        parsedRevision = segs[3];
      }

      // Dedupe by (repoId, rfilename).
      if (parsedRepoId != null) {
        final current = load();
        final existing = current.where((m) =>
            m.repoId == parsedRepoId && m.rfilename == parsedRfilename && m.revision == parsedRevision).firstOrNull;
        if (existing != null) return existing;
      }

      var metadata = ImportedGgufModelMetadata(
        id: id,
        name: _displayNameFromFileName(originalName),
        filePath: null,
        projectorPath: null,
        fileSizeBytes: fileSizeBytes,
        importedAt: DateTime.now(),
        source: OnDeviceImportedSource.huggingFace,
        sourceUrl: normalizedUrl.toString(),
        repoId: parsedRepoId,
        rfilename: parsedRfilename,
        revision: parsedRevision,
      );

      // Best-effort metadata enrichment.
      metadata = await _enrichGgufMetadata(metadata, token);

      final current2 = load();
      // Re-check dedupe after enrichment/network.
      if (metadata.repoId != null) {
        final dup = current2.where((m) =>
            m.repoId == metadata.repoId && m.rfilename == metadata.rfilename && m.revision == metadata.revision).firstOrNull;
        if (dup != null) return dup;
      }
      await _saveAllUnlocked([...current2, metadata]);
      return metadata;
    });
  }


  Future<void> reconcileCompletedDownloads() async {
    final pending = _reconcileFuture;
    if (pending != null) return pending;
    final future = _reconcileOnce();
    _reconcileFuture = future;
    try {
      await future;
    } finally {
      _reconcileFuture = null;
    }
  }

  Future<void> _reconcileOnce() async {
    List<TaskRecord> records;
    try {
      records = await FileDownloader().database.allRecords(
        group: 'localmind_gguf_downloads',
      );
    } catch (_) {
      return;
    }

    // Dedupe: cancel all but the first task sharing a taskId.
    final byId = <String, List<TaskRecord>>{};
    for (final r in records) {
      byId.putIfAbsent(r.task.taskId, () => []).add(r);
    }
    for (final entry in byId.entries) {
      if (entry.value.length <= 1) continue;
      for (final r in entry.value.skip(1)) {
        try { await FileDownloader().cancel(r.task); } catch (_) {}
        try { await FileDownloader().database.deleteRecordWithId(r.task.taskId); } catch (_) {}
      }
    }

    // Clean up canceled/failed update tasks.
    for (final record in records) {
      final rawId = record.task.taskId;
      if (!rawId.endsWith('-update')) continue;
      if (record.status == TaskStatus.canceled || record.status == TaskStatus.failed) {
        try { await FileDownloader().database.deleteRecordWithId(rawId); } catch (_) {}
        try {
          final tempPath = await record.task.filePath();
          final tempFile = File(tempPath);
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    }

    for (final record in records) {
      if (record.status != TaskStatus.complete) continue;
      final rawId = record.task.taskId;

      // Handle update tasks ($modelId-update).
      if (rawId.endsWith('-update')) {
        final modelId = rawId.substring(0, rawId.length - '-update'.length);
        final models = load();
        final index = models.indexWhere((m) => m.id == modelId);
        if (index < 0) continue;

        // Revision revalidation.
        final op = operations?.forModel(modelId);
        if (op != null && op.type == DownloadOperationType.update &&
            op.targetRevision != null &&
            models[index].latestRevision != null &&
            op.targetRevision != models[index].latestRevision) {
          try { await FileDownloader().database.deleteRecordWithId(rawId); } catch (_) {}
          try {
            final tp = await record.task.filePath();
            final tf = File(tp);
            if (await tf.exists()) await tf.delete();
          } catch (_) {}
          if (operations != null) await operations!.fail(op.operationId);
          continue;
        }

        String? filePath;
        try {
          filePath = await record.task.filePath();
        } catch (_) {
          continue;
        }
        if (filePath == null || filePath.isEmpty) continue;
        final file = File(filePath);
        if (!await file.exists() || await file.length() <= 0) continue;

        try {
          await _validateGgufFile(file);
        } catch (_) {
          continue;
        }

        final oldFilePath = models[index].filePath;
        await _mutex.run(() async {
          final fresh = load();
          final i = fresh.indexWhere((m) => m.id == modelId);
          if (i >= 0) {
            // Save metadata FIRST (crash-safe).
            fresh[i] = fresh[i].copyWith(
              filePath: filePath,
              fileSizeBytes: await file.length(),
              revision: fresh[i].latestRevision ?? fresh[i].revision,
              fileOid: fresh[i].latestFileOid ?? fresh[i].fileOid,
              lastModified: fresh[i].latestLastModified ?? fresh[i].lastModified,
              latestFileOid: null,
              latestLastModified: null,
              updateAvailable: false,
              latestRevision: null,
              lastCheckedAt: DateTime.now(),
            );
            await _saveAllUnlocked(fresh);
            // THEN delete old file (best-effort).
            if (oldFilePath != null &&
                oldFilePath != filePath &&
                await File(oldFilePath).exists()) {
              try { await File(oldFilePath).delete(); } catch (_) {}
            }
          }
        });

        try { await FileDownloader().database.deleteRecordWithId(rawId); } catch (_) {}
        continue;
      }

      final modelId = rawId;
      final models = load();
      final index = models.indexWhere((m) => m.id == modelId);
      if (index < 0) continue;
      final model = models[index];
      if (model.filePath != null &&
          model.filePath!.isNotEmpty &&
          await File(model.filePath!).exists()) {
        continue;
      }

      String? filePath;
      try {
        filePath = await record.task.filePath();
      } catch (_) {
        continue;
      }
      if (filePath.isEmpty) continue;
      final file = File(filePath);
      if (!await file.exists() || await file.length() <= 0) continue;

      try {
        await _validateGgufFile(file);
      } catch (_) {
        continue;
      }

      await _mutex.run(() async {
        final fresh = load();
        final i = fresh.indexWhere((m) => m.id == modelId);
        if (i >= 0) {
          fresh[i] = fresh[i].copyWith(
            filePath: filePath,
            fileSizeBytes: await file.length(),
          );
          await _saveAllUnlocked(fresh);
        }
      });
      await FileDownloader().database.deleteRecordWithId(modelId);
    }
  }

  Future<ImportedGgufModelMetadata> _enrichGgufMetadata(
    ImportedGgufModelMetadata metadata,
    String? token,
  ) async {
    if (metadata.repoId == null || metadata.rfilename == null) return metadata;
    try {
      final service = HuggingFaceModelSearchService(dio: _dio);
      final info = await service.fetchModelInfo(
        metadata.repoId!,
        rfilename: metadata.rfilename,
        token: token,
      );
      if (info == null) return metadata;
      return metadata.copyWith(
        revision: metadata.revision ?? info.sha,
        fileOid: info.fileOid,
        lastModified: info.lastModified,
        pipelineTag: info.pipelineTag,
        libraryName: info.libraryName,
        license: info.license,
        baseModel: info.baseModel,
        architecture: info.architecture,
        contextLength: info.contextLength,
        quantization: info.quantization ?? parseQuantization(metadata.name),
        languages: info.languages.isNotEmpty ? info.languages : metadata.languages,
        modalities: info.modalities.isNotEmpty ? info.modalities : metadata.modalities,
        parameterLabelOverride: info.totalParameters != null
            ? formatParameterSize(info.totalParameters!)
            : metadata.parameterLabelOverride,
      );
    } catch (_) {
      return metadata;
    }
  }


  Future<int> checkForUpdates({String? token}) async {
    final models = load().where((m) =>
        m.source == OnDeviceImportedSource.huggingFace &&
        m.repoId != null &&
        m.rfilename != null).toList();
    int updated = 0;
    for (final model in models) {
      try {
        final service = HuggingFaceModelSearchService(dio: _dio);
        final info = await service.fetchModelInfo(
          model.repoId!,
          rfilename: model.rfilename,
          token: token,
        );
        if (info == null) continue;
        // Compare fileOid first, then sha.
        bool changed = false;
        if (model.latestFileOid != null && info.fileOid != null) {
          changed = model.latestFileOid != info.fileOid;
        } else if (model.fileOid != null && info.fileOid != null) {
          changed = model.fileOid != info.fileOid;
        } else if (model.revision != null && info.sha != null) {
          changed = model.revision != info.sha;
        } else if (info.sha != null && model.revision == null) {
          changed = false; // no baseline
        }
        await _mutex.run(() async {
          final fresh = load();
          final idx = fresh.indexWhere((m) => m.id == model.id);
          if (idx < 0) return;
          fresh[idx] = fresh[idx].copyWith(
            lastCheckedAt: DateTime.now(),
            updateAvailable: changed ? true : fresh[idx].updateAvailable,
            latestRevision: changed ? info.sha : fresh[idx].latestRevision,
            // enrich metadata on change
            latestFileOid: info.fileOid ?? fresh[idx].latestFileOid,
            latestLastModified: info.lastModified ?? fresh[idx].latestLastModified,
            pipelineTag: info.pipelineTag ?? fresh[idx].pipelineTag,
            libraryName: info.libraryName ?? fresh[idx].libraryName,
            license: info.license ?? fresh[idx].license,
            baseModel: info.baseModel ?? fresh[idx].baseModel,
            architecture: info.architecture ?? fresh[idx].architecture,
            contextLength: info.contextLength ?? fresh[idx].contextLength,
            quantization: info.quantization ?? fresh[idx].quantization,
            languages: info.languages.isNotEmpty ? info.languages : fresh[idx].languages,
            modalities: info.modalities.isNotEmpty ? info.modalities : fresh[idx].modalities,
          );
          await _saveAllUnlocked(fresh);
        });
        if (changed) updated++;
      } catch (_) {
        // best-effort
      }
    }
    return updated;
  }

  Future<TaskStatus> download(
    String modelId, {
    String? token,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    try {
      await FileDownloader().permissions
          .request(PermissionType.notifications)
          .timeout(const Duration(seconds: 10),
              onTimeout: () => PermissionStatus.requestError);
    } catch (_) {}

    final lock = _downloadMutexes.putIfAbsent(modelId, () => AsyncMutex());
    await lock.run(() async {
      final models = load();
      final index = models.indexWhere((model) => model.id == modelId);
      if (index < 0) {
        throw StateError('Imported GGUF model no longer exists');
      }

      final model = models[index];
      if (model.filePath != null && model.filePath!.isNotEmpty) {
        return TaskStatus.complete;
      }
      if (model.sourceUrl == null || model.sourceUrl!.isEmpty) {
        throw const FormatException('Imported GGUF model has no source URL.');
      }

      await _modelsDirectory();

      final originalName = _fileNameFromUri(Uri.parse(model.sourceUrl!));
      final task = DownloadTask(
        taskId: modelId,
        url: model.sourceUrl!,
        filename: '$modelId-${_sanitizeFileName(originalName)}',
        directory: _storageDirName,
        baseDirectory: BaseDirectory.applicationSupport,
        headers: {
          if (token != null && token.isNotEmpty)
            HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        allowPause: true,
        retries: 3,
        updates: Updates.statusAndProgress,
        group: 'localmind_gguf_downloads',
        displayName: model.name,
      );

      _activeGgufTasks[modelId] = task;

      var lastReceived = 0;
      final result = await FileDownloader().download(
        task,
        onProgress: (progress) {
          if (onProgress == null) return;
          final total = model.fileSizeBytes > 0 ? model.fileSizeBytes : 0;
          if (total > 0) {
            final received = (progress.clamp(0.0, 1.0) * total).round().clamp(0, total);
            if (received >= lastReceived) {
              lastReceived = received;
              onProgress(received, total);
            }
          } else {
            onProgress(
              (progress.clamp(0.0, 1.0) * 100).round().clamp(0, 100),
              100,
            );
          }
        },
      );

      if (result.status == TaskStatus.paused) {
        _activeGgufTasks[modelId] = task as DownloadTask;
        return TaskStatus.paused;
      }
      if (result.status == TaskStatus.canceled) {
        _activeGgufTasks.remove(modelId);
        await FileDownloader().database.deleteRecordWithId(modelId);
        throw const HttpException('GGUF import canceled.');
      }
      if (result.status != TaskStatus.complete) {
        _activeGgufTasks.remove(modelId);
        await FileDownloader().database.deleteRecordWithId(modelId);
        throw HttpException(
          result.exception?.description ?? 'GGUF download failed.',
        );
      }

      final filePath = await task.filePath();
      final file = File(filePath);
      if (!await file.exists() || await file.length() <= 0) {
        _activeGgufTasks.remove(modelId);
        await FileDownloader().database.deleteRecordWithId(modelId);
        throw const FileSystemException(
          'The downloaded GGUF file was empty or missing.',
        );
      }

      await _validateGgufFile(file);

      final fileSize = await file.length();
      await _mutex.run(() async {
        final freshModels = load();
        final freshIndex = freshModels.indexWhere((m) => m.id == modelId);
        if (freshIndex >= 0) {
          freshModels[freshIndex] = freshModels[freshIndex].copyWith(
            filePath: filePath,
            fileSizeBytes: fileSize,
          );
          await _saveAllUnlocked(freshModels);
        }
      });

      _activeGgufTasks.remove(modelId);
      await FileDownloader().database.deleteRecordWithId(modelId);
      return TaskStatus.complete;
    });
    return TaskStatus.complete;
  }


  /// Download an update for an already-imported GGUF model.
  Future<TaskStatus> downloadUpdate(
    String modelId, {
    String? token,
    String? operationId,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    try {
      await FileDownloader().permissions
          .request(PermissionType.notifications)
          .timeout(const Duration(seconds: 10),
              onTimeout: () => PermissionStatus.requestError);
    } catch (_) {}

    final lock = _downloadMutexes.putIfAbsent(modelId, () => AsyncMutex());
    return lock.run(() async {
      // Write-ahead intent.
      if (operations != null && operationId != null) {
        await operations!.begin(DownloadOperation(
          operationId: operationId,
          modelId: modelId,
          type: DownloadOperationType.update,
          taskId: '$modelId-update',
          phase: DownloadOperationPhase.downloading,
          startedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }

      final models = load();
      final index = models.indexWhere((model) => model.id == modelId);
      if (index < 0) {
        throw StateError('Imported GGUF model no longer exists');
      }
      final model = models[index];
      final originalRevision = model.revision;
      if (operations != null && operationId != null) {
        await operations!.enrich(
          operationId,
          taskId: '$modelId-update',
          baseRevision: model.revision,
          targetRevision: model.latestRevision,
        );
      }
      if (model.sourceUrl == null || model.sourceUrl!.isEmpty) {
        throw const FormatException('Imported GGUF model has no source URL.');
      }

      final oldFilePath = model.filePath;
      final originalName = _fileNameFromUri(Uri.parse(model.sourceUrl!));
      final task = DownloadTask(
        taskId: '$modelId-update',
        url: model.sourceUrl!,
        filename: '$modelId-update-${_sanitizeFileName(originalName)}',
        directory: _storageDirName,
        baseDirectory: BaseDirectory.applicationSupport,
        headers: {
          if (token != null && token.isNotEmpty)
            HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        allowPause: true,
        retries: 3,
        updates: Updates.statusAndProgress,
        group: 'localmind_gguf_downloads',
        displayName: '${model.name} (update)',
      );

      _activeGgufTasks[modelId] = task;

      var lastReceived = 0;
      final result = await FileDownloader().download(
        task,
        onProgress: (progress) {
          if (onProgress == null) return;
          final total = model.fileSizeBytes > 0 ? model.fileSizeBytes : 0;
          if (total > 0) {
            final received = (progress.clamp(0.0, 1.0) * total).round().clamp(0, total);
            if (received >= lastReceived) {
              lastReceived = received;
              onProgress(received, total);
            }
          } else {
            onProgress(
              (progress.clamp(0.0, 1.0) * 100).round().clamp(0, 100),
              100,
            );
          }
        },
      );

      if (result.status == TaskStatus.paused) {
        _activeGgufTasks[modelId] = task as DownloadTask;
        return TaskStatus.paused;
      }
      if (result.status == TaskStatus.canceled) {
        _activeGgufTasks.remove(modelId);
        await FileDownloader().database.deleteRecordWithId('$modelId-update');
        if (operations != null && operationId != null) {
          await operations!.fail(operationId);
        }
        throw const HttpException('GGUF update canceled.');
      }
      if (result.status != TaskStatus.complete) {
        _activeGgufTasks.remove(modelId);
        await FileDownloader().database.deleteRecordWithId('$modelId-update');
        if (operations != null && operationId != null) {
          await operations!.fail(operationId);
        }
        // Clean up temp file.
        try {
          final tempPath = await task.filePath();
          final tempFile = File(tempPath);
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
        throw HttpException(
          result.exception?.description ?? 'GGUF update failed.',
        );
      }

      final filePath = await task.filePath();
      final file = File(filePath);
      if (!await file.exists() || await file.length() <= 0) {
        _activeGgufTasks.remove(modelId);
        await FileDownloader().database.deleteRecordWithId('$modelId-update');
        throw const FileSystemException('The downloaded GGUF file was empty or missing.');
      }

      await _validateGgufFile(file);

      final fileSize = await file.length();
      await _mutex.run(() async {
        final freshModels = load();
        final freshIndex = freshModels.indexWhere((m) => m.id == modelId);
        if (freshIndex < 0) {
          throw StateError('Model removed during update: $modelId');
        }
        // Revalidate revision.
        if (freshModels[freshIndex].revision != originalRevision) {
          Log.warning('Revision changed during GGUF update for $modelId; aborting finalization.');
          // Clean up temp file (best-effort).
          try { await File(filePath).delete(); } catch (_) {}
          throw const HttpException('revision_changed');
        }
        // Update metadata FIRST (crash-safe).
        freshModels[freshIndex] = freshModels[freshIndex].copyWith(
          filePath: filePath,
          fileSizeBytes: fileSize,
          revision: freshModels[freshIndex].latestRevision ?? freshModels[freshIndex].revision,
          updateAvailable: false,
          latestRevision: null,
          lastCheckedAt: DateTime.now(),
        );
        await _saveAllUnlocked(freshModels);

        // THEN delete old file (best-effort).
        if (oldFilePath != null &&
            oldFilePath != filePath &&
            await File(oldFilePath).exists()) {
          try {
            await File(oldFilePath).delete();
          } catch (_) {}
        }
      });

      if (operations != null && operationId != null) {
        await operations!.complete(operationId);
      }
      _activeGgufTasks.remove(modelId);
      await FileDownloader().database.deleteRecordWithId('$modelId-update');
      return TaskStatus.complete;
    });
  }


  Future<bool> pauseDownload(String modelId) async {
    final tasks = (await FileDownloader().allTasks(allGroups: true))
        .where((t) => t.taskId == modelId || t.taskId == '$modelId-update')
        .toList();
    if (tasks.isEmpty) {
      final t = _activeGgufTasks[modelId];
      if (t != null) tasks.add(t);
      final ut = await FileDownloader().taskForId('$modelId-update');
      if (ut != null) tasks.add(ut);
    }
    if (tasks.isEmpty) return false;
    bool any = false;
    for (final t in tasks) {
      _activeGgufTasks[modelId] = t as DownloadTask;
      try {
        final ok = await FileDownloader().pause(t as DownloadTask);
        if (ok) any = true;
      } catch (_) {}
    }
    return any;
  }

  Future<TaskStatus> resumeDownload(
    String modelId, {
    String? token,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final models = load();
    final idx = models.indexWhere((m) => m.id == modelId);
    if (idx < 0) throw StateError('Imported GGUF model no longer exists');
    final model = models[idx];
    if (model.filePath != null && model.filePath!.isNotEmpty) return TaskStatus.complete;

    var task = _activeGgufTasks[modelId];
    if (task == null) {
      final existing = await FileDownloader().taskForId(modelId);
      task = existing as DownloadTask?;
    }
    if (task == null) {
      await download(modelId, token: token, onProgress: onProgress);
      return TaskStatus.complete;
    }
    _activeGgufTasks[modelId] = task;

    final totalBytes = model.fileSizeBytes > 0 ? model.fileSizeBytes : 0;
    final completer = Completer<void>();
    var lastReceived = 0;
    final sub = FileDownloader().updates.listen((update) {
      if (update.task.taskId != modelId) return;
      if (update is TaskProgressUpdate) {
        final total = (update.hasExpectedFileSize && update.expectedFileSize > 0)
            ? update.expectedFileSize
            : totalBytes;
        if (total > 0 && onProgress != null) {
          final received = (update.progress.clamp(0.0, 1.0) * total).round();
          if (received >= lastReceived) {
            lastReceived = received;
            onProgress(received, total);
          }
        }
        if (update.progress >= 1.0 && !completer.isCompleted) {
          completer.complete();
        }
      } else if (update is TaskStatusUpdate) {
        if (update.status == TaskStatus.complete ||
            update.status == TaskStatus.canceled ||
            update.status == TaskStatus.failed ||
            update.status == TaskStatus.paused ||
            update.status == TaskStatus.notFound) {
          if (!completer.isCompleted) completer.complete();
        }
      }
    });

    // If the surviving task is already running/complete, don't re-enqueue.
    bool ok = true;
    TaskStatus? dbStatus;
    try {
      dbStatus = (await FileDownloader().database.recordForId(modelId))?.status;
      if (dbStatus != null &&
          (dbStatus == TaskStatus.running || dbStatus == TaskStatus.enqueued)) {
        ok = true;
      } else if (dbStatus == TaskStatus.paused) {
        ok = await FileDownloader().resume(task);
      } else {
        ok = true;
      }
    } catch (_) {
      ok = await FileDownloader().resume(task);
    }
    if (!ok) {
      await sub.cancel();
      if (dbStatus == TaskStatus.paused) {
        try { await FileDownloader().cancel(task); } catch (_) {}
        try { await FileDownloader().database.deleteRecordWithId(modelId); } catch (_) {}
        await download(modelId, token: token, onProgress: onProgress);
        return TaskStatus.complete;
      }
      _activeGgufTasks.remove(modelId);
      return TaskStatus.running;
    }

    if (dbStatus == TaskStatus.complete) {
      await sub.cancel();
      return TaskStatus.complete;
    }

    await completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {},
    );
    await sub.cancel();

    TaskStatus status;
    try {
      status = (await FileDownloader().database.recordForId(modelId))?.status ?? TaskStatus.running;
    } catch (_) {
      status = TaskStatus.running;
    }

    if (status == TaskStatus.complete) {
      final filePath = await task.filePath();
      final file = File(filePath);
      if (await file.exists() && await file.length() > 0) {
        try {
          await _validateGgufFile(file);
          final fileSize = await file.length();
          await _mutex.run(() async {
            final freshModels = load();
            final freshIndex = freshModels.indexWhere((m) => m.id == modelId);
            if (freshIndex >= 0) {
              freshModels[freshIndex] = freshModels[freshIndex].copyWith(
                filePath: filePath,
                fileSizeBytes: fileSize,
              );
              await _saveAllUnlocked(freshModels);
            }
          });
        } catch (_) {}
      }
    } else if (status == TaskStatus.paused || status == TaskStatus.canceled || status == TaskStatus.failed) {
      _activeGgufTasks.remove(modelId);
    }
    return status == TaskStatus.running ? TaskStatus.paused : status;
  }

  Future<void> cancelDownload(String modelId) async {
    for (final taskId in [modelId, '$modelId-update']) {
      final tasks = (await FileDownloader().allTasks(allGroups: true))
          .where((t) => t.taskId == taskId)
          .toList();
      for (final t in tasks) {
        try { await FileDownloader().cancel(t); } catch (_) {}
      }
      await FileDownloader().cancelTaskWithId(taskId);
    }
    _activeGgufTasks.remove(modelId);
    try {
      final t = await FileDownloader().taskForId('$modelId-update');
      if (t != null) {
        final tp = await t.filePath();
        final tf = File(tp);
        if (await tf.exists()) await tf.delete();
      }
    } catch (_) {}
  }

  Future<void> deleteFile(String modelId) async {
    final attempt = _ggufAttempts.remove(modelId);
    attempt?.cancelToken.cancel('Deleted by user');

    await _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((model) => model.id == modelId);
      if (index < 0) {
        throw StateError('Imported GGUF model no longer exists');
      }

      final model = models[index];
      if (model.filePath != null) {
        final file = File(model.filePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (model.projectorPath != null) {
        final projFile = File(model.projectorPath!);
        if (await projFile.exists()) {
          await projFile.delete();
        }
      }

      models[index] = model.copyWith(filePath: null, projectorPath: null);
      await _saveAllUnlocked(models);
    });
  }

  Future<void> removeFromList(String id) {
    return _mutex.run(() async {
      final current = load();
      final kept = current.where((model) => model.id != id).toList();
      await _saveAllUnlocked(kept);
    });
  }

  Future<void> delete(String id) {
    return _mutex.run(() async {
      final current = load();
      final kept = <ImportedGgufModelMetadata>[];

      for (final model in current) {
        if (model.id == id) {
          if (model.filePath != null) {
            final file = File(model.filePath!);
            if (await file.exists()) {
              await file.delete();
            }
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

      await _saveAllUnlocked(kept);
    });
  }

  Future<void> saveAll(List<ImportedGgufModelMetadata> models) {
    return _mutex.run(() => _saveAllUnlocked(models));
  }

  Future<void> _saveAllUnlocked(List<ImportedGgufModelMetadata> models) async {
    final encoded = json.encode(models.map((m) => m.toJson()).toList());
    if (!await _prefs.setString(_storageKey, encoded)) {
      throw StateError('Could not save imported models');
    }
  }

  /// Remove all persisted downloader task records for this group, so that
  /// (possibly token-bearing) headers do not linger after the credential is
  /// cleared or replaced.
  Future<void> scrubDownloadTaskRecords() async {
    try {
      final records = await FileDownloader().database.allRecords(group: 'localmind_gguf_downloads');
      await FileDownloader().database.deleteRecordsWithIds(
        records.map((r) => r.taskId),
      );
    } catch (_) {
      // Best-effort.
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
    final normalizedUri = canonicalizeHuggingFaceUrl(
      input,
      emptyMessage: 'Enter a Hugging Face GGUF URL.',
    );
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

  String _friendlyDioError(DioException error) {
    final statusCode = error.response?.statusCode;
    if (statusCode == 401 || statusCode == 403) {
      return 'Hugging Face denied access to this file. Add a valid Hugging Face token in Settings for gated or private models.';
    }
    if (statusCode == 404) {
      return 'The GGUF file could not be found on Hugging Face.';
    }
    if (statusCode != null) {
      return 'Failed to download GGUF from Hugging Face (HTTP $statusCode).';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'The GGUF download timed out. Please try again on a stable connection.';
    }
    return error.message ?? 'Failed to download GGUF from Hugging Face.';
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

class _GgufDownloadAttempt {
  _GgufDownloadAttempt({required this.id, required this.cancelToken});

  final String id;
  final CancelToken cancelToken;
  bool renamedTarget = false;
  bool paused = false;
}