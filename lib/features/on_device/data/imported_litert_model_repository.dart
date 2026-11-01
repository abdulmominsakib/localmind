import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/on_device_model.dart';

class ImportedLitertModelMetadata {
  static const _unset = Object();

  final String id;
  final String name;
  final String? filePath;
  final String? sourceUrl;
  final int fileSizeBytes;
  final DateTime importedAt;
  final OnDeviceImportedSource source;
  final String? projectorPath;
  final bool? reasoningEnabled;

  const ImportedLitertModelMetadata({
    required this.id,
    required this.name,
    this.filePath,
    this.sourceUrl,
    required this.fileSizeBytes,
    required this.importedAt,
    required this.source,
    this.projectorPath,
    this.reasoningEnabled,
  });

  String get fileName {
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
    Object? sourceUrl = _unset,
    int? fileSizeBytes,
    DateTime? importedAt,
    OnDeviceImportedSource? source,
    Object? projectorPath = _unset,
    bool? reasoningEnabled,
  }) {
    return ImportedLitertModelMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      filePath: identical(filePath, _unset)
          ? this.filePath
          : filePath as String?,
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
    );
  }

  OnDeviceModel toOnDeviceModel() {
    final isHuggingFace = source == OnDeviceImportedSource.huggingFace;
    return OnDeviceModel(
      id: id,
      name: name,
      huggingFaceUrl: isHuggingFace ? (sourceUrl ?? '') : '',
      fileSizeBytes: fileSizeBytes,
      license: sourceLabel,
      description: isHuggingFace
          ? 'Imported LiteRT model from Hugging Face for on-device Gemma inference.'
          : 'Imported LiteRT model from a local file for on-device Gemma inference.',
      minRamMb: 2048,
      parameterLabel: 'LiteRT',
      bestFor: 'Local LiteRT inference',
      languagesLabel: 'Local',
      backendNote: 'LiteRT',
      runtime: OnDeviceModelRuntime.gemma,
      format: OnDeviceModelFormat.litertlm,
      localPath: filePath,
      projectorPath: projectorPath,
      supportsVision: projectorPath != null && projectorPath!.isNotEmpty,
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
      'sourceUrl': sourceUrl,
      'fileSizeBytes': fileSizeBytes,
      'importedAt': importedAt.toIso8601String(),
      'source': source.name,
      'projectorPath': projectorPath,
      'reasoningEnabled': reasoningEnabled,
    };
  }

  factory ImportedLitertModelMetadata.fromJson(Map<String, dynamic> json) {
    return ImportedLitertModelMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      filePath: json['filePath'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      importedAt: DateTime.parse(json['importedAt'] as String),
      source: _sourceFromJson(json['source']),
      projectorPath: json['projectorPath'] as String?,
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

class ImportedLitertModelRepository {
  static const _storageKey = 'imported_litert_models_v1';
  static const _storageDirName = 'imported_litert_models';

  final SharedPreferences _prefs;
  final Dio _dio;
  final Random _random;
  final Future<Directory> Function()? modelsDirectoryProvider;

  ImportedLitertModelRepository(
    this._prefs,
    this._dio, {
    Random? random,
    this.modelsDirectoryProvider,
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

  Future<void> saveAll(List<ImportedLitertModelMetadata> models) async {
    final encoded = json.encode(models.map((m) => m.toJson()).toList());
    if (!await _prefs.setString(_storageKey, encoded)) {
      throw StateError('Could not save imported LiteRT models');
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
    final models = load();
    final existing = <ImportedLitertModelMetadata>[];
    var hasChanges = false;

    for (final model in models) {
      if (model.filePath == null || model.filePath!.isEmpty) {
        existing.add(model);
        continue;
      }
      if (await File(model.filePath!).exists()) {
        existing.add(model);
      } else {
        hasChanges = true;
      }
    }

    if (hasChanges || existing.length != models.length) {
      await saveAll(existing);
    }

    return existing;
  }

  Future<ImportedLitertModelMetadata> addFromPath(String sourcePath) async {
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
      return existing.first;
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
        sourceUrl: null,
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
      rethrow;
    }
  }

  Future<ImportedLitertModelMetadata> addFromUrl(
    String sourceUrl, {
    String? token,
  }) async {
    final normalizedUrl = _normalizeHuggingFaceLitertUrl(sourceUrl);
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

    final metadata = ImportedLitertModelMetadata(
      id: id,
      name: _displayNameFromFileName(originalName),
      filePath: null,
      sourceUrl: normalizedUrl.toString(),
      fileSizeBytes: fileSizeBytes,
      importedAt: DateTime.now(),
      source: OnDeviceImportedSource.huggingFace,
    );

    final current = load();
    await saveAll([...current, metadata]);
    return metadata;
  }

  Future<void> download(
    String modelId, {
    String? token,
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final models = load();
    final index = models.indexWhere((model) => model.id == modelId);
    if (index < 0) {
      throw StateError('Imported LiteRT model no longer exists');
    }

    final model = models[index];
    if (model.filePath != null && model.filePath!.isNotEmpty) {
      await FlutterGemma.installModel(
        modelType: ModelType.general,
        fileType: ModelFileType.litertlm,
      ).fromFile(model.filePath!).install();
      return;
    }

    if (model.sourceUrl == null || model.sourceUrl!.isEmpty) {
      throw const FormatException('Imported LiteRT model has no source URL.');
    }

    await FlutterGemma.installModel(
      modelType: ModelType.general,
      fileType: ModelFileType.litertlm,
    ).fromNetwork(model.sourceUrl!, token: token).withProgress((progress) {
      final total = model.fileSizeBytes > 0 ? model.fileSizeBytes : 100;
      final received = model.fileSizeBytes > 0
          ? ((progress / 100.0) * total).round()
          : progress;
      onProgress?.call(received, total);
    }).install();
  }

  Future<void> deleteFile(String modelId) async {
    final models = load();
    final index = models.indexWhere((model) => model.id == modelId);
    if (index < 0) {
      throw StateError('Imported LiteRT model no longer exists');
    }

    final model = models[index];
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

    models[index] = model.copyWith(filePath: null);
    await saveAll(models);
  }

  Future<void> removeFromList(String modelId) async {
    final current = load();
    final kept = current.where((model) => model.id != modelId).toList();
    await saveAll(kept);
  }

  Future<void> delete(String modelId) async {
    final models = load();
    final kept = <ImportedLitertModelMetadata>[];

    for (final model in models) {
      if (model.id == modelId) {
        try {
          await FlutterGemma.uninstallModel(model.fileName);
        } catch (_) {}
        if (model.filePath != null) {
          final file = File(model.filePath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
      } else {
        kept.add(model);
      }
    }

    await saveAll(kept);
  }

  Future<void> updateReasoning(String modelId, bool? enabled) async {
    final models = load();
    final index = models.indexWhere((model) => model.id == modelId);
    if (index < 0) throw StateError('Imported model no longer exists');
    models[index] = models[index].copyWith(reasoningEnabled: enabled);
    await saveAll(models);
  }

  Uri _normalizeHuggingFaceLitertUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Enter a Hugging Face LiteRT URL.');
    }

    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'https://huggingface.co/$trimmed';

    final uri = Uri.parse(withScheme);
    final host = uri.host.toLowerCase();
    if (host != 'huggingface.co' &&
        host != 'www.huggingface.co' &&
        host != 'hf.co') {
      throw const FormatException(
        'Only official Hugging Face LiteRT URLs are supported.',
      );
    }

    if (uri.scheme.toLowerCase() != 'https') {
      throw const FormatException(
        'Use an HTTPS Hugging Face URL for LiteRT import.',
      );
    }

    final normalizedSegments = [...uri.pathSegments];
    final blobIndex = normalizedSegments.indexOf('blob');
    if (blobIndex != -1) {
      normalizedSegments[blobIndex] = 'resolve';
    }

    final normalizedUri = uri.replace(pathSegments: normalizedSegments);
    final fileName = _fileNameFromUri(normalizedUri);
    if (!fileName.toLowerCase().endsWith('.litertlm')) {
      throw const FormatException(
        'The Hugging Face URL must point directly to a .litertlm file.',
      );
    }
    return normalizedUri;
  }

  String _fileNameFromUri(Uri uri) {
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
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