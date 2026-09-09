import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/on_device_model.dart';

class ImportedGgufModelMetadata {
  final String id;
  final String name;
  final String filePath;
  final int fileSizeBytes;
  final DateTime importedAt;
  final OnDeviceImportedSource source;
  final String? sourceUrl;
  final bool? reasoningEnabled;

  const ImportedGgufModelMetadata({
    required this.id,
    required this.name,
    required this.filePath,
    required this.fileSizeBytes,
    required this.importedAt,
    required this.source,
    this.sourceUrl,
    this.reasoningEnabled,
  });

  String get fileName => p.basename(filePath);

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

  OnDeviceModel toOnDeviceModel() {
    final isHuggingFace = source == OnDeviceImportedSource.huggingFace;
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

  Future<List<ImportedGgufModelMetadata>> loadExisting() async {
    final models = load();
    final existing = <ImportedGgufModelMetadata>[];

    for (final model in models) {
      if (await File(model.filePath).exists()) {
        existing.add(model);
      }
    }

    if (existing.length != models.length) {
      await saveAll(existing);
    }

    return existing;
  }

  Future<ImportedGgufModelMetadata> importFromPath(String sourcePath) async {
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

    final dir = await _modelsDirectory();
    final originalName = p.basename(sourcePath);
    final id = _createId(originalName);
    final fileName = '$id-${_sanitizeFileName(originalName)}';
    final target = File(p.join(dir.path, fileName));

    try {
      await source.copy(target.path);
      await _validateGgufFile(target);

      final metadata = ImportedGgufModelMetadata(
        id: id,
        name: _displayNameFromFileName(originalName),
        filePath: target.path,
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

  Future<ImportedGgufModelMetadata> importFromHuggingFaceUrl(
    String sourceUrl, {
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

      final metadata = ImportedGgufModelMetadata(
        id: id,
        name: _displayNameFromFileName(originalName),
        filePath: targetFile.path,
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
