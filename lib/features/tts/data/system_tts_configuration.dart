import 'package:flutter_tts/flutter_tts.dart';

/// Keeps the app aligned with Android's chosen TTS engine. Each engine owns
/// its default voice/language; forcing en-US can disable third-party voices.
class SystemTtsConfiguration {
  String? _engine;

  Future<void> prepare(FlutterTts tts, {required bool isAndroid}) async {
    if (!isAndroid) return;
    final selected = await tts.getDefaultEngine;
    if (selected is! String || selected.trim().isEmpty) return;
    if (selected == _engine) return;
    // setEngine completes after native initialization and reports failures.
    await tts.setEngine(selected);
    _engine = selected;
  }
}
