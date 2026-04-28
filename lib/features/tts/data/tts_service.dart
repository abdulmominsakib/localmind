import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  Future<void> init() async {
    if (_isInitialized) return;
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
    _isInitialized = true;
  }

  bool get isSpeaking => _isSpeaking;

  Future<void> speak(String text) async {
    await init();
    if (text.trim().isEmpty) return;
    _isSpeaking = true;
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  Future<void> pause() async {
    await _tts.pause();
    _isSpeaking = false;
  }

  Future<List<dynamic>> getVoices() async {
    await init();
    return await _tts.getVoices;
  }

  Future<void> setVoice(String name, String locale) async {
    await _tts.setVoice({'name': name, 'locale': locale});
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
