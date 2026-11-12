import 'dart:typed_data';

/// The measured behaviour an edge fixture is required to reproduce.
enum SpeechEdgeContract {
  /// Recognition must be rejected with a `LlamaSpeechException` whose message
  /// is the fixture's [SpeechEdgeFixture.rejectionMessage].
  typedRejection,

  /// Recognition must complete without reproducing the locked reference.
  unrelatedTranscript,

  /// Recognition must either complete without reproducing the locked
  /// reference, or be rejected with a `LlamaAudioFormatException`.
  unrelatedTranscriptOrFormatRejection,

  /// Recognition must complete and reproduce the reference in full, repeated
  /// `referenceRepeats` times.
  repeatedReference,
}

/// A synthetic edge-case WAV built in-process for the speech validation packs.
class SpeechEdgeFixture {
  /// Creates an edge fixture description.
  const SpeechEdgeFixture({
    required this.id,
    required this.bytes,
    required this.sampleRateHz,
    required this.channelCount,
    required this.seconds,
    required this.contract,
    required this.rationale,
    this.referenceRepeats = 0,
    this.rejectionMessage,
  });

  /// Stable identifier, used as the validation check id.
  final String id;

  /// The fixture's encoded bytes, which may be a deliberately truncated WAV.
  final Uint8List bytes;

  /// Sample rate declared by [bytes].
  final int sampleRateHz;

  /// Channel count declared by [bytes].
  final int channelCount;

  /// Audio duration, or null when [bytes] deliberately declare more audio than
  /// they carry.
  final double? seconds;

  /// The required outcome for this fixture.
  final SpeechEdgeContract contract;

  /// How many consecutive copies of the locked reference the transcript must
  /// contain under [SpeechEdgeContract.repeatedReference].
  final int referenceRepeats;

  /// Why this input sits at an edge of the documented speech contract.
  final String rationale;

  /// The exact rejection message required under
  /// [SpeechEdgeContract.typedRejection], and null under every other contract.
  final String? rejectionMessage;
}

/// Largest fixture byte count `speechFixtureSeconds` and
/// [buildSpeechEdgeFixtures] accept.
const speechFixtureByteCap = 5000000;

/// Builds the synthetic speech edge fixtures for [fixture], which must be a
/// locked mono 16 kHz PCM16 WAV.
///
/// Digital silence is generated; the other three are derived from [fixture].
/// Every returned fixture stays at or below [speechFixtureByteCap] bytes.
/// Only the silence and long-boundary fixtures satisfy `speechFixtureSeconds`:
/// the stereo fixture is 44.1 kHz two-channel, and the truncated fixture's
/// RIFF size field declares more bytes than it carries.
List<SpeechEdgeFixture> buildSpeechEdgeFixtures(Uint8List fixture) {
  final source = _readMono16kPcm(fixture);
  final silence = _wav(Int16List(48000), sampleRateHz: 16000, channelCount: 1);
  final truncated = Uint8List.fromList(fixture.sublist(0, 20044));
  final stereo = _wav(
    _interleaveStereo(_resample(source, 16000, 44100)),
    sampleRateHz: 44100,
    channelCount: 2,
  );
  final repeats = (30 * 16000 / source.length).floor() + 1;
  final concatenated = Int16List(source.length * repeats);
  for (var i = 0; i < repeats; i++) {
    concatenated.setRange(i * source.length, (i + 1) * source.length, source);
  }
  final long = _wav(concatenated, sampleRateHz: 16000, channelCount: 1);
  final fixtures = [
    SpeechEdgeFixture(
      id: 'edge_silence',
      bytes: silence,
      sampleRateHz: 16000,
      channelCount: 1,
      seconds: 48000 / 16000,
      contract: SpeechEdgeContract.typedRejection,
      rationale: 'Digital silence yields no transcript to return.',
      rejectionMessage: 'Speech recognition produced an empty transcript.',
    ),
    SpeechEdgeFixture(
      id: 'edge_truncated_riff',
      bytes: truncated,
      sampleRateHz: 16000,
      channelCount: 1,
      seconds: null,
      contract: SpeechEdgeContract.unrelatedTranscriptOrFormatRejection,
      rationale: 'RIFF size declares more audio than the bytes carry.',
    ),
    SpeechEdgeFixture(
      id: 'edge_stereo_44100',
      bytes: stereo,
      sampleRateHz: 44100,
      channelCount: 2,
      seconds: source.length / 16000,
      contract: SpeechEdgeContract.repeatedReference,
      referenceRepeats: 1,
      rationale: 'Decoding must downmix and resample stereo 44.1 kHz input.',
    ),
    SpeechEdgeFixture(
      id: 'edge_long_boundary',
      bytes: long,
      sampleRateHz: 16000,
      channelCount: 1,
      seconds: concatenated.length / 16000,
      contract: SpeechEdgeContract.repeatedReference,
      referenceRepeats: repeats,
      rationale: 'Audio over 30 seconds must be transcribed in full.',
    ),
  ];
  for (final entry in fixtures) {
    if (entry.bytes.length > speechFixtureByteCap) {
      throw StateError('Edge fixture ${entry.id} exceeds the byte cap');
    }
    if (entry.contract == SpeechEdgeContract.repeatedReference &&
        entry.referenceRepeats < 1) {
      throw StateError('Edge fixture ${entry.id} needs a reference repeat');
    }
    if ((entry.contract == SpeechEdgeContract.typedRejection) !=
        (entry.rejectionMessage != null)) {
      throw StateError('Edge fixture ${entry.id} misdeclares its rejection');
    }
  }
  return fixtures;
}

/// Whether a completed recognition with word error rate [wer] satisfies
/// [fixture]'s contract.
bool speechEdgeTranscriptHolds(SpeechEdgeFixture fixture, double wer) =>
    switch (fixture.contract) {
      SpeechEdgeContract.typedRejection => false,
      SpeechEdgeContract.unrelatedTranscript ||
      SpeechEdgeContract.unrelatedTranscriptOrFormatRejection => wer > 0,
      SpeechEdgeContract.repeatedReference => wer == 0,
    };

/// Whether a rejection satisfies [fixture]'s contract.
///
/// [message] is the thrown `LlamaSpeechException` message and
/// [isAudioFormat] whether it was a `LlamaAudioFormatException`. Contracts
/// that require a transcript are never satisfied by a rejection.
bool speechEdgeRejectionHolds(
  SpeechEdgeFixture fixture, {
  required String message,
  required bool isAudioFormat,
}) => switch (fixture.contract) {
  SpeechEdgeContract.typedRejection => message == fixture.rejectionMessage,
  SpeechEdgeContract.unrelatedTranscriptOrFormatRejection => isAudioFormat,
  SpeechEdgeContract.unrelatedTranscript ||
  SpeechEdgeContract.repeatedReference => false,
};

Int16List _readMono16kPcm(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  String tag(int start) =>
      String.fromCharCodes(bytes.sublist(start, start + 4));
  if (bytes.length < 44 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Expected a RIFF/WAVE fixture');
  }
  var offset = 12;
  var formatSeen = false;
  while (offset + 8 <= bytes.length) {
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (start + size > bytes.length) {
      throw const FormatException('Truncated WAV chunk');
    }
    if (tag(offset) == 'fmt ') {
      if (data.getUint16(start, Endian.little) != 1 ||
          data.getUint16(start + 2, Endian.little) != 1 ||
          data.getUint32(start + 4, Endian.little) != 16000 ||
          data.getUint16(start + 14, Endian.little) != 16) {
        throw const FormatException('Expected mono 16 kHz PCM16 WAV');
      }
      formatSeen = true;
    }
    if (tag(offset) == 'data' && formatSeen) {
      final samples = Int16List(size ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = data.getInt16(start + i * 2, Endian.little);
      }
      return samples;
    }
    offset = start + size + (size.isOdd ? 1 : 0);
  }
  throw const FormatException('Fixture carries no mono 16 kHz PCM data');
}

Int16List _resample(Int16List samples, int fromRate, int toRate) {
  final length = (samples.length * toRate / fromRate).floor();
  final result = Int16List(length);
  for (var i = 0; i < length; i++) {
    final position = i * fromRate / toRate;
    final index = position.floor();
    final next = index + 1 < samples.length ? index + 1 : index;
    final weight = position - index;
    result[i] = (samples[index] * (1 - weight) + samples[next] * weight)
        .round()
        .clamp(-32768, 32767);
  }
  return result;
}

Int16List _interleaveStereo(Int16List mono) {
  final result = Int16List(mono.length * 2);
  for (var i = 0; i < mono.length; i++) {
    result[i * 2] = mono[i];
    result[i * 2 + 1] = mono[i];
  }
  return result;
}

Uint8List _wav(
  Int16List samples, {
  required int sampleRateHz,
  required int channelCount,
}) {
  final payload = samples.length * 2;
  final bytes = Uint8List(44 + payload);
  final data = ByteData.sublistView(bytes);
  void tag(int offset, String value) =>
      bytes.setRange(offset, offset + 4, value.codeUnits);
  tag(0, 'RIFF');
  data.setUint32(4, 36 + payload, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channelCount, Endian.little);
  data.setUint32(24, sampleRateHz, Endian.little);
  data.setUint32(28, sampleRateHz * channelCount * 2, Endian.little);
  data.setUint16(32, channelCount * 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, payload, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes;
}
