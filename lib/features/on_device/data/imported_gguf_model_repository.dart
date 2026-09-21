import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class ImportedGgufModelRepository {
  static const _storageKey = 'imported_gguf_models_v1';
  static const _storageDirName = 'imported_gguf_models';

  final SharedPreferences _prefs;
  final Dio _dio;
  final Random _random;

  ImportedGgufModelRepository(this._prefs, this._dio, {Random? random})
    : _random = random ?? Random.secure();

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
              .where((f) =>
                  f.path.toLowerCase().endsWith('.gguf') &&
                  isProjectorFileName(p.basename(f.path)))
              .toList();
          if (candidates.isNotEmpty) {
            final modelBase =
                p.basenameWithoutExtension(sourcePath).toLowerCase();
            final match = candidates.firstWhere(
              (c) {
                final cName =
                    p.basenameWithoutExtension(c.path).toLowerCase();
                final sharedTokens = modelBase
                    .split(RegExp(r'[-_.]'))
                    .where((t) => t.length > 2);
                return sharedTokens.any((t) => cName.contains(t));
              },
              orElse: () => candidates.first,
            );
            resolvedProjectorPath = match.path;
          }
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

    final results = <ImportedGgufModelMetadata>[];
    if (models.length == 1 && projectors.isNotEmpty) {
      results.add(
        await importFromPath(models.single, projectorPath: projectors.first),
      );
      return results;
    }

    for (final modelPath in models) {
      final modelBase = p.basenameWithoutExtension(modelPath).toLowerCase();
      final matchingProjector = projectors.cast<String?>().firstWhere(
        (projPath) {
          if (projPath == null) return false;
          final projBase =
              p.basenameWithoutExtension(projPath).toLowerCase();
          final sharedTokens = modelBase
              .split(RegExp(r'[-_.]'))
              .where((t) => t.length > 2);
          return sharedTokens.any((t) => projBase.contains(t));
        },
        orElse: () => null,
      );

      results.add(
        await importFromPath(modelPath, projectorPath: matchingProjector),
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
      throw const FormatException(
        'Only GGUF projector files are supported.',
      );
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
        '$modelId-mmproj-${_sanitizeFileName(projOriginalName)}';
    final targetProjector = File(p.join(dir.path, projFileName));

    try {
      await projSource.copy(targetProjector.path);
      await _validateGgufFile(targetProjector);

      final oldProjPath = models[index].projectorPath;
      if (oldProjPath != null && oldProjPath != targetProjector.path) {
        final oldProj = File(oldProjPath);
        if (await oldProj.exists() && p.isWithin(dir.path, oldProj.path)) {
          await oldProj.delete();
        }
      }

      final updated = models[index].copyWith(
        projectorPath: targetProjector.path,
      );
      models[index] = updated;
      await saveAll(models);
      return updated;
    } catch (_) {
      if (await targetProjector.exists()) {
        await targetProjector.delete();
      }
      rethrow;
    }
  }

  Future<ImportedGgufModelMetadata> removeProjector(String modelId) async {
    final models = load();
    final index = models.indexWhere((m) => m.id == modelId);
    if (index < 0) {
      throw StateError('Imported model no longer exists');
    }

    final dir = await _modelsDirectory();
    final oldProjPath = models[index].projectorPath;
    if (oldProjPath != null) {
      final oldProj = File(oldProjPath);
      if (await oldProj.exists() && p.isWithin(dir.path, oldProj.path)) {
        await oldProj.delete();
      }
    }

    final updated = models[index].copyWith(projectorPath: null);
    models[index] = updated;
    await saveAll(models);
    return updated;
  }

  Future<ImportedGgufModelMetadata> importFromHuggingFaceUrl(
    String sourceUrl, {
    String? projectorUrl,
    String? token,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final normalizedUrl = _normalizeHuggingFaceGgufUrl(sourceUrl);
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
        final normalizedProjUrl =
            _normalizeHuggingFaceGgufUrl(projectorUrl.trim());
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

      final metadata = ImportedGgufModelMetadata(
        id: id,
        name: _displayNameFromFileName(originalName),
        filePath: targetFile.path,
        projectorPath: targetProjectorFile?.path,
        fileSizeBytes: await targetFile.length(),
        importedAt: DateTime.now(),
        source: OnDeviceImportedSource.huggingFace,
        sourceUrl: normalizedUrl.toString(),
      );

      final current = load();
      await saveAll([...current, metadata]);
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
    }
  }

  Future<void> delete(String id) async {
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
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(supportDir.path, _storageDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
