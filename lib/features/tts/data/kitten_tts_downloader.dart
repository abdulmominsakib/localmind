import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/logger/app_logger.dart';
import 'kitten_tts_model.dart';

/// Downloads KittenTTS model files (config.json, model.onnx, voices.npz)
/// from HuggingFace with resume support and per-file progress reporting.
class KittenTtsDownloader {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _activeDownloads = {};

  /// Returns the storage directory for a given variant.
  Future<Directory> _getVariantDir(KittenTtsModelVariant variant) async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/kitten_tts/${variant.dirName}');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Check whether all files for a variant have been downloaded.
  Future<bool> isVariantDownloaded(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    for (final file in variant.files) {
      final path = '${dir.path}/${file.fileName}';
      if (!await File(path).exists()) {
        return false;
      }
    }
    return true;
  }

  /// Get total downloaded bytes for a variant.
  Future<int> getDownloadedBytes(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    int total = 0;
    for (final file in variant.files) {
      final path = '${dir.path}/${file.fileName}';
      final f = File(path);
      if (await f.exists()) {
        total += await f.length();
      }
    }
    return total;
  }

  /// Download all files for [model], emitting per-file progress.
  Stream<KittenTtsFileProgress> downloadModel(KittenTtsModel model) async* {
    final variantId = model.variant.name;
    final dir = await _getVariantDir(model.variant);

    await WakelockPlus.enable();

    try {
      for (final file in model.files) {
        final cancelToken = CancelToken();
        _activeDownloads[variantId] = cancelToken;

        final filePath = '${dir.path}/${file.fileName}';
        final partialPath = '$filePath.part';
        final partialFile = File(partialPath);

        int receivedBytes = 0;

        if (await partialFile.exists()) {
          receivedBytes = await partialFile.length();
          Log.info(
            'Resuming KittenTTS ${model.variant.displayName} ${file.fileName} from $receivedBytes bytes',
          );
        }

        DateTime lastProgressUpdate = DateTime.now();

        try {
          final response = await _resolveWithRedirects(
            url: file.downloadUrl,
            startByte: receivedBytes,
            cancelToken: cancelToken,
          );

          final totalBytes = (response.headers.value(Headers.contentLengthHeader) != null)
              ? int.parse(response.headers.value(Headers.contentLengthHeader)!) + receivedBytes
              : file.sizeBytes;

          final IOSink sink = partialFile.openWrite(mode: FileMode.append);
          final stream = response.data?.stream;

          if (stream == null) {
            await sink.close();
            throw DioException(
              requestOptions: response.requestOptions,
              error: 'Response data stream is null',
            );
          }

          await for (final List<int> chunk in stream) {
            if (cancelToken.isCancelled) break;
            sink.add(chunk);
            receivedBytes += chunk.length;

            final now = DateTime.now();
            final elapsedSinceLastUpdate = now.difference(lastProgressUpdate);

            if (elapsedSinceLastUpdate.inMilliseconds >= 500) {
              yield KittenTtsFileProgress(
                fileName: file.fileName,
                variant: model.variant,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
              );

              lastProgressUpdate = now;
            }
          }

          await sink.flush();
          await sink.close();

          await partialFile.rename(filePath);
          Log.info(
            'KittenTTS ${model.variant.displayName} ${file.fileName} downloaded',
          );

          yield KittenTtsFileProgress(
            fileName: file.fileName,
            variant: model.variant,
            receivedBytes: receivedBytes,
            totalBytes: receivedBytes,
            isComplete: true,
          );
        } catch (e) {
          if (e is DioException && CancelToken.isCancel(e)) {
            Log.info('KittenTTS download cancelled for $variantId');
            return;
          }
          rethrow;
        }
      }
    } finally {
      _activeDownloads.remove(variantId);
      if (_activeDownloads.isEmpty) {
        await WakelockPlus.disable();
      }
    }
  }

  /// Cancel an in-flight download for [variantId].
  void cancelDownload(KittenTtsModelVariant variant) {
    _activeDownloads[variant.name]?.cancel();
  }

  /// Delete all files for a variant from disk.
  Future<void> deleteVariant(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    for (final file in variant.files) {
      final path = '${dir.path}/${file.fileName}';
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
      final partFile = File('$path.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }
    }
    if (await dir.exists()) {
      final entities = await dir.list().toList();
      if (entities.isEmpty) {
        await dir.delete();
      }
    }
    Log.info('KittenTTS variant ${variant.displayName} deleted');
  }

  /// Get list of downloaded variants.
  Future<Set<KittenTtsModelVariant>> getDownloadedVariants() async {
    final result = <KittenTtsModelVariant>{};
    for (final variant in KittenTtsModelVariant.values) {
      if (await isVariantDownloaded(variant)) {
        result.add(variant);
      }
    }
    return result;
  }

  /// Get the absolute file path for a variant's file.
  Future<String?> getFilePath(
    KittenTtsModelVariant variant,
    String fileName,
  ) async {
    final dir = await _getVariantDir(variant);
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// Manually follows redirects to ensure Authorization header safety.
  Future<Response<ResponseBody>> _resolveWithRedirects({
    required String url,
    required int startByte,
    required CancelToken cancelToken,
  }) async {
    String currentUrl = url;
    final Uri originalUri = Uri.parse(url);

    for (int hop = 0; hop < 5; hop++) {
      final options = Options(
        responseType: ResponseType.stream,
        followRedirects: false,
        validateStatus: (status) => status != null && status < 500,
        headers: {
          if (startByte > 0) 'Range': 'bytes=$startByte-',
        },
      );

      final currentUri = Uri.parse(currentUrl);
      if (currentUri.host != originalUri.host) {
        options.headers?.remove('Authorization');
      }

      final response = await _dio.get<ResponseBody>(
        currentUrl,
        options: options,
        cancelToken: cancelToken,
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        return response;
      }

      if (response.statusCode! >= 300 && response.statusCode! < 400) {
        final location = response.headers.value('location');
        if (location == null) {
          throw DioException(
            requestOptions: response.requestOptions,
            error: 'Redirect without location header',
          );
        }
        currentUrl = Uri.parse(currentUrl).resolve(location).toString();
        continue;
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        error: 'Server returned ${response.statusCode}',
      );
    }

    throw DioException(
      requestOptions: RequestOptions(path: url),
      error: 'Too many redirects',
    );
  }
}
