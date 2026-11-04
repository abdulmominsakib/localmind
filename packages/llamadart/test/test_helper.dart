import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

class TestHelper {
  static const String modelUrl =
      'https://huggingface.co/ggml-org/tiny-llamas/resolve/main/stories15M.gguf';
  static const String modelFileName = 'stories15M.gguf';
  static const String testModelsDirEnv = 'LLAMADART_TEST_MODELS_DIR';

  static Future<File> getTestModel() async {
    return ensureModel(modelUrl, modelFileName);
  }

  static Future<File> ensureModel(String url, String filename) async {
    final modelsDir = _modelsDir();
    if (!modelsDir.existsSync()) {
      modelsDir.createSync(recursive: true);
    }

    final modelFile = File(path.join(modelsDir.path, filename));
    if (modelFile.existsSync()) {
      return modelFile;
    }

    return _withDownloadLock(modelFile, () async {
      if (modelFile.existsSync()) {
        return modelFile;
      }

      print('Downloading model from $url...');
      await _downloadToFile(url, modelFile);
      print('Model downloaded to ${modelFile.path}');
      return modelFile;
    });
  }

  static Directory _modelsDir() {
    final configuredDir = Platform.environment[testModelsDirEnv];
    if (configuredDir != null && configuredDir.isNotEmpty) {
      return Directory(configuredDir);
    }
    return Directory(path.join(Directory.current.path, 'models'));
  }

  static Future<void> _downloadToFile(String url, File target) async {
    const maxAttempts = 5;
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http
            .get(Uri.parse(url), headers: _downloadHeaders(url))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode == 200) {
          final tempFile = File('${target.path}.tmp');
          await tempFile.writeAsBytes(response.bodyBytes, flush: true);
          await tempFile.rename(target.path);
          return;
        }

        lastError = 'HTTP ${response.statusCode}';
        if (!_shouldRetry(response.statusCode) || attempt == maxAttempts) {
          break;
        }
        await _waitBeforeRetry(response, attempt, lastError);
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt == maxAttempts) break;
        await _waitBeforeRetry(null, attempt, lastError);
      } on Exception catch (error) {
        lastError = error;
        if (attempt == maxAttempts) break;
        await _waitBeforeRetry(null, attempt, lastError);
      }
    }

    throw Exception(
      'Failed to download model from $url after $maxAttempts attempts: '
      '$lastError',
    );
  }

  static Future<T> _withDownloadLock<T>(
    File target,
    Future<T> Function() action,
  ) async {
    final lockFile = File('${target.path}.download.lock');
    var acquired = false;

    try {
      while (!acquired) {
        try {
          await lockFile.create(exclusive: true);
          acquired = true;
        } on FileSystemException {
          if (!await _deleteStaleLock(lockFile)) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      }

      return await action();
    } finally {
      if (acquired && lockFile.existsSync()) {
        await lockFile.delete();
      }
    }
  }

  static Future<bool> _deleteStaleLock(File lockFile) async {
    final stat = await lockFile.stat();
    if (stat.type != FileSystemEntityType.file) {
      return false;
    }

    final lockAge = DateTime.now().difference(stat.modified);
    if (lockAge < const Duration(minutes: 15)) {
      return false;
    }

    await lockFile.delete();
    return true;
  }

  static Map<String, String> _downloadHeaders(String url) {
    final uri = Uri.parse(url);
    final token = Platform.environment['HF_TOKEN'];
    if (uri.host.endsWith('huggingface.co') &&
        token != null &&
        token.isNotEmpty) {
      return {'Authorization': 'Bearer $token'};
    }
    return const {};
  }

  static bool _shouldRetry(int statusCode) {
    return statusCode == 408 ||
        statusCode == 429 ||
        (statusCode >= 500 && statusCode < 600);
  }

  static Future<void> _waitBeforeRetry(
    http.Response? response,
    int attempt,
    Object? lastError,
  ) async {
    final retryAfter = response?.headers['retry-after'];
    final retryAfterSeconds = int.tryParse(retryAfter ?? '');
    final seconds = retryAfterSeconds != null
        ? retryAfterSeconds.clamp(1, 60).toInt()
        : attempt * 3;
    print(
      'Model download failed ($lastError); retrying in ${seconds}s '
      '(attempt ${attempt + 1})...',
    );
    await Future<void>.delayed(Duration(seconds: seconds));
  }
}
