import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Deterministic instruction shared by the audio-chat real-model smokes.
const String audioChatQuestionPrompt =
    'Listen carefully to every spoken word. Determine what the speaker is '
    'asking, solve that request, and return only the final answer. Do not '
    'merely repeat a word from the recording.';

/// Encoded audio bytes and path-free identity used by a smoke result.
class AudioChatSmokeFixture {
  const AudioChatSmokeFixture({required this.bytes, required this.fixtureId});

  /// Complete encoded audio file bytes.
  final Uint8List bytes;

  /// Stable SHA-256 identity that does not expose the source path.
  final String fixtureId;

  /// Path-free result metadata suitable for logs and PR evidence.
  Map<String, Object> toJson() => <String, Object>{
    'encodedByteLength': bytes.length,
    'fixtureId': fixtureId,
  };
}

/// Resolves an optional encoded-audio path from [environmentName].
String? optionalAudioChatSmokePath({
  required String environmentName,
  required String smokeName,
}) {
  final value = Platform.environment[environmentName]?.trim();
  if (value == null || value.isEmpty) {
    return null;
  }
  if (!File(value).existsSync()) {
    throw ArgumentError('$smokeName audio fixture does not exist.');
  }
  return value;
}

/// Resolves and validates the exact expected answer for an audio variant.
String? optionalAudioChatExpectedText({
  required String? audioPath,
  required String environmentName,
  required String audioEnvironmentName,
}) {
  if (audioPath == null) {
    return null;
  }
  final value = Platform.environment[environmentName]?.trim();
  if (value == null || value.isEmpty) {
    throw ArgumentError(
      '$environmentName is required when $audioEnvironmentName is set.',
    );
  }
  if (normalizeAudioChatAnswer(value).isEmpty) {
    throw ArgumentError('$environmentName must contain a verifiable answer.');
  }
  return value;
}

/// Reads an encoded fixture and computes its stable, path-free identity.
Future<AudioChatSmokeFixture> readAudioChatSmokeFixture(String path) async {
  final bytes = await File(path).readAsBytes();
  if (bytes.isEmpty) {
    throw ArgumentError('Audio-chat smoke fixture must not be empty.');
  }
  final digest = sha256.convert(bytes);
  return AudioChatSmokeFixture(bytes: bytes, fixtureId: 'sha256:$digest');
}

/// Normalizes insignificant presentation around a short exact answer.
String normalizeAudioChatAnswer(String value) {
  final collapsed = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return collapsed.replaceAll(RegExp(r'^[`*_]+|[`*_.!,;:?]+$'), '').trim();
}

/// Requires [actualText] to equal [expectedText] after normalization.
void verifyExactAudioChatAnswer({
  required String scenarioName,
  required String actualText,
  required String expectedText,
}) {
  final expected = normalizeAudioChatAnswer(expectedText);
  final actual = normalizeAudioChatAnswer(actualText);
  if (actual != expected) {
    throw StateError(
      '$scenarioName answer mismatch: expected "$expected", received '
      '"$actual".',
    );
  }
}
