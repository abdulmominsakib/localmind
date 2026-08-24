import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/logger/app_logger.dart';
import 'kitten_tts_model.dart';
import 'sherpa_bundle_downloader.dart';

/// Downloads sherpa-onnx Kitten TTS bundles.
class KittenTtsDownloader {
  final Dio _dio = Dio();
  final Map<String, CancelToken> _activeDownloads = {};

  Future<Directory> _getEngineDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}/tts_models/kitten');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getVariantDir(KittenTtsModelVariant variant) async {
    final engineDir = await _getEngineDir();
    return Directory('${engineDir.path}/${variant.bundleDirName}');
  }

  Future<bool> isVariantDownloaded(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    return await File('${dir.path}/${variant.modelFileName}').exists() &&
        await File('${dir.path}/${variant.voicesFileName}').exists() &&
        await File('${dir.path}/${variant.tokensFileName}').exists() &&
        await Directory('${dir.path}/${variant.dataDirName}').exists();
  }

  Stream<KittenTtsFileProgress> downloadModel(KittenTtsModel model) {
    final variant = model.variant;
    final variantKey = variant.name;

    return Stream<KittenTtsFileProgress>.multi((controller) async {
      final engineDir = await _getEngineDir();
      final variantDir = await _getVariantDir(variant);
      await variantDir.parent.create(recursive: true);

      await WakelockPlus.enable();

      try {
        final cancelToken = CancelToken();
        _activeDownloads[variantKey] = cancelToken;

        final tempDir = await getTemporaryDirectory();
        final archivePath = '${tempDir.path}/${variant.bundleDirName}.tar.bz2';
        final archiveFile = File(archivePath);
        final fileName = '${variant.bundleDirName}.tar.bz2';

        controller.add(
          KittenTtsFileProgress(
            fileName: fileName,
            variant: variant,
            receivedBytes: 0,
            totalBytes: model.totalSizeBytes,
            isComplete: false,
          ),
        );

        await _dio.download(
          variant.tarballUrl,
          archiveFile.path,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            final totalBytes = total > 0 ? total : model.totalSizeBytes;
            controller.add(
              KittenTtsFileProgress(
                fileName: fileName,
                variant: variant,
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
          KittenTtsFileProgress(
            fileName: fileName,
            variant: variant,
            receivedBytes: model.totalSizeBytes,
            totalBytes: model.totalSizeBytes,
            isComplete: true,
          ),
        );
        Log.info('Kitten ${variant.displayName} downloaded');
      } catch (e, st) {
        if (e is DioException && CancelToken.isCancel(e)) {
          Log.info('Kitten download cancelled for $variantKey');
        } else {
          controller.addError(e, st);
        }
      } finally {
        _activeDownloads.remove(variantKey);
        if (_activeDownloads.isEmpty) {
          await WakelockPlus.disable();
        }
        await controller.close();
      }
    });
  }

  void cancelDownload(KittenTtsModelVariant variant) {
    _activeDownloads[variant.name]?.cancel();
  }

  Future<void> deleteVariant(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    await deleteDirectoryIfExists(dir);
    Log.info('KittenTTS variant ${variant.displayName} deleted');
  }

  Future<Set<KittenTtsModelVariant>> getDownloadedVariants() async {
    final result = <KittenTtsModelVariant>{};
    for (final variant in KittenTtsModelVariant.values) {
      if (await isVariantDownloaded(variant)) {
        result.add(variant);
      }
    }
    return result;
  }

  Future<String?> getModelPath(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    final file = File('${dir.path}/${variant.modelFileName}');
    if (await file.exists()) return file.path;
    return null;
  }

  Future<String?> getVoicesPath(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    final file = File('${dir.path}/${variant.voicesFileName}');
    if (await file.exists()) return file.path;
    return null;
  }

  Future<String?> getTokensPath(KittenTtsModelVariant variant) async {
    final dir = await _getVariantDir(variant);
    final file = File('${dir.path}/${variant.tokensFileName}');
    if (await file.exists()) return file.path;
    return null;
  }

  Future<Directory> getDataDir(KittenTtsModelVariant variant) async {
    return Directory(
      '${(await _getVariantDir(variant)).path}/${variant.dataDirName}',
    );
  }
}
