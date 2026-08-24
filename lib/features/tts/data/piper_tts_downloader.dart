import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'model_downloader.dart';
import 'piper_tts_model.dart';
import 'sherpa_bundle_downloader.dart';

class PiperTtsDownloader {
  final Dio _dio;
  final ModelDownloader _baseDownloader;
  final Map<PiperTtsModelVariant, CancelToken> _cancelTokens = {};

  PiperTtsDownloader() : _dio = Dio(), _baseDownloader = ModelDownloader();

  Future<Directory> _getEngineDir() async {
    final ttsDir = await _baseDownloader.getTtsDir();
    final dir = Directory('${ttsDir.path}/piper');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getVariantDir(PiperTtsModelVariant variant) async {
    final engineDir = await _getEngineDir();
    return Directory('${engineDir.path}/${variant.bundleDirName}');
  }

  Future<Set<PiperTtsModelVariant>> getDownloadedVariants() async {
    final downloaded = <PiperTtsModelVariant>{};
    for (final variant in PiperTtsModelVariant.values) {
      final dir = await _getVariantDir(variant);
      final modelFile = File('${dir.path}/${variant.modelFileName}');
      final tokensFile = File('${dir.path}/${variant.tokensFileName}');
      final dataDir = Directory('${dir.path}/${variant.dataDirName}');
      if (await modelFile.exists() &&
          await tokensFile.exists() &&
          await dataDir.exists()) {
        downloaded.add(variant);
      }
    }
    return downloaded;
  }

  Future<bool> isVariantDownloaded(PiperTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    return await File('${dir.path}/${variant.modelFileName}').exists() &&
        await File('${dir.path}/${variant.tokensFileName}').exists() &&
        await Directory('${dir.path}/${variant.dataDirName}').exists();
  }

  Stream<PiperTtsFileProgress> downloadModel(PiperTtsModelVariant variant) {
    return Stream<PiperTtsFileProgress>.multi((controller) async {
      final cancelToken = CancelToken();
      _cancelTokens[variant] = cancelToken;
      final engineDir = await _getEngineDir();
      await WakelockPlus.enable();

      try {
        final tempDir = await getTemporaryDirectory();
        final archivePath = '${tempDir.path}/${variant.bundleDirName}.tar.bz2';
        final archiveFile = File(archivePath);
        final fileName = '${variant.bundleDirName}.tar.bz2';

        controller.add(
          PiperTtsFileProgress(
            fileName: fileName,
            receivedBytes: 0,
            totalBytes: variant.totalSizeBytes,
            isComplete: false,
          ),
        );

        await _dio.download(
          variant.tarballUrl,
          archiveFile.path,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            final totalBytes = total > 0 ? total : variant.totalSizeBytes;
            controller.add(
              PiperTtsFileProgress(
                fileName: fileName,
                receivedBytes: received,
                totalBytes: totalBytes,
                isComplete: false,
              ),
            );
          },
        );

        if (cancelToken.isCancelled) {
          return;
        }

        await extractTarBz2(
          archivePath: archiveFile.path,
          targetDir: engineDir,
        );

        if (await archiveFile.exists()) {
          await archiveFile.delete();
        }

        controller.add(
          PiperTtsFileProgress(
            fileName: fileName,
            receivedBytes: variant.totalSizeBytes,
            totalBytes: variant.totalSizeBytes,
            isComplete: true,
          ),
        );
      } catch (e, st) {
        if (e is DioException && CancelToken.isCancel(e)) {
          // Ignore user cancellations.
        } else {
          controller.addError(e, st);
        }
      } finally {
        _cancelTokens.remove(variant);
        if (_cancelTokens.isEmpty) {
          await WakelockPlus.disable();
        }
        await controller.close();
      }
    });
  }

  void cancelDownload(PiperTtsModelVariant variant) {
    _cancelTokens[variant]?.cancel('User cancelled');
    _cancelTokens.remove(variant);
  }

  Future<void> deleteVariant(PiperTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    await deleteDirectoryIfExists(dir);
  }

  Future<String?> getModelPath(PiperTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    final file = File('${dir.path}/${variant.modelFileName}');
    if (await file.exists()) return file.path;
    return null;
  }

  Future<String?> getTokensPath(PiperTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    final file = File('${dir.path}/${variant.tokensFileName}');
    if (await file.exists()) return file.path;
    return null;
  }

  Future<Directory> getDataDir(PiperTtsModelVariant variant) async {
    return Directory(
      '${(await _getVariantDir(variant)).path}/${variant.dataDirName}',
    );
  }
}
