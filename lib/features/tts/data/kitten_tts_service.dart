import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:kitten_tts_flutter/kitten_tts_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import 'kitten_tts_model.dart';
import 'phonemizer_service.dart';

/// Service that wraps the KittenTTS Flutter package for neural text-to-speech.
///
/// Model files are downloaded on-demand from HuggingFace and stored in the
/// app support directory. Call [initialize] with a variant before use.
///
/// Usage:
/// ```dart
/// final service = KittenTtsService();
/// await service.initialize(variant: KittenTtsModelVariant.nanoInt8);
/// await service.speak('Hello world', voice: KittenTtsVoice.bella);
/// await service.dispose();
/// ```
class KittenTtsService {
  KittenTtsFlutter? _tts;
  AudioPlayer? _audioPlayer;
  final PhonemizerService _phonemizer = PhonemizerService();

  bool _isInitialized = false;
  bool _isSpeaking = false;
  Future<void>? _initializeFuture;
  KittenTtsModelVariant? _currentVariant;

  bool get isInitialized => _isInitialized;
  bool get isSpeaking => _isSpeaking;
  KittenTtsModelVariant? get currentVariant => _currentVariant;

  /// Check whether all files for a variant exist on disk.
  static Future<bool> isVariantDownloaded(KittenTtsModelVariant variant) async {
    final supportDir = await getApplicationSupportDirectory();
    final ttsDir = Directory('${supportDir.path}/kitten_tts/${variant.dirName}');
    for (final file in variant.files) {
      if (!await File('${ttsDir.path}/${file.fileName}').exists()) {
        return false;
      }
    }
    return true;
  }

  /// Get the file paths for a variant, or null if not downloaded.
  static Future<({String config, String model, String voices})?> getVariantPaths(
    KittenTtsModelVariant variant,
  ) async {
    final supportDir = await getApplicationSupportDirectory();
    final ttsDir = Directory('${supportDir.path}/kitten_tts/${variant.dirName}');
    final configFile = File('${ttsDir.path}/config.json');
    final modelFile = File('${ttsDir.path}/${variant.modelFileName}');
    final voicesFile = File('${ttsDir.path}/voices.npz');

    if (!await configFile.exists() ||
        !await modelFile.exists() ||
        !await voicesFile.exists()) {
      return null;
    }

    return (
      config: configFile.path,
      model: modelFile.path,
      voices: voicesFile.path,
    );
  }

  /// Initialize (or re-initialize) the KittenTTS engine for [variant].
  ///
  /// Throws if the model files are not downloaded.
  Future<void> initialize({required KittenTtsModelVariant variant}) async {
    if (_isInitialized && _currentVariant == variant) return;
    if (_initializeFuture != null) return _initializeFuture;

    _initializeFuture = _doInitialize(variant);
    return _initializeFuture;
  }

  Future<void> _doInitialize(KittenTtsModelVariant variant) async {
    try {
      final paths = await getVariantPaths(variant);
      if (paths == null) {
        throw StateError(
          'KittenTTS model "${variant.displayName}" is not downloaded. '
          'Please download it from the TTS Models screen.',
        );
      }

      Log.info(
        'KittenTTS initializing: variant=${variant.displayName}, '
        'config=${paths.config}, model=${paths.model}, voices=${paths.voices}',
      );

      if (_tts != null && _currentVariant != null && _currentVariant != variant) {
        try {
          _tts?.release();
        } catch (_) {}
        _tts = null;
      }

      _tts ??= KittenTtsFlutter();
      await _tts!.init(
        configPath: paths.config,
        modelPath: paths.model,
        voicesPath: paths.voices,
      );

      _audioPlayer ??= AudioPlayer();
      _audioPlayer!.onPlayerComplete.listen((_) {
        _isSpeaking = false;
      });

      _currentVariant = variant;
      _isInitialized = true;
      Log.info('KittenTTS initialized successfully (${variant.displayName})');
    } catch (e, st) {
      Log.error('Failed to initialize KittenTTS: $e\n$st');
      rethrow;
    } finally {
      _initializeFuture = null;
    }
  }

  /// Generate WAV bytes and play them for the given text.
  Future<void> speak(
    String text, {
    KittenTtsVoice voice = KittenTtsVoice.bella,
    double speed = 1.0,
  }) async {
    if (!_isInitialized) {
      throw StateError(
        'KittenTTS not initialized. Call initialize() first.',
      );
    }

    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    if (_isSpeaking) {
      await stop();
    }

    _isSpeaking = true;

    try {
      final chunks = _splitIntoChunks(trimmedText);
      Log.debug('Split text into ${chunks.length} chunks for TTS');

      for (final chunk in chunks) {
        if (!_isSpeaking) break;

        final phonemized =
            "${_phonemizer.phonemize(chunk)}  ";
        Log.debug('Speaking chunk: "$chunk"');
        Log.debug('Phonemized: "$phonemized" (speed: $speed)');

        final wavBytes = await _generateWavWithRetry(
          phonemizedText: phonemized,
          language: 'en',
          voice: voice.displayName,
          speed: speed,
        );

        if (!_isSpeaking) break;

        final completer = Completer<void>();
        StreamSubscription? completeSub;

        completeSub = _audioPlayer!.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await _audioPlayer!.play(BytesSource(wavBytes));

        while (_isSpeaking && !completer.isCompleted) {
          await Future.delayed(const Duration(milliseconds: 50));
        }

        await completeSub.cancel();
      }
    } catch (e, st) {
      Log.error('KittenTTS speak error: $e\n$st');
      rethrow;
    } finally {
      _isSpeaking = false;
    }
  }

  /// Stop any ongoing audio playback.
  Future<void> stop() async {
    await _audioPlayer?.stop();
    _isSpeaking = false;
  }

  /// Pause audio playback.
  Future<void> pause() async {
    await _audioPlayer?.pause();
    _isSpeaking = false;
  }

  /// Release the ONNX session and audio player.
  Future<void> dispose() async {
    try {
      _tts?.release();
    } catch (_) {}
    try {
      await _audioPlayer?.dispose();
    } catch (_) {}
    _tts = null;
    _audioPlayer = null;
    _isInitialized = false;
    _isSpeaking = false;
    _currentVariant = null;
  }

  /// Generate WAV bytes for a sample preview (used by TTS Model Manager).
  Future<Uint8List> generatePreviewWav(
    String text, {
    KittenTtsVoice voice = KittenTtsVoice.bella,
    double speed = 1.0,
  }) async {
    if (!_isInitialized) {
      throw StateError('KittenTTS not initialized');
    }
    final phonemized = "${_phonemizer.phonemize(text)}  ";
    return _generateWavWithRetry(
      phonemizedText: phonemized,
      language: 'en',
      voice: voice.displayName,
      speed: speed,
    );
  }

  /// Core helper to generate WAV bytes with retry for "Session not initialized".
  Future<Uint8List> _generateWavWithRetry({
    required String phonemizedText,
    required String language,
    required String voice,
    required double speed,
  }) async {
    const maxRetries = 3;
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await _tts!.generateWavBytes(
          phonemizedText: phonemizedText,
          language: language,
          voice: voice,
          speed: speed,
        );
      } catch (e) {
        if (e.toString().contains('Session not initialized') &&
            attempt < maxRetries - 1) {
          Log.warning(
            'KittenTTS session not initialized (attempt ${attempt + 1}/$maxRetries), '
            're-initializing...',
          );
          _isInitialized = false;
          if (_currentVariant != null) {
            await initialize(variant: _currentVariant!);
          }
          await Future.delayed(const Duration(milliseconds: 150));
        } else {
          rethrow;
        }
      }
    }
    throw StateError('KittenTTS session failed to initialize after $maxRetries attempts');
  }

  /// Splits text into smaller chunks (ideally sentences) to avoid TTS engine limits.
  List<String> _splitIntoChunks(String text, {int maxChars = 200}) {
    final sentences = _splitIntoSentences(text);
    final chunks = <String>[];
    String currentChunk = "";

    for (final sentence in sentences) {
      if (currentChunk.isNotEmpty &&
          (currentChunk.length + sentence.length + 1) > maxChars) {
        chunks.add(currentChunk.trim());
        currentChunk = "";
      }

      if (sentence.length > maxChars) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.trim());
          currentChunk = "";
        }

        final words = sentence.split(' ');
        String subChunk = "";
        for (final word in words) {
          if (subChunk.isNotEmpty &&
              (subChunk.length + word.length + 1) > maxChars) {
            chunks.add(subChunk.trim());
            subChunk = "";
          }
          subChunk += (subChunk.isEmpty ? "" : " ") + word;
        }
        if (subChunk.isNotEmpty) currentChunk = subChunk;
      } else {
        currentChunk += (currentChunk.isEmpty ? "" : " ") + sentence;
      }
    }

    if (currentChunk.isNotEmpty) chunks.add(currentChunk.trim());
    return chunks;
  }

  /// Splits text into sentences based on punctuation.
  List<String> _splitIntoSentences(String text) {
    final regex = RegExp(r'(?<=[.!?])\s+');
    return text.split(regex).where((s) => s.trim().isNotEmpty).toList();
  }
}
