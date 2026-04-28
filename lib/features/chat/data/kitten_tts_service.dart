import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:kitten_tts_flutter/kitten_tts_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/logger/app_logger.dart';
import '../../../core/models/enums.dart';
import 'phonemizer_service.dart';

/// Service that wraps the KittenTTS Flutter package for neural text-to-speech.
///
/// On first initialization, copies the required model files from app assets
/// to the filesystem (since the ONNX runtime requires absolute file paths).
///
/// Usage:
/// ```dart
/// final service = KittenTtsService();
/// await service.initialize();
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

  // Asset paths
  static const String _assetConfig = 'assets/tts/config.json';
  static const String _assetModel = 'assets/tts/kitten_tts_nano_v0_8.onnx';
  static const String _assetVoices = 'assets/tts/voices.npz';

  // File names in the app support directory
  static const String _fileConfig = 'config.json';
  static const String _fileModel = 'kitten_tts_nano_v0_8.onnx';
  static const String _fileVoices = 'voices.npz';

  bool get isInitialized => _isInitialized;
  bool get isSpeaking => _isSpeaking;

  /// Initialize the KittenTTS engine.
  ///
  /// Copies model files from assets to the filesystem on first run,
  /// then loads the ONNX session.
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initializeFuture != null) return _initializeFuture;

    _initializeFuture = _doInitialize();
    return _initializeFuture;
  }

  Future<void> _doInitialize() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final ttsDir = Directory('${supportDir.path}/kitten_tts');
      if (!await ttsDir.exists()) {
        await ttsDir.create(recursive: true);
      }

      // Copy assets to filesystem if not already present
      final configPath = await _ensureAssetFile(
        ttsDir,
        _fileConfig,
        _assetConfig,
      );
      final modelPath = await _ensureAssetFile(ttsDir, _fileModel, _assetModel);
      final voicesPath = await _ensureAssetFile(
        ttsDir,
        _fileVoices,
        _assetVoices,
      );

      Log.info(
        'KittenTTS assets ready: config=$configPath, model=$modelPath, voices=$voicesPath',
      );

      // Initialize KittenTTS engine
      _tts ??= KittenTtsFlutter();
      await _tts!.init(
        configPath: configPath,
        modelPath: modelPath,
        voicesPath: voicesPath,
      );

      _audioPlayer ??= AudioPlayer();
      _audioPlayer!.onPlayerComplete.listen((_) {
        _isSpeaking = false;
      });

      _isInitialized = true;
      Log.info('KittenTTS initialized successfully');
    } catch (e, st) {
      Log.error('Failed to initialize KittenTTS: $e\n$st');
      rethrow;
    } finally {
      _initializeFuture = null;
    }
  }

  /// Generate WAV bytes and play them for the given text.
  ///
  /// [text] should be plain English text. It will be phonemized internally.
  /// [voice] selects one of the built-in voices.
  /// [speed] controls the playback rate (0.5 to 2.0).
  Future<void> speak(
    String text, {
    KittenTtsVoice voice = KittenTtsVoice.bella,
    double speed = 1.0,
  }) async {
    await initialize();
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    // If already speaking, stop first
    if (_isSpeaking) {
      await stop();
    }

    _isSpeaking = true;

    try {
      // Split text into smaller chunks (sentences) to avoid ONNX sequence length limits
      // The "Nano" model used by KittenTTS often crashes on inputs > ~200-300 chars.
      final chunks = _splitIntoChunks(trimmedText);
      Log.debug('Split text into ${chunks.length} chunks for TTS');

      for (final chunk in chunks) {
        if (!_isSpeaking) break;

        final phonemized =
            "${_phonemizer.phonemize(chunk)}  "; // Add trailing silence
        Log.debug('Speaking chunk: "$chunk"');
        Log.debug('Phonemized: "$phonemized" (speed: $speed)');

        Uint8List wavBytes;
        try {
          wavBytes = await _tts!.generateWavBytes(
            phonemizedText: phonemized,
            language: 'en',
            voice: voice.displayName,
            speed: speed,
          );
        } catch (e) {
          // If session is not initialized, try one re-initialization
          if (e.toString().contains('Session not initialized')) {
            Log.warning(
              'KittenTTS session not initialized, attempting recovery...',
            );
            _isInitialized = false;
            await initialize();
            wavBytes = await _tts!.generateWavBytes(
              phonemizedText: phonemized,
              language: 'en',
              voice: voice.displayName,
              speed: speed,
            );
          } else {
            rethrow;
          }
        }

        if (!_isSpeaking) break;

        // Play the WAV bytes and wait for completion
        final completer = Completer<void>();
        StreamSubscription? completeSub;

        completeSub = _audioPlayer!.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        await _audioPlayer!.play(BytesSource(wavBytes));

        // Wait until the chunk finishes playing or _isSpeaking becomes false (stopped manually)
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
  }

  /// Ensures an asset file exists on the filesystem.
  /// If missing, copies it from app assets.
  Future<String> _ensureAssetFile(
    Directory targetDir,
    String fileName,
    String assetPath,
  ) async {
    final file = File('${targetDir.path}/$fileName');
    if (await file.exists()) {
      return file.path;
    }

    Log.info('Copying asset $assetPath to ${file.path}');
    final byteData = await rootBundle.load(assetPath);
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.path;
  }

  /// Splits text into smaller chunks (ideally sentences) to avoid TTS engine limits.
  List<String> _splitIntoChunks(String text, {int maxChars = 200}) {
    final sentences = _splitIntoSentences(text);
    final chunks = <String>[];
    String currentChunk = "";

    for (final sentence in sentences) {
      // If adding this sentence exceeds maxChars, push currentChunk and start new
      if (currentChunk.isNotEmpty &&
          (currentChunk.length + sentence.length + 1) > maxChars) {
        chunks.add(currentChunk.trim());
        currentChunk = "";
      }

      // If the sentence itself is longer than maxChars, split it by words
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
    // Split by . ! ? followed by space or end of string
    final regex = RegExp(r'(?<=[.!?])\s+');
    return text.split(regex).where((s) => s.trim().isNotEmpty).toList();
  }
}
