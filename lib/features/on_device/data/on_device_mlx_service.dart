import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apple_mlx/apple_mlx.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import '../../servers/data/models/server.dart';
import '../../chat/data/models/chat_parameters.dart';
import '../../chat/data/models/message.dart';
import '../../chat/data/models/mcp_integration.dart';
import '../../chat/data/tools/tool_definition.dart';
import '../../chat/data/chat_service.dart';
import 'models/on_device_model.dart';

class OnDeviceMlxService {
  OnDeviceMlxService(
    this._dio, {
    this.modelsDirectoryProvider,
    AppleMlxLlmManager Function()? llmManagerFactory,
    bool? nativeInferenceAvailable,
    bool? isIOS,
  }) : _llmManagerFactory = llmManagerFactory ?? AppleMlxLlmManager.new,
       _nativeInferenceAvailable =
           nativeInferenceAvailable ??
           AppleMlxCapabilities.nativeLlmInferenceAvailable,
       _isIOS = isIOS ?? Platform.isIOS;

  static const String _downloadCompleteFileName = '.download_complete';

  final Dio _dio;
  final Future<Directory> Function()? modelsDirectoryProvider;
  final AppleMlxLlmManager Function() _llmManagerFactory;
  final bool _nativeInferenceAvailable;
  final bool _isIOS;
  AppleMlxLlmManager? _llmManager;
  String? _currentModelId;
  bool _currentModelSupportsThinking = false;
  bool _isDisposed = false;
  final Map<String, CancelToken> _activeDownloads = {};

  String? get currentModelId => _currentModelId;
  bool get isLoaded => _llmManager?.isModelLoaded == true && !_isDisposed;

  /// Returns the base directory where MLX models are stored.
  Future<Directory> get _modelsDirectory async {
    final override = modelsDirectoryProvider;
    final mlxDir = override != null
        ? await override()
        : Directory(
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              'models',
              'mlx',
            ),
          );
    if (!await mlxDir.exists()) {
      await mlxDir.create(recursive: true);
    }
    return mlxDir;
  }

  /// Returns the specific directory for a model.
  Future<Directory> getModelDirectory(String modelId) async {
    final base = await _modelsDirectory;
    final sanitized = modelId.replaceAll('/', '_');
    return Directory(p.join(base.path, sanitized));
  }

  /// Checks if a model is fully downloaded and installed.
  Future<bool> isModelInstalled(String modelId) async {
    try {
      final dir = await getModelDirectory(modelId);
      if (!await dir.exists()) return false;

      final completionMarker = File(
        p.join(dir.path, _downloadCompleteFileName),
      );
      if (!await completionMarker.exists()) return false;

      final markerData = jsonDecode(await completionMarker.readAsString());
      if (markerData is! Map || markerData['files'] is! List) return false;
      final manifestFiles = (markerData['files'] as List)
          .whereType<String>()
          .toList(growable: false);
      if (manifestFiles.isEmpty) return false;

      for (final relativePath in manifestFiles) {
        final filePath = p.normalize(p.join(dir.path, relativePath));
        if (!p.isWithin(dir.path, filePath) || !await File(filePath).exists()) {
          return false;
        }
      }

      final config = File(p.join(dir.path, 'config.json'));
      if (!await config.exists()) return false;

      final hasWeights = manifestFiles.any(
        (path) =>
            path.endsWith('.safetensors') ||
            path.endsWith('.npz') ||
            path.endsWith('.bin'),
      );
      return hasWeights;
    } catch (e) {
      Log.error('Error checking MLX model installation for $modelId: $e');
      return false;
    }
  }

  /// Returns a set of installed MLX model IDs.
  Future<Set<String>> getInstalledModelIds() async {
    if (!_nativeInferenceAvailable || !_isIOS) {
      return const <String>{};
    }
    try {
      final base = await _modelsDirectory;
      if (!await base.exists()) return const <String>{};

      final installed = <String>{};
      final curated = OnDeviceModel.curatedMlxModels;

      for (final model in curated) {
        if (await isModelInstalled(model.id)) {
          installed.add(model.id);
        }
      }
      return installed;
    } catch (e) {
      Log.error('Error listing installed MLX models: $e');
      return const <String>{};
    }
  }

  /// Downloads all required files of an MLX model from Hugging Face.
  Future<void> downloadModel(
    OnDeviceModel model, {
    String? huggingFaceToken,
    void Function(int receivedBytes, int totalBytes)? onProgress,
    CancelToken? cancelToken,
  }) async {
    _ensureNativeInferenceAvailable();
    if (!_isIOS) {
      throw UnsupportedError(
        'Apple MLX text generation is only supported on iOS.',
      );
    }
    if (model.runtime != OnDeviceModelRuntime.mlx) {
      throw ArgumentError.value(
        model.runtime,
        'model.runtime',
        'Expected an Apple MLX model',
      );
    }

    final targetDir = await getModelDirectory(model.id);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final completionMarker = File(
      p.join(targetDir.path, _downloadCompleteFileName),
    );
    if (await completionMarker.exists()) {
      await completionMarker.delete();
    }

    // Extract repo ID from huggingFaceUrl if needed
    final repoId = _extractRepoId(model.huggingFaceUrl);
    final effectiveCancelToken = cancelToken ?? CancelToken();
    _activeDownloads[model.id] = effectiveCancelToken;

    try {
      Log.info('Fetching MLX model file list for $repoId from Hugging Face...');

      final headers = <String, dynamic>{
        if (huggingFaceToken != null && huggingFaceToken.isNotEmpty)
          'Authorization': 'Bearer $huggingFaceToken',
      };

      // 1. Fetch file list from Hugging Face API
      final apiUrl =
          'https://huggingface.co/api/models/$repoId/tree/main?recursive=true';
      List<String> filesToDownload = [];
      int totalModelBytes = model.fileSizeBytes;

      try {
        final res = await _dio.get<List<dynamic>>(
          apiUrl,
          options: Options(headers: headers),
          cancelToken: effectiveCancelToken,
        );
        if (res.data != null) {
          int computedTotal = 0;
          for (final item in res.data!) {
            if (item is Map) {
              final path = item['path'] as String?;
              final type = item['type'] as String?;
              final size = (item['size'] as num?)?.toInt() ?? 0;
              if (type == 'file' && path != null && !_shouldSkipFile(path)) {
                filesToDownload.add(path);
                computedTotal += size;
              }
            }
          }
          if (computedTotal > 0) {
            totalModelBytes = computedTotal;
          }
        }
      } catch (e) {
        Log.warning(
          'Could not fetch Hugging Face file tree ($e). Using default MLX file list.',
        );
        filesToDownload = [
          'config.json',
          'model.safetensors',
          'tokenizer.json',
          'tokenizer_config.json',
          'special_tokens_map.json',
        ];
      }

      if (filesToDownload.isEmpty) {
        filesToDownload = [
          'config.json',
          'model.safetensors',
          'tokenizer.json',
          'tokenizer_config.json',
        ];
      }

      int cumulativeDownloaded = 0;
      final fileSizes = <String, int>{};

      for (final fileName in filesToDownload) {
        if (effectiveCancelToken.isCancelled) {
          throw StateError('MLX model download was cancelled.');
        }

        final fileUrl = 'https://huggingface.co/$repoId/resolve/main/$fileName';
        final savePath = p.normalize(p.join(targetDir.path, fileName));
        if (!p.isWithin(targetDir.path, savePath)) {
          throw StateError('Invalid model file path returned by Hugging Face.');
        }
        final parent = Directory(p.dirname(savePath));
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        int fileDownloadedBefore = fileSizes[fileName] ?? 0;

        await _dio.download(
          fileUrl,
          savePath,
          options: Options(headers: headers),
          cancelToken: effectiveCancelToken,
          onReceiveProgress: (received, total) {
            final delta = received - fileDownloadedBefore;
            fileDownloadedBefore = received;
            fileSizes[fileName] = received;
            cumulativeDownloaded += delta;

            onProgress?.call(
              cumulativeDownloaded,
              totalModelBytes > 0 ? totalModelBytes : cumulativeDownloaded,
            );
          },
        );
      }

      if (effectiveCancelToken.isCancelled) {
        throw StateError('MLX model download was cancelled.');
      }
      for (final fileName in filesToDownload) {
        if (!await File(p.join(targetDir.path, fileName)).exists()) {
          throw StateError('MLX model download is missing $fileName.');
        }
      }
      await completionMarker.writeAsString(
        jsonEncode({'repository': repoId, 'files': filesToDownload}),
        flush: true,
      );
      onProgress?.call(totalModelBytes, totalModelBytes);

      Log.info(
        'MLX model ${model.id} successfully downloaded to ${targetDir.path}',
      );
    } catch (e) {
      Log.error('Failed to download MLX model ${model.id}: $e');
      rethrow;
    } finally {
      _activeDownloads.remove(model.id);
    }
  }

  /// Cancels an in-flight download.
  void cancelDownload(String modelId) {
    _activeDownloads[modelId]?.cancel('Download cancelled by user');
    _activeDownloads.remove(modelId);
  }

  /// Deletes a downloaded model from disk.
  Future<void> deleteModel(String modelId) async {
    try {
      if (_currentModelId == modelId) {
        await unloadModel();
      }
      final dir = await getModelDirectory(modelId);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      Log.info('Deleted MLX model $modelId');
    } catch (e) {
      Log.error('Error deleting MLX model $modelId: $e');
    }
  }

  /// Loads an MLX model for inference.
  Future<void> loadModel(OnDeviceModel model) async {
    if (_isDisposed) {
      throw StateError('OnDeviceMlxService has been disposed');
    }
    _ensureNativeInferenceAvailable();
    if (!_isIOS) {
      throw UnsupportedError(
        'Apple MLX text generation is only supported on iOS.',
      );
    }
    if (model.runtime != OnDeviceModelRuntime.mlx) {
      throw ArgumentError.value(
        model.runtime,
        'model.runtime',
        'Expected an Apple MLX model',
      );
    }
    if (_currentModelId == model.id && isLoaded) return;

    final dir = await getModelDirectory(model.id);
    if (!await isModelInstalled(model.id)) {
      throw StateError(
        'MLX Model ${model.id} is not downloaded. Please download it first.',
      );
    }

    await unloadModel();

    Log.info('Loading MLX model ${model.id} from ${dir.path}');
    final manager = _llmManagerFactory();
    await manager.loadAndStartServer(
      modelPath: dir.path,
      modelId: _extractRepoId(model.huggingFaceUrl),
      thinkingEnabled: model.supportsThinking,
    );

    _llmManager = manager;
    _currentModelId = model.id;
    _currentModelSupportsThinking = model.supportsThinking;
    Log.info('MLX model ${model.id} loaded successfully');
  }

  /// Unloads the active MLX model.
  Future<void> unloadModel() async {
    final manager = _llmManager;
    final modelId = _currentModelId;
    _llmManager = null;
    _currentModelId = null;
    _currentModelSupportsThinking = false;
    if (manager != null) {
      Log.info('Unloading MLX model $modelId');
      await manager.dispose();
    }
  }

  /// Streams chat responses from the loaded MLX model.
  Stream<ChatResponse> sendMessage({
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
  }) async* {
    final manager = _llmManager;
    if (manager == null || !manager.isModelLoaded) {
      yield const ChatResponse(
        type: ChatResponseType.error,
        content: 'MLX model is not loaded. Please load the model first.',
      );
      yield const ChatResponse(type: ChatResponseType.done);
      return;
    }
    if (_currentModelId != modelId) {
      yield ChatResponse(
        type: ChatResponseType.error,
        content:
            'MLX model $modelId is not loaded. The active model is '
            '${_currentModelId ?? 'unknown'}.',
      );
      yield const ChatResponse(type: ChatResponseType.done);
      return;
    }

    final formattedMessages = <Map<String, String>>[];

    if (params.systemPrompt != null && params.systemPrompt!.isNotEmpty) {
      formattedMessages.add({
        'role': 'system',
        'content': params.systemPrompt!,
      });
    }

    for (final m in messages) {
      if (m.role == MessageRole.system && m.content == params.systemPrompt) {
        continue;
      }
      final role = m.role == MessageRole.user
          ? 'user'
          : m.role == MessageRole.assistant
          ? 'assistant'
          : 'system';
      formattedMessages.add({'role': role, 'content': m.content});
    }

    while (formattedMessages.isNotEmpty &&
        formattedMessages.last['role'] == 'assistant' &&
        formattedMessages.last['content']!.isEmpty) {
      formattedMessages.removeLast();
    }

    try {
      final stream = manager.generateStream(
        messages: formattedMessages,
        temperature: params.temperature,
        maxTokens: params.maxTokens,
        thinking: _currentModelSupportsThinking,
      );

      await for (final delta in stream) {
        if (delta.isDone) {
          yield const ChatResponse(type: ChatResponseType.done);
          break;
        }

        if (delta.reasoningContent != null &&
            delta.reasoningContent!.isNotEmpty) {
          yield ChatResponse(
            type: ChatResponseType.reasoning,
            reasoningContent: delta.reasoningContent!,
          );
        }

        if (delta.content != null && delta.content!.isNotEmpty) {
          yield ChatResponse(
            type: ChatResponseType.message,
            content: delta.content!,
          );
        }
      }
    } catch (e) {
      Log.error('MLX generation error: $e');
      yield ChatResponse(
        type: ChatResponseType.error,
        content: 'MLX generation error: $e',
      );
      yield const ChatResponse(type: ChatResponseType.done);
    }
  }

  void dispose() {
    _isDisposed = true;
    for (final token in _activeDownloads.values) {
      token.cancel('Service disposed');
    }
    _activeDownloads.clear();
    unawaited(unloadModel());
  }

  void _ensureNativeInferenceAvailable() {
    if (!_nativeInferenceAvailable) {
      throw UnsupportedError(AppleMlxCapabilities.nativeLlmUnavailableReason);
    }
  }

  String _extractRepoId(String url) {
    if (!url.startsWith('http')) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      return '${segments[0]}/${segments[1]}';
    }
    return url;
  }

  bool _shouldSkipFile(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('.') ||
        lower.endsWith('.md') ||
        lower.endsWith('.gitattributes') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg');
  }
}

class OnDeviceMlxChatService implements ChatService {
  OnDeviceMlxChatService(this._mlxService);

  final OnDeviceMlxService _mlxService;
  bool _isCancelled = false;

  @override
  Stream<ChatResponse> sendMessage({
    required Server server,
    required String modelId,
    required List<Message> messages,
    required ChatParameters params,
    List<McpIntegration>? integrations,
    List<ToolDefinition>? tools,
    bool continueGeneration = false,
  }) async* {
    _isCancelled = false;
    await for (final response in _mlxService.sendMessage(
      modelId: modelId,
      messages: messages,
      params: params,
    )) {
      if (_isCancelled) break;
      yield response;
      if (response.type == ChatResponseType.done ||
          response.type == ChatResponseType.error) {
        break;
      }
    }
  }

  @override
  void cancelStream() {
    _isCancelled = true;
  }
}
