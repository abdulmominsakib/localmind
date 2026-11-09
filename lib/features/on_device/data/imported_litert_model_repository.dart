import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/async_mutex.dart';
import 'download_operation_store.dart';
import 'download_task_gateway.dart';
import 'models/download_operation.dart';
import '../../../core/logger/app_logger.dart';
import '../../../core/utils/hugging_face_url.dart';
import 'package:background_downloader/background_downloader.dart';

import 'models/on_device_model.dart';
import 'huggingface_model_search_service.dart';
import '../utils/model_quantization_parser.dart';
import '../utils/model_param_size_parser.dart';

class ImportedLitertModelMetadata {
  static const _unset = Object();

  final String id;
  final String name;
  final String? filePath;
  final String? installFileName;
  final String? sourceUrl;
  final int fileSizeBytes;
  final DateTime importedAt;
  final OnDeviceImportedSource source;
  final String? projectorPath;
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

  const ImportedLitertModelMetadata({
    required this.id,
    required this.name,
    this.filePath,
    this.installFileName,
    this.sourceUrl,
    required this.fileSizeBytes,
    required this.importedAt,
    required this.source,
    this.projectorPath,
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
    if (installFileName != null && installFileName!.isNotEmpty) {
      return installFileName!;
    }
    if (filePath != null && filePath!.isNotEmpty) {
      return p.basename(filePath!);
    }
    if (sourceUrl != null && sourceUrl!.isNotEmpty) {
      return Uri.parse(sourceUrl!).pathSegments.last;
    }
    return '$id.litertlm';
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

  bool get isDownloaded => filePath != null && filePath!.isNotEmpty;

  ImportedLitertModelMetadata copyWith({
    String? id,
    String? name,
    Object? filePath = _unset,
    Object? installFileName = _unset,
    Object? sourceUrl = _unset,
    int? fileSizeBytes,
    DateTime? importedAt,
    OnDeviceImportedSource? source,
    Object? projectorPath = _unset,
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
    return ImportedLitertModelMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: identical(filePath, _unset)
          ? this.filePath
          : filePath as String?,
      installFileName: identical(installFileName, _unset)
          ? this.installFileName
          : installFileName as String?,
      sourceUrl: identical(sourceUrl, _unset)
          ? this.sourceUrl
          : sourceUrl as String?,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      importedAt: importedAt ?? this.importedAt,
      source: source ?? this.source,
      projectorPath: identical(projectorPath, _unset)
          ? this.projectorPath
          : projectorPath as String?,
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
    final langs = languages.isNotEmpty ? languages.join(', ') : 'Local';
    // modality from pipeline/tags heuristic: vision if projector or vision modalities
    final mod = modalities.contains('vision') || (projectorPath != null && projectorPath!.isNotEmpty)
        ? 'vision'
        : (modalities.isNotEmpty ? modalities.first : 'text');
    return OnDeviceModel(
      id: id,
      name: name,
      huggingFaceUrl: isHuggingFace ? (sourceUrl ?? '') : '',
      fileSizeBytes: fileSizeBytes,
      license: license ?? sourceLabel,
      description: isHuggingFace
          ? 'Imported LiteRT model from Hugging Face for on-device Gemma inference.'
          : 'Imported LiteRT model from a local file for on-device Gemma inference.',
      minRamMb: 2048,
      parameterLabel: parameterLabelOverride ?? 'LiteRT',
      bestFor: 'Local LiteRT inference',
      languagesLabel: langs,
      backendNote: 'LiteRT',
      runtime: OnDeviceModelRuntime.gemma,
      format: OnDeviceModelFormat.litertlm,
      localPath: filePath,
      installFileName: installFileName,
      projectorPath: projectorPath,
      supportsVision: projectorPath != null && projectorPath!.isNotEmpty,
      modality: mod,
      quantization: quantization,
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
      'installFileName': installFileName,
      'sourceUrl': sourceUrl,
      'fileSizeBytes': fileSizeBytes,
      'importedAt': importedAt.toIso8601String(),
      'source': source.name,
      'projectorPath': projectorPath,
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

  factory ImportedLitertModelMetadata.fromJson(Map<String, dynamic> json) {
    final langs = json['languages'];
    final mods = json['modalities'];
    return ImportedLitertModelMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      filePath: json['filePath'] as String?,
      installFileName: json['installFileName'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      importedAt: DateTime.parse(json['importedAt'] as String),
      source: _sourceFromJson(json['source']),
      projectorPath: json['projectorPath'] as String?,
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

class ImportedLitertModelRepository {
  static const _storageKey = 'imported_litert_models_v1';
  static const _storageDirName = 'imported_litert_models';

  final SharedPreferences _prefs;
  final Dio _dio;
  final Random _random;
  final Future<Directory> Function()? modelsDirectoryProvider;
  final DownloadOperationStore? operations;
  final DownloadTaskGateway? gateway;
  final AsyncMutex _mutex = AsyncMutex();
  Future<void>? _reconcileFuture;
  final Set<String> _registeredLocalModels = <String>{};
  final Map<String, Task> _activeLitertTasks = <String, Task>{};

  ImportedLitertModelRepository(
    this._prefs,
    this._dio, {
    Random? random,
    this.modelsDirectoryProvider,
    this.operations,
    this.gateway,
  }) : _random = random ?? Random.secure();

  List<ImportedLitertModelMetadata> load() {
    final encoded = _prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) return [];

    final decoded = json.decode(encoded) as List<dynamic>;
    return decoded
        .map(
          (item) => ImportedLitertModelMetadata.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> saveAll(List<ImportedLitertModelMetadata> models) {
    return _mutex.run(() => _saveAllUnlocked(models));
  }

  Future<void> _saveAllUnlocked(
    List<ImportedLitertModelMetadata> models,
  ) async {
    final encoded = json.encode(models.map((m) => m.toJson()).toList());
    if (!await _prefs.setString(_storageKey, encoded)) {
      throw StateError('Could not save imported LiteRT models');
    }
  }

  /// Remove all persisted downloader task records for this group, so that
  /// (possibly token-bearing) headers do not linger after the credential is
  /// cleared or replaced.
  Future<void> scrubDownloadTaskRecords() async {
    try {
      final records = await FileDownloader().database.allRecords(group: 'localmind_litert_downloads');
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

  Future<List<ImportedLitertModelMetadata>> loadExisting() async {
    // Read the current metadata under the lock first (avoid stale snapshot),
    // then perform file I/O outside the lock.
    final firstModels = await _mutex.run(() async => load());
    final fileExists = <String, bool>{};
    for (final model in firstModels) {
      if (model.filePath != null && model.filePath!.isNotEmpty) {
        fileExists[model.id] = await File(model.filePath!).exists();
      }
    }

    return _mutex.run(() async {
      // Re-read current metadata under the lock so concurrent writes are not
      // clobbered by a stale snapshot.
      final models = load();
      final existing = <ImportedLitertModelMetadata>[];
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
          existing.add(working);
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

  Future<void> registerLocalModels() async {
    final models = load();
    for (final model in models) {
      if (model.filePath == null || model.filePath!.isEmpty) continue;
      try {
        await _ensureRegistered(model);
      } catch (_) {
        // _ensureRegistered already removed from the set on failure.
      }
    }
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
        group: 'localmind_litert_downloads',
      );
    } catch (_) {
      return;
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

    // Dedupe: if multiple unfinished tasks share a taskId (process-death
    // duplicate), cancel all but the first before reconciling.
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

    for (final record in records) {
      if (record.status != TaskStatus.complete) continue;
      final rawId = record.task.taskId;

      // Handle update tasks ($modelId-update).
      if (rawId.endsWith('-update')) {
        final modelId = rawId.substring(0, rawId.length - '-update'.length);
        final models = load();
        final index = models.indexWhere((m) => m.id == modelId);
        if (index < 0) continue;

        // Revision revalidation: if a newer revision is targeted now, discard.
        final op = operations?.forModel(modelId);
        if (op != null && op.type == DownloadOperationType.update &&
            op.targetRevision != null &&
            models[index].latestRevision != null &&
            op.targetRevision != models[index].latestRevision) {
          // Stale artifact — quarantine.
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
        if (filePath == null || filePath.isEmpty) {
          try { await FileDownloader().database.deleteRecordWithId(rawId); } catch (_) {}
          continue;
        }
        final file = File(filePath);
        if (!await file.exists() || await file.length() <= 0) {
          try { await FileDownloader().database.deleteRecordWithId(rawId); } catch (_) {}
          continue;
        }

        try {
          final previousSpec = FlutterGemma.activeModelSpec;
          await FlutterGemma.installModel(
            modelType: ModelType.general,
            fileType: ModelFileType.litertlm,
          ).fromFile(filePath).install();
          final manager = FlutterGemmaPlugin.instance.modelManager;
          if (previousSpec != null) {
            manager.setActiveModel(previousSpec);
          } else {
            await FlutterGemma.clearActiveInferenceIdentity();
          }
        } catch (_) {
          // Quarantine: delete record and temp file.
          try { await FileDownloader().database.deleteRecordWithId(rawId); } catch (_) {}
          try {
            final tp = await record.task.filePath();
            final tf = File(tp);
            if (await tf.exists()) await tf.delete();
          } catch (_) {}
          continue;
        }

        await _mutex.run(() async {
          final fresh = load();
          final i = fresh.indexWhere((m) => m.id == modelId);
          if (i >= 0) {
            final oldInstallName = fresh[i].installFileName ?? fresh[i].fileName;
            final oldPath = fresh[i].filePath;
            // Save metadata FIRST (crash-safe).
            fresh[i] = fresh[i].copyWith(
              filePath: filePath,
              installFileName: record.task.filename,
              fileSizeBytes: await file.length(),
              revision: fresh[i].latestRevision ?? fresh[i].revision,
              updateAvailable: false,
              latestRevision: null,
              lastCheckedAt: DateTime.now(),
            );
            await _saveAllUnlocked(fresh);
            // THEN uninstall/delete old (best-effort).
            if (oldInstallName != record.task.filename) {
              try {
                await FlutterGemma.uninstallModel(oldInstallName);
              } catch (_) {}
            }
            if (oldPath != null && oldPath != filePath && await File(oldPath).exists()) {
              try { await File(oldPath).delete(); } catch (_) {}
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
        final previousSpec = FlutterGemma.activeModelSpec;
        await FlutterGemma.installModel(
          modelType: ModelType.general,
          fileType: ModelFileType.litertlm,
        ).fromFile(filePath).install();
        final manager = FlutterGemmaPlugin.instance.modelManager;
        if (previousSpec != null) {
          manager.setActiveModel(previousSpec);
        } else {
          await FlutterGemma.clearActiveInferenceIdentity();
        }
      } catch (_) {
        continue;
      }

      await _mutex.run(() async {
        final fresh = load();
        final i = fresh.indexWhere((m) => m.id == modelId);
        if (i >= 0) {
          fresh[i] = fresh[i].copyWith(
            filePath: filePath,
            installFileName: fresh[i].installFileName ?? record.task.filename,
            fileSizeBytes: await file.length(),
          );
          await _saveAllUnlocked(fresh);
        }
      });
      try { await FileDownloader().database.deleteRecordWithId(modelId); } catch (_) {}
    }
  }


  Future<ImportedLitertModelMetadata> _enrichLitertMetadata(
    ImportedLitertModelMetadata metadata,
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
        bool changed = false;
        if (model.latestFileOid != null && info.fileOid != null) {
          changed = model.latestFileOid != info.fileOid;
        } else if (model.fileOid != null && info.fileOid != null) {
          changed = model.fileOid != info.fileOid;
        } else if (model.revision != null && info.sha != null) {
          changed = model.revision != info.sha;
        }
        await _mutex.run(() async {
          final fresh = load();
          final idx = fresh.indexWhere((m) => m.id == model.id);
          if (idx < 0) return;
          fresh[idx] = fresh[idx].copyWith(
            lastCheckedAt: DateTime.now(),
            updateAvailable: changed ? true : fresh[idx].updateAvailable,
            latestRevision: changed ? info.sha : fresh[idx].latestRevision,
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
      } catch (_) {}
    }
    return updated;
  }

  Future<void> _ensureRegistered(ImportedLitertModelMetadata model) async {
    // Single-flight guard: avoid concurrent registration of the same model
    // (e.g. startup microtask + import overlap).
    if (!_registeredLocalModels.add(model.id)) return;
    try {
      final installName = model.installFileName ?? model.fileName;
      final alreadyInstalled = await FlutterGemma.isModelInstalled(installName);
      if (alreadyInstalled) return;

      final previousSpec = FlutterGemma.activeModelSpec;
      await FlutterGemma.installModel(
        modelType: ModelType.general,
        fileType: ModelFileType.litertlm,
      ).fromFile(model.filePath!).install();

      final manager = FlutterGemmaPlugin.instance.modelManager;
      if (previousSpec != null) {
        manager.setActiveModel(previousSpec);
      } else {
        await FlutterGemma.clearActiveInferenceIdentity();
      }
    } catch (e) {
      _registeredLocalModels.remove(model.id);
      rethrow;
    }
  }

  Future<ImportedLitertModelMetadata> addFromPath(String sourcePath) {
    return _mutex.run(() async {
      final source = File(sourcePath);
      if (!sourcePath.toLowerCase().endsWith('.litertlm')) {
        throw const FormatException(
          'Only LiteRT (.litertlm) models are supported for this import.',
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
        final found = existing.first;
        if (found.filePath != null && found.filePath!.isNotEmpty) {
          await _ensureRegistered(found);
          _registeredLocalModels.add(found.id);
        }
        return found;
      }

      final dir = await _modelsDirectory();
      final id = _createId(originalName);
      final fileName = '$id-${_sanitizeFileName(originalName)}';
      final target = File(p.join(dir.path, fileName));

      try {
        await source.copy(target.path);
        final metadata = ImportedLitertModelMetadata(
          id: id,
          name: _displayNameFromFileName(originalName),
          filePath: target.path,
          installFileName: fileName,
          sourceUrl: null,
          fileSizeBytes: await target.length(),
          importedAt: DateTime.now(),
          source: OnDeviceImportedSource.localFile,
        );
        // Register with FlutterGemma before persisting, so a failed
        // registration does not leave a misleading ready entry.
        await _ensureRegistered(metadata);
        _registeredLocalModels.add(metadata.id);
        final current = load();
        await _saveAllUnlocked([...current, metadata]);
        return metadata;
      } catch (_) {
        if (await target.exists()) {
          await target.delete();
        }
        rethrow;
      }
    });
  }

  Future<ImportedLitertModelMetadata> addFromUrl(
    String sourceUrl, {
    String? token,
  }) {
    return _mutex.run(() async {
      final normalizedUrl = _normalizeHuggingFaceLitertUrl(sourceUrl);
      final existing = load().where(
        (model) => model.sourceUrl == normalizedUrl.toString(),
      );
      if (existing.isNotEmpty) {
        return existing.first;
      }

      final originalName = _fileNameFromUri(normalizedUrl);
      final id = _createId(originalName);
      final installFileName = '$id-${_sanitizeFileName(originalName)}';

      int fileSizeBytes = 0;
      try {
        final response = await _dio.headUri(
          normalizedUrl,
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
        final existing = load().where((m) =>
            m.repoId == parsedRepoId && m.rfilename == parsedRfilename && m.revision == parsedRevision).firstOrNull;
        if (existing != null) return existing;
      }

      var metadata = ImportedLitertModelMetadata(
        id: id,
        name: _displayNameFromFileName(originalName),
        filePath: null,
        installFileName: installFileName,
        sourceUrl: normalizedUrl.toString(),
        fileSizeBytes: fileSizeBytes,
        importedAt: DateTime.now(),
        source: OnDeviceImportedSource.huggingFace,
        repoId: parsedRepoId,
        rfilename: parsedRfilename,
        revision: parsedRevision,
      );

      // Best-effort metadata enrichment.
      metadata = await _enrichLitertMetadata(metadata, token);

      final current2 = load();
      if (metadata.repoId != null) {
        final dup = current2.where((m) =>
            m.repoId == metadata.repoId && m.rfilename == metadata.rfilename && m.revision == metadata.revision).firstOrNull;
        if (dup != null) return dup;
      }
      await _saveAllUnlocked([...current2, metadata]);
      return metadata;
    });
  }

  Future<TaskStatus> download(
    String modelId, {
    String? token,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final model = await _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((m) => m.id == modelId);
      if (index < 0) {
        throw StateError('Imported LiteRT model no longer exists');
      }
      return models[index];
    });

    if (model.filePath != null && model.filePath!.isNotEmpty) {
      final previousSpec = FlutterGemma.activeModelSpec;
      await FlutterGemma.installModel(
        modelType: ModelType.general,
        fileType: ModelFileType.litertlm,
      ).fromFile(model.filePath!).install();
      final manager = FlutterGemmaPlugin.instance.modelManager;
      if (previousSpec != null) {
        manager.setActiveModel(previousSpec);
      }
      return TaskStatus.complete;
    }

    if (model.sourceUrl == null || model.sourceUrl!.isEmpty) {
      throw const FormatException('Imported LiteRT model has no source URL.');
    }

    final installName = model.installFileName ?? model.fileName;
    final totalBytes = model.fileSizeBytes > 0 ? model.fileSizeBytes : 0;

    // Best-effort POST_NOTIFICATIONS request on Android 13+ so the foreground
    // service actually gets its exemption. Mirrors SmartDownloader.
    try {
      await FileDownloader().permissions
          .request(PermissionType.notifications)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => PermissionStatus.requestError,
          );
    } catch (_) {
      // Do not block the download on a denial or a thrown request.
    }

    // Dedupe: if a task with this id is already running/paused (e.g. after
    // process death), reuse it instead of enqueuing a duplicate WorkSpec.
    var task = await FileDownloader().taskForId(model.id);
    if (task == null) {
      task = DownloadTask(
        taskId: model.id,
        url: model.sourceUrl!,
        filename: installName,
        directory: _storageDirName,
        baseDirectory: BaseDirectory.applicationSupport,
        headers: {
          if (token != null && token.isNotEmpty)
            HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        allowPause: true,
        retries: 3,
        updates: Updates.statusAndProgress,
        group: 'localmind_litert_downloads',
        displayName: model.name,
      );
    }
    _activeLitertTasks[model.id] = task as DownloadTask;

    // Do NOT call resume() here — it enqueues a second WorkSpec. download()
    // already handles resume data internally when the task is paused.
    var lastReceived = 0;
    final result = await FileDownloader().download(
      task,
      onProgress: (progress) {
        final clamped = progress.clamp(0.0, 1.0);
        if (totalBytes > 0) {
          final received = (clamped * totalBytes).round().clamp(0, totalBytes);
          if (received >= lastReceived) {
            lastReceived = received;
            onProgress?.call(received, totalBytes);
          }
        } else {
          onProgress?.call((clamped * 100).round().clamp(0, 100), 100);
        }
      },
    );

    if (result.status == TaskStatus.paused) {
      // Keep the task reference for resume; do not throw.
      return TaskStatus.paused;
    }
    if (result.status == TaskStatus.canceled) {
      _activeLitertTasks.remove(model.id);
      await FileDownloader().database.deleteRecordWithId(model.id);
      throw const HttpException('LiteRT import canceled.');
    }
    if (result.status != TaskStatus.complete) {
      _activeLitertTasks.remove(model.id);
      await FileDownloader().database.deleteRecordWithId(model.id);
      throw HttpException(
        result.exception?.description ?? 'LiteRT download failed.',
      );
    }
    final status = await _finalizeLitertDownload(modelId, task as DownloadTask, installName);
    // Remove the persisted task record so the (possibly token-bearing) headers
    // do not linger in the downloader's database.
    await FileDownloader().database.deleteRecordWithId(model.id);
    return status;
  }


  /// Download an update for an already-imported LiteRT model.
  /// Downloads to a temp path, then on success swaps metadata and cleans up old.
  Future<TaskStatus> downloadUpdate(
    String modelId, {
    String? token,
    String? operationId,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
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

    final model = await _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((m) => m.id == modelId);
      if (index < 0) {
        throw StateError('Imported LiteRT model no longer exists');
      }
      return models[index];
    });

    if (model.sourceUrl == null || model.sourceUrl!.isEmpty) {
      throw const FormatException('Imported LiteRT model has no source URL.');
    }

    if (operations != null && operationId != null) {
      await operations!.enrich(
        operationId,
        taskId: '$modelId-update',
        baseRevision: model.revision,
        targetRevision: model.latestRevision,
      );
    }

    final updateTaskId = '$modelId-update';
    final updateInstallName = '$modelId-update.litertlm';
    final oldFilePath = model.filePath;
    final oldInstallName = model.installFileName ?? model.fileName;
    final totalBytes = model.fileSizeBytes > 0 ? model.fileSizeBytes : 0;

    // Best-effort notification permission.
    try {
      await FileDownloader().permissions
          .request(PermissionType.notifications)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => PermissionStatus.requestError,
          );
    } catch (_) {}

    var task = await FileDownloader().taskForId(updateTaskId);
    if (task == null) {
      task = DownloadTask(
        taskId: updateTaskId,
        url: model.sourceUrl!,
        filename: updateInstallName,
        directory: _storageDirName,
        baseDirectory: BaseDirectory.applicationSupport,
        headers: {
          if (token != null && token.isNotEmpty)
            HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        allowPause: true,
        retries: 3,
        updates: Updates.statusAndProgress,
        group: 'localmind_litert_downloads',
        displayName: '${model.name} (update)',
      );
    }
    _activeLitertTasks[modelId] = task as DownloadTask;

    var lastReceived = 0;
    final result = await FileDownloader().download(
      task,
      onProgress: (progress) {
        final clamped = progress.clamp(0.0, 1.0);
        if (totalBytes > 0) {
          final received = (clamped * totalBytes).round().clamp(0, totalBytes);
          if (received >= lastReceived) {
            lastReceived = received;
            onProgress?.call(received, totalBytes);
          }
        } else {
          onProgress?.call((clamped * 100).round().clamp(0, 100), 100);
        }
      },
    );

    if (result.status == TaskStatus.paused) {
      return TaskStatus.paused;
    }
    if (result.status == TaskStatus.canceled) {
      _activeLitertTasks.remove(modelId);
      await FileDownloader().database.deleteRecordWithId(updateTaskId);
      if (operations != null && operationId != null) {
        await operations!.fail(operationId);
      }
      throw const HttpException('LiteRT update canceled.');
    }
    if (result.status != TaskStatus.complete) {
      _activeLitertTasks.remove(modelId);
      await FileDownloader().database.deleteRecordWithId(updateTaskId);
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
        result.exception?.description ?? 'LiteRT update failed.',
      );
    }

    // Finalize: register new install, swap metadata, clean up old.
    if (operations != null && operationId != null) {
      await operations!.markPhase(operationId, DownloadOperationPhase.finalizing);
    }
    try {
      final status = await _finalizeLitertUpdate(
        modelId,
        task,
        updateInstallName,
        model,
        oldFilePath,
        oldInstallName,
      );
      await FileDownloader().database.deleteRecordWithId(updateTaskId);
      if (operations != null && operationId != null) {
        await operations!.complete(operationId);
      }
      return status;
    } catch (e) {
      _activeLitertTasks.remove(modelId);
      await FileDownloader().database.deleteRecordWithId(updateTaskId);
      if (operations != null && operationId != null) {
        await operations!.fail(operationId);
      }
      // Clean up temp file.
      try {
        final tempPath = await task.filePath();
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      rethrow;
    }
  }

  Future<TaskStatus> _finalizeLitertUpdate(
    String modelId,
    DownloadTask task,
    String installName,
    ImportedLitertModelMetadata oldModel,
    String? oldFilePath,
    String oldInstallName,
  ) async {
    final filePath = await task.filePath();
    final file = File(filePath);
    if (!await file.exists() || await file.length() <= 0) {
      throw const FileSystemException('The downloaded LiteRT file was empty or missing.');
    }

    // Register new install.
    final previousSpec = FlutterGemma.activeModelSpec;
    await FlutterGemma.installModel(
      modelType: ModelType.general,
      fileType: ModelFileType.litertlm,
    ).fromFile(filePath).install();
    final manager = FlutterGemmaPlugin.instance.modelManager;
    if (previousSpec != null) {
      manager.setActiveModel(previousSpec);
    } else {
      await FlutterGemma.clearActiveInferenceIdentity();
    }

    await _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((m) => m.id == modelId);
      if (index < 0) {
        // Model removed during download — don't overwrite.
        throw StateError('Model removed during update: $modelId');
      }
      // Revalidate revision: if the model's revision changed since update
      // started, abort to avoid clobbering newer metadata.
      if (models[index].revision != oldModel.revision) {
        Log.warning('Revision changed during update for $modelId; aborting finalization.');
        // Clean up the orphan install + temp file (best-effort).
        try { await FlutterGemma.uninstallModel(installName); } catch (_) {}
        try {
          final tp = await task.filePath();
          final tf = File(tp);
          if (await tf.exists()) await tf.delete();
        } catch (_) {}
        throw const HttpException('revision_changed');
      }
      // Update metadata FIRST (crash-safe: if save fails, old file is still intact).
      models[index] = models[index].copyWith(
        filePath: filePath,
        installFileName: installName,
        fileSizeBytes: await file.length(),
        revision: oldModel.latestRevision ?? oldModel.revision,
        fileOid: oldModel.latestFileOid ?? oldModel.fileOid,
        lastModified: oldModel.latestLastModified ?? oldModel.lastModified,
        latestFileOid: null,
        latestLastModified: null,
        updateAvailable: false,
        latestRevision: null,
        lastCheckedAt: DateTime.now(),
      );
      await _saveAllUnlocked(models);

        // THEN delete old install + file (best-effort; lingering old file is OK).
        if (oldInstallName != installName) {
          try {
            await FlutterGemma.uninstallModel(oldInstallName);
          } catch (_) {}
        }
        if (oldFilePath != null &&
            oldFilePath != filePath &&
            await File(oldFilePath).exists()) {
          try { await File(oldFilePath).delete(); } catch (_) {}
        }
    });

    _activeLitertTasks.remove(modelId);
    return TaskStatus.complete;
  }


  Future<TaskStatus> _finalizeLitertDownload(
    String modelId,
    DownloadTask task,
    String installName,
  ) async {
    _activeLitertTasks.remove(modelId);

    final filePath = await task.filePath();
    final file = File(filePath);
    if (!await file.exists() || await file.length() <= 0) {
      _activeLitertTasks.remove(modelId);
      throw const FileSystemException(
        'The downloaded LiteRT file was empty or missing.',
      );
    }

    final previousSpec = FlutterGemma.activeModelSpec;
    await FlutterGemma.installModel(
      modelType: ModelType.general,
      fileType: ModelFileType.litertlm,
    ).fromFile(filePath).install();
    final manager = FlutterGemmaPlugin.instance.modelManager;
    if (previousSpec != null) {
      manager.setActiveModel(previousSpec);
    } else {
      await FlutterGemma.clearActiveInferenceIdentity();
    }

    await _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((m) => m.id == modelId);
      if (index >= 0) {
        models[index] = models[index].copyWith(
          filePath: filePath,
          installFileName: installName,
          fileSizeBytes: await file.length(),
        );
        await _saveAllUnlocked(models);
      }
    });

    _activeLitertTasks.remove(modelId);
    return TaskStatus.complete;
  }

  Future<bool> pauseDownload(String modelId) async {
    // Pause every task sharing this id (handles duplicate WorkSpecs after
    // process death).
    final tasks = (await FileDownloader().allTasks(allGroups: true))
        .where((t) => t.taskId == modelId || t.taskId == '$modelId-update')
        .toList();
    if (tasks.isEmpty) {
      final t = _activeLitertTasks[modelId] ?? await FileDownloader().taskForId(modelId);
      if (t != null) tasks.add(t);
      final ut = await FileDownloader().taskForId('$modelId-update');
      if (ut != null) tasks.add(ut);
    }
    if (tasks.isEmpty) return false;
    bool any = false;
    for (final t in tasks) {
      _activeLitertTasks[modelId] = t;
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
    final modelIdx = models.indexWhere((m) => m.id == modelId);
    final totalBytes = (modelIdx >= 0 && models[modelIdx].fileSizeBytes > 0)
        ? models[modelIdx].fileSizeBytes
        : 0;
    final task =
        _activeLitertTasks[modelId] ??
        await FileDownloader().taskForId(modelId);
    if (task == null) {
      final st = await download(modelId, token: token, onProgress: onProgress);
      return st;
    }
    _activeLitertTasks[modelId] = task;

    // Subscribe BEFORE resume() so we capture every progress update.
    final completer = Completer<TaskStatus>();
    var lastReceived = 0;
    // Progress from the updates stream.
    final sub = FileDownloader().updates.listen((update) {
      if (update.task.taskId != modelId) return;
      if (update is TaskProgressUpdate) {
        final total = (update.hasExpectedFileSize && update.expectedFileSize > 0)
            ? update.expectedFileSize
            : totalBytes;
        if (total > 0 && onProgress != null) {
          final received = (update.progress.clamp(0.0, 1.0) * total).round();
          // Monotonic guard: ignore stale lower-progress updates from a
          // duplicate background task after process death.
          if (received >= lastReceived) {
            lastReceived = received;
            onProgress(received, total);
          }
        }
        if (update.progress >= 1.0 && !completer.isCompleted) {
          completer.complete(TaskStatus.complete);
        }
      } else if (update is TaskStatusUpdate) {
        if (update.status == TaskStatus.complete ||
            update.status == TaskStatus.canceled ||
            update.status == TaskStatus.failed ||
            update.status == TaskStatus.paused ||
            update.status == TaskStatus.notFound) {
          if (!completer.isCompleted) completer.complete(update.status);
        }
      }
    });

    final ok = await FileDownloader().resume(task as DownloadTask);
    if (!ok) {
      // resume() returns false if no resume data (task already running or
      // completed). Check DB status before deciding.
      await sub.cancel();
      TaskStatus? dbStatus;
      try {
        dbStatus = (await FileDownloader().database.recordForId(modelId))?.status;
      } catch (_) {}
      if (dbStatus == TaskStatus.paused) {
        // Paused but no resume data — retire stale attempt, start fresh.
        try { await FileDownloader().cancel(task as DownloadTask); } catch (_) {}
        try { await FileDownloader().database.deleteRecordWithId(modelId); } catch (_) {}
        final st = await download(modelId, token: token, onProgress: onProgress);
        return st;
      }
      // Running/enqueued/complete/unknown — attach (no enqueue).
      _activeLitertTasks[modelId] = task as DownloadTask;
      if (dbStatus == TaskStatus.complete) {
        return TaskStatus.complete;
      }
      // Wait for terminal via DB polling (longer timeout, no fabricated failure).
      TaskStatus status = TaskStatus.running;
      for (int i = 0; i < 300 && status == TaskStatus.running; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (completer.isCompleted) break;
        try {
          final s = (await FileDownloader().database.recordForId(modelId))?.status;
          if (s != null) status = s;
        } catch (_) {}
      }
      await sub.cancel();
      if (status == TaskStatus.complete) {
        if (onProgress != null && totalBytes > 0) onProgress(totalBytes, totalBytes);
        try {
          final t = _activeLitertTasks[modelId] ?? await FileDownloader().taskForId(modelId);
          if (t != null) {
            final models2 = load();
            final idx = models2.indexWhere((m) => m.id == modelId);
            final installName = (idx >= 0 ? models2[idx].installFileName : null) ?? modelId;
            await _finalizeLitertDownload(modelId, t as DownloadTask, installName);
          }
        } catch (_) {}
      } else if (status == TaskStatus.paused || status == TaskStatus.canceled || status == TaskStatus.failed) {
        _activeLitertTasks.remove(modelId);
      }
      return status == TaskStatus.running ? TaskStatus.paused : status;
    }

    TaskStatus status;
    try {
      status = await completer.future.timeout(const Duration(seconds: 120));
    } catch (_) {
      // Timeout is NOT a failure — keep the task alive.
      status = TaskStatus.running;
    }
    await sub.cancel();

    if (status == TaskStatus.complete) {
      if (onProgress != null && totalBytes > 0) onProgress(totalBytes, totalBytes);
      try {
        final t = _activeLitertTasks[modelId] ?? await FileDownloader().taskForId(modelId);
        if (t != null) {
          final models2 = load();
          final idx = models2.indexWhere((m) => m.id == modelId);
          final installName = (idx >= 0 ? models2[idx].installFileName : null) ?? modelId;
          await _finalizeLitertDownload(modelId, t as DownloadTask, installName);
        }
      } catch (_) {}
    } else if (status == TaskStatus.paused || status == TaskStatus.canceled || status == TaskStatus.failed) {
      _activeLitertTasks.remove(modelId);
    }
    return status == TaskStatus.running ? TaskStatus.paused : status;
  }

  Future<void> cancelDownload(String modelId) async {
    // Cancel both normal and update tasks.
    for (final taskId in [modelId, '$modelId-update']) {
      final tasks = (await FileDownloader().allTasks(allGroups: true))
          .where((t) => t.taskId == taskId)
          .toList();
      if (tasks.isEmpty) {
        final t = _activeLitertTasks[modelId] ?? await FileDownloader().taskForId(taskId);
        if (t != null) tasks.add(t);
      }
      for (final t in tasks) {
        try { await FileDownloader().cancel(t); } catch (_) {}
      }
      await FileDownloader().cancelTaskWithId(taskId);
    }
    _activeLitertTasks.remove(modelId);
    // Clean up partial update temp file (best-effort).
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
    await cancelDownload(modelId);

    await _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((model) => model.id == modelId);
      if (index < 0) {
        throw StateError('Imported LiteRT model no longer exists');
      }

      final model = models[index];
      final shared = models.where(
        (other) => other.id != model.id && other.fileName == model.fileName,
      );
      if (shared.isEmpty) {
        try {
          await FlutterGemma.uninstallModel(model.fileName);
        } catch (_) {
          // The file may already be absent; metadata cleanup still matters.
        }

        if (model.filePath != null && model.filePath!.isNotEmpty) {
          final file = File(model.filePath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      models[index] = model.copyWith(filePath: null);
      await _saveAllUnlocked(models);
    });
  }

  Future<void> removeFromList(String modelId) {
    return _mutex.run(() async {
      final current = load();
      final kept = current.where((model) => model.id != modelId).toList();
      await _saveAllUnlocked(kept);
    });
  }

  Future<void> delete(String modelId) async {
    await cancelDownload(modelId);
    await _mutex.run(() async {
      final models = load();
      final kept = <ImportedLitertModelMetadata>[];

      for (final model in models) {
        if (model.id == modelId) {
          final shared = models.where(
            (other) => other.id != model.id && other.fileName == model.fileName,
          );
          if (shared.isEmpty) {
            try {
              await FlutterGemma.uninstallModel(model.fileName);
            } catch (_) {}
            if (model.filePath != null) {
              final file = File(model.filePath!);
              if (await file.exists()) {
                await file.delete();
              }
            }
          }
        } else {
          kept.add(model);
        }
      }

      await _saveAllUnlocked(kept);
    });
  }

  Future<void> updateReasoning(String modelId, bool? enabled) {
    return _mutex.run(() async {
      final models = load();
      final index = models.indexWhere((model) => model.id == modelId);
      if (index < 0) throw StateError('Imported model no longer exists');
      models[index] = models[index].copyWith(reasoningEnabled: enabled);
      await _saveAllUnlocked(models);
    });
  }

  Uri _normalizeHuggingFaceLitertUrl(String input) {
    final normalizedUri = canonicalizeHuggingFaceUrl(
      input,
      emptyMessage: 'Enter a Hugging Face LiteRT URL.',
    );
    final fileName = _fileNameFromUri(normalizedUri);
    if (!fileName.toLowerCase().endsWith('.litertlm')) {
      throw const FormatException(
        'The Hugging Face URL must point directly to a .litertlm file.',
      );
    }
    return normalizedUri;
  }

  String _fileNameFromUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      throw const FormatException('Unable to determine the LiteRT file name.');
    }
    final fileName = Uri.decodeComponent(segments.last);
    if (!fileName.toLowerCase().endsWith('.litertlm')) {
      throw const FormatException('Unable to determine the LiteRT file name.');
    }
    return fileName;
  }

  String _createId(String fileName) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final suffix = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'litert-$micros-$suffix';
  }

  String _sanitizeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (sanitized.toLowerCase().endsWith('.litertlm')) return sanitized;
    return '$sanitized.litertlm';
  }

  String _displayNameFromFileName(String fileName) {
    final withoutExtension = fileName.replaceFirst(
      RegExp(r'\.litertlm$', caseSensitive: false),
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
