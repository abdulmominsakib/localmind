import 'speech_runner.dart';

/// One file-input STT -> chat -> TTS operation through injected public adapters.
/// Physical microphone/speaker behavior requires its own device evidence.
Future<Map<String, Object?>> runVoiceRoundTrip({
  required SpeechValidationAdapter recognizer,
  required Future<String> Function(String transcript) respond,
  required SpeechValidationAdapter Function(String response) synthesizer,
}) async {
  SpeechValidationAdapter? speaker;
  final watch = Stopwatch()..start();
  final result = <String, Object?>{
    'schema_version': 1,
    'kind': 'voice_round_trip',
    'functional_pass': false,
    'qualified': false,
    'microphone': 'NOT_RUN',
    'speaker_playback': 'NOT_RUN',
    'listening_check': 'NOT_RUN',
  };
  try {
    await recognizer.load();
    final transcription = await recognizer.execute();
    result['stt'] = transcription;
    if (transcription['predicate_passed'] != true) {
      throw StateError('STT reference predicate failed');
    }
    final transcript = transcription['transcript'] as String;
    if (transcript.trim().isEmpty) throw StateError('Empty transcript');
    await recognizer.dispose();
    final response = await respond(transcript);
    if (response.trim().isEmpty) throw StateError('Empty chat response');
    result['response'] = response;
    speaker = synthesizer(response);
    await speaker.load();
    final synthesis = await speaker.execute();
    result['tts'] = synthesis;
    if (synthesis['predicate_passed'] != true) {
      throw StateError('TTS output predicate failed');
    }
    result['functional_pass'] = true;
  } catch (error) {
    result['error_type'] = '${error.runtimeType}';
  } finally {
    for (final adapter in [recognizer, ?speaker]) {
      try {
        await adapter.dispose();
      } catch (error) {
        result['functional_pass'] = false;
        result['cleanup_error_type'] = '${error.runtimeType}';
      }
    }
    result['elapsed_ms'] = watch.elapsedMicroseconds / 1000;
  }
  return result;
}
