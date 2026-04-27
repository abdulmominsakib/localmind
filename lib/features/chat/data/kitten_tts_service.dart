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
      final configPath = await _ensureAssetFile(ttsDir, _fileConfig, _assetConfig);
      final modelPath = await _ensureAssetFile(ttsDir, _fileModel, _assetModel);
      final voicesPath = await _ensureAssetFile(ttsDir, _fileVoices, _assetVoices);

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
    if (text.trim().isEmpty) return;

    _isSpeaking = true;

    try {
      final phonemized = "${_phonemizer.phonemize(text)}  "; // Add trailing silence
      Log.debug('Phonemized: "$text" → "$phonemized" (speed: $speed)');

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
          Log.warning('KittenTTS session not initialized, attempting recovery...');
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

      // Play the WAV bytes
      await _audioPlayer!.stop();
      await _audioPlayer!.play(BytesSource(wavBytes));
    } catch (e, st) {
      Log.error('KittenTTS speak error: $e\n$st');
      _isSpeaking = false;
      rethrow;
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
}
