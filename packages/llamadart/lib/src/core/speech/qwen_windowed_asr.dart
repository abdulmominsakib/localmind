import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../exceptions.dart';
import 'speech_to_text.dart';

/// Sample rate required by Qwen3-ASR windowed live input.
const int qwenWindowedSampleRateHz = 16000;

/// Maximum samples held in the bounded Qwen3-ASR ring buffer (8 s at 16 kHz).
const int qwenWindowedMaxSamples = 128000;

/// Checkpoint step in samples (2 s at 16 kHz: checkpoints at 2, 4, and 6 s).
const int qwenWindowedCheckpointStepSamples = 32000;

/// Start of the quiet-boundary search range in samples (6 s at 16 kHz).
const int qwenWindowedQuietSearchStartSample = 96000;

/// Frame size for quiet-boundary RMS evaluation (20 ms at 16 kHz).
const int qwenWindowedQuietFrameSamples = 320;

/// Minimum contiguous quiet frames for a quiet boundary (100 ms = 5 frames).
const int qwenWindowedQuietMinFrames = 5;

/// Normalized RMS threshold for a quiet 20 ms frame.
const double qwenWindowedQuietRmsThreshold = 0.01;

const double _verificationFrameRms = 0.007;
const int _voicingDownsample = 4;
const int _voicingFrameSize =
    qwenWindowedQuietFrameSamples ~/ _voicingDownsample;
const int _voicingMinLag = 10;
const int _voicingMaxLag = 40;
const double _voicingMinRms = 0.007;
const double _voicingMinCorrelation = 0.75;
const int _voicingMinCrossingChange = 3;
const int _voicingMinChanges = 4;

/// Shared transcription instruction for Qwen3-ASR's instructed prompt.
const String qwen3AsrDefaultInstruction = 'Transcribe this audio accurately.';

final _instructionHypotheses = {
  _normalizeInstruction(qwen3AsrDefaultInstruction),
  'transcreva este audio com precisao',
  'transcreva este audio',
  'transcreva este audio acertadamente',
};

final _instructionWhitespace = RegExp(r'\s+');
final _instructionTerminalPunctuation = RegExp(r'[.!?…]+$');
final _instructionCombiningAccents = RegExp(r'[\u0301\u0303]');

String _normalizeInstruction(String text) => text
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('ã', 'a')
    .replaceAll(_instructionCombiningAccents, '')
    .trim()
    .replaceAll(_instructionWhitespace, ' ')
    .replaceFirst(_instructionTerminalPunctuation, '')
    .trimRight();

bool _referenceAgrees(String original, String reference) {
  if (original == reference) {
    return true;
  }
  final originalWords = original.split(' ');
  final referenceWords = reference.split(' ');
  if ((originalWords.length - referenceWords.length).abs() > 1) {
    return false;
  }
  var originalIndex = 0;
  var referenceIndex = 0;
  var edits = 0;
  while (originalIndex < originalWords.length &&
      referenceIndex < referenceWords.length) {
    if (originalWords[originalIndex] == referenceWords[referenceIndex]) {
      originalIndex++;
      referenceIndex++;
    } else {
      if (++edits > 1) {
        return false;
      }
      if (originalWords.length >= referenceWords.length) {
        originalIndex++;
      }
      if (referenceWords.length >= originalWords.length) {
        referenceIndex++;
      }
    }
  }
  return edits +
          (originalWords.length - originalIndex) +
          (referenceWords.length - referenceIndex) <=
      1;
}

bool _hasVoicingPeriod(Float64List differences) {
  const correlationStart = _voicingFrameSize - _voicingMaxLag;
  var energy = 0.0;
  for (var i = correlationStart; i < _voicingFrameSize; i++) {
    energy += differences[i] * differences[i];
  }
  for (var lag = _voicingMinLag; lag <= _voicingMaxLag; lag++) {
    var dot = 0.0;
    var delayedEnergy = 0.0;
    for (var i = correlationStart; i < _voicingFrameSize; i++) {
      final delayed = differences[i - lag];
      dot += differences[i] * delayed;
      delayedEnergy += delayed * delayed;
    }
    if (dot > 0 &&
        dot * dot >=
            _voicingMinCorrelation *
                _voicingMinCorrelation *
                energy *
                delayedEnergy) {
      return true;
    }
  }
  return false;
}

/// RIFF/WAVE header byte length for PCM16 LE mono audio.
const int qwenWindowedWavHeaderBytes = 44;

/// Prompt used to decode a window of Qwen3-ASR audio.
enum QwenWindowPrompt {
  /// The normal Qwen3-ASR transcription instruction.
  instructed,

  /// Qwen3-ASR's reference prompt with an audio-only user turn.
  reference,
}

/// Decodes one bounded RIFF/WAVE interval for [QwenWindowedAsrSession].
typedef QwenWindowDecode =
    Future<String> Function(
      Uint8List wavBytes, {
      required QwenWindowPrompt prompt,
      required String confirmedPrefix,
      required void Function(void Function()? cancel) registerCancel,
      required bool Function() isCancelled,
    });

/// Selects the commit cut sample in `0..length` for a full window.
///
/// Scans 20 ms (320-sample) frames across `[96000, length)` and returns the
/// sample midpoint of the latest contiguous run of at least 5 quiet frames
/// (`>= 100 ms` with `RMS <= 0.01`), including a trailing quiet run that reaches
/// [length]. Returns [length] (hard cut) if no such run exists.
int selectQwenWindowCut(Float32List window, int length) {
  if (length <= qwenWindowedQuietSearchStartSample) {
    return length;
  }

  var runStart = 0;
  var runFrames = 0;
  int? latestMidpoint;

  var frameStart = qwenWindowedQuietSearchStartSample;
  while (frameStart + qwenWindowedQuietFrameSamples <= length) {
    var sumSquares = 0.0;
    final frameEnd = frameStart + qwenWindowedQuietFrameSamples;
    for (var i = frameStart; i < frameEnd; i++) {
      final sample = window[i];
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / qwenWindowedQuietFrameSamples);
    if (rms <= qwenWindowedQuietRmsThreshold) {
      if (runFrames == 0) {
        runStart = frameStart;
      }
      runFrames++;
    } else {
      if (runFrames >= qwenWindowedQuietMinFrames) {
        latestMidpoint = (runStart + frameStart) ~/ 2;
      }
      runFrames = 0;
    }
    frameStart = frameEnd;
  }

  if (runFrames >= qwenWindowedQuietMinFrames) {
    latestMidpoint = (runStart + length) ~/ 2;
  }

  return latestMidpoint ?? length;
}

/// Encodes `samples[0 .. length)` as mono 16 kHz PCM16 LE RIFF/WAVE into
/// [target] at [gain], limiting samples to [peakLimit], and returns a view of
/// the written bytes.
Uint8List encodePcm16WavInto(
  Float32List samples,
  int length,
  Uint8List target, {
  double gain = 1.0,
  double peakLimit = 1.0,
}) {
  final dataBytes = length * 2;
  final totalBytes = qwenWindowedWavHeaderBytes + dataBytes;
  final data = ByteData.sublistView(target, 0, totalBytes);

  // "RIFF"
  target[0] = 0x52;
  target[1] = 0x49;
  target[2] = 0x46;
  target[3] = 0x46;
  data.setUint32(4, 36 + dataBytes, Endian.little);
  // "WAVE"
  target[8] = 0x57;
  target[9] = 0x41;
  target[10] = 0x56;
  target[11] = 0x45;
  // "fmt "
  target[12] = 0x66;
  target[13] = 0x6D;
  target[14] = 0x74;
  target[15] = 0x20;
  data.setUint32(16, 16, Endian.little); // PCM subchunk size
  data.setUint16(20, 1, Endian.little); // PCM format
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, qwenWindowedSampleRateHz, Endian.little);
  data.setUint32(28, qwenWindowedSampleRateHz * 2, Endian.little);
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little); // bits per sample
  // "data"
  target[36] = 0x64;
  target[37] = 0x61;
  target[38] = 0x74;
  target[39] = 0x61;
  data.setUint32(40, dataBytes, Endian.little);

  for (var i = 0; i < length; i++) {
    final clamped = (samples[i] * gain).clamp(-peakLimit, peakLimit);
    final scaled = clamped < 0
        ? (clamped * 32768.0).round()
        : (clamped * 32767.0).round();
    data.setInt16(
      qwenWindowedWavHeaderBytes + i * 2,
      scaled.clamp(-32768, 32767),
      Endian.little,
    );
  }

  return Uint8List.sublistView(target, 0, totalBytes);
}

/// Joins adjacent nonempty window strings with a single newline.
String joinWindowTranscript(String base, String addition) {
  if (base.isEmpty) {
    return addition;
  }
  if (addition.isEmpty) {
    return base;
  }
  return '$base\n$addition';
}

/// Bounded windowed streaming session for Qwen3-ASR.
class QwenWindowedAsrSession implements SpeechToTextStreamingSession {
  final QwenWindowDecode _decodeWindow;
  final SpeechAudioFormat _sourceFormat;
  final void Function() _onClosed;
  final String? _emptyTranscriptDetails;

  final Float32List _ring = Float32List(qwenWindowedMaxSamples);
  final Uint8List _wavBuffer = Uint8List(
    qwenWindowedWavHeaderBytes + qwenWindowedMaxSamples * 2,
  );

  late final StreamController<SpeechToTextEvent> _events;
  final Completer<SpeechToTextCompletion> _done =
      Completer<SpeechToTextCompletion>();

  Future<void>? _inFlightPush;
  Future<String>? _activeDecode;
  Future<void>? _finishFuture;
  Future<void>? _cancelFuture;
  void Function()? _cancelActiveDecode;
  SpeechToTextPartialEvent? _pendingPartial;

  int _buffered = 0;
  int _acceptedSamples = 0;
  int _lastDecodedLength = 0;
  String _confirmedText = '';
  String _pendingText = '';

  bool _finishing = false;
  bool _recheckCurrentWindow = false;
  bool _cancelled = false;
  bool _closed = false;

  /// Creates a bounded windowed Qwen3-ASR session.
  QwenWindowedAsrSession({
    required QwenWindowDecode decodeWindow,
    required SpeechAudioFormat sourceFormat,
    required void Function() onClosed,
    String? emptyTranscriptDetails,
  }) : _decodeWindow = decodeWindow,
       _sourceFormat = sourceFormat,
       _onClosed = onClosed,
       _emptyTranscriptDetails = emptyTranscriptDetails {
    _events = StreamController<SpeechToTextEvent>(
      onListen: _flushPendingPartial,
      onResume: _flushPendingPartial,
    );
  }

  @override
  Stream<SpeechToTextEvent> get events => _events.stream;

  @override
  Future<SpeechToTextCompletion> get done => _done.future;

  @override
  Future<void> addPcm(Float32List samples) {
    if (_cancelled) {
      return Future<void>.error(
        LlamaStateException(
          'Cannot add audio after the speech stream has been cancelled.',
        ),
      );
    }
    if (_finishing || _closed) {
      return Future<void>.error(
        LlamaStateException(
          'Cannot add audio after the speech stream has finished.',
        ),
      );
    }
    if (_inFlightPush != null) {
      return Future<void>.error(
        LlamaStateException(
          'Another live speech recognition push is already in progress.',
        ),
      );
    }
    if (samples.isEmpty) {
      return Future<void>.value();
    }
    try {
      _validateSamples(samples);
    } on LlamaAudioFormatException catch (error, stackTrace) {
      return _failInvalidSlice(error, stackTrace);
    }

    final push = _runPush(samples);
    _inFlightPush = push;
    return push.whenComplete(() {
      if (identical(_inFlightPush, push)) {
        _inFlightPush = null;
      }
    });
  }

  static void _validateSamples(Float32List samples) {
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      if (!sample.isFinite || sample < -1.0 || sample > 1.0) {
        throw LlamaAudioFormatException(
          'Float PCM samples must be finite and normalized to [-1.0, 1.0].',
          'sample[$i]=$sample',
        );
      }
    }
  }

  Future<void> _failInvalidSlice(
    LlamaAudioFormatException error,
    StackTrace stackTrace,
  ) async {
    _finishing = true;
    await _fail(error, stackTrace);
    Error.throwWithStackTrace(error, stackTrace);
  }

  int _nextThreshold(int buffered) {
    if (buffered < qwenWindowedCheckpointStepSamples) {
      return qwenWindowedCheckpointStepSamples;
    }
    if (buffered < qwenWindowedCheckpointStepSamples * 2) {
      return qwenWindowedCheckpointStepSamples * 2;
    }
    if (buffered < qwenWindowedQuietSearchStartSample) {
      return qwenWindowedQuietSearchStartSample;
    }
    return qwenWindowedMaxSamples;
  }

  Future<void> _runPush(Float32List samples) async {
    try {
      var offset = 0;
      while (offset < samples.length) {
        if (_cancelled || _closed) {
          return;
        }
        final nextThreshold = _nextThreshold(_buffered);
        final take = math.min(
          samples.length - offset,
          nextThreshold - _buffered,
        );
        _ring.setRange(_buffered, _buffered + take, samples, offset);
        _buffered += take;
        _acceptedSamples += take;
        offset += take;

        if (_buffered == qwenWindowedMaxSamples) {
          final cut = selectQwenWindowCut(_ring, _buffered);
          final decoded = await _decodeInterval(cut);
          if (_cancelled || _closed) {
            return;
          }
          if (decoded.isNotEmpty) {
            _confirmedText = joinWindowTranscript(_confirmedText, decoded);
          }
          _pendingText = '';
          _lastDecodedLength = 0;
          _recheckCurrentWindow = false;
          final carry = _buffered - cut;
          if (carry > 0) {
            _ring.setRange(0, carry, _ring, cut);
          }
          _buffered = carry;
          _emitPartial();
        } else if (_buffered == qwenWindowedCheckpointStepSamples ||
            _buffered == qwenWindowedCheckpointStepSamples * 2 ||
            _buffered == qwenWindowedQuietSearchStartSample) {
          final decoded = await _decodeInterval(_buffered);
          if (_cancelled || _closed) {
            return;
          }
          _lastDecodedLength = _buffered;
          _pendingText = decoded;
          _emitPartial();
        }
      }
    } catch (error, stackTrace) {
      if (_cancelled) {
        return;
      }
      await _fail(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<String> _decodeInterval(int length) {
    final future = _decodeForPublication(length);
    _activeDecode = future;
    return future.whenComplete(() {
      if (identical(_activeDecode, future)) {
        _activeDecode = null;
      }
    });
  }

  Future<String> _decodeForPublication(int length) async {
    final decoded = await _decodeVerified(length);
    if (decoded.isEmpty || _cancelled || _closed) {
      return decoded;
    }
    final normalized = _normalizeInstruction(decoded);
    if (!_instructionHypotheses.contains(normalized) ||
        _hasChangingVoicing(length)) {
      return decoded;
    }

    // Re-encode from the ring because quiet verification may have amplified
    // the contents of the shared WAV buffer.
    final reference = await _decodeAtGain(
      length,
      1.0,
      prompt: QwenWindowPrompt.reference,
    );
    return _referenceAgrees(normalized, _normalizeInstruction(reference))
        ? decoded
        : '';
  }

  bool _hasChangingVoicing(int length) {
    final differences = Float64List(_voicingFrameSize);
    var changes = 0;
    int? previousCrossings;
    var previousSample = 0.0;
    for (
      var start = 0;
      start + qwenWindowedQuietFrameSamples <= length;
      start += qwenWindowedQuietFrameSamples
    ) {
      var sum = 0.0;
      var squares = 0.0;
      var crossings = 0;
      for (var k = 0; k < _voicingFrameSize; k++) {
        final i = start + k * _voicingDownsample;
        final sample =
            (_ring[i] + _ring[i + 1] + _ring[i + 2] + _ring[i + 3]) /
            _voicingDownsample;
        sum += sample;
        squares += sample * sample;
        differences[k] = i == 0 ? 0.0 : sample - previousSample;
        previousSample = sample;
        if (k > 0 && (differences[k] > 0) != (differences[k - 1] > 0)) {
          crossings++;
        }
      }
      final centeredEnergy = squares - sum * sum / _voicingFrameSize;
      if (centeredEnergy <
              _voicingFrameSize * _voicingMinRms * _voicingMinRms ||
          !_hasVoicingPeriod(differences)) {
        previousCrossings = null;
        continue;
      }
      // Stationary tones can be loud and periodic without changing voicing.
      if (previousCrossings != null &&
          (crossings - previousCrossings).abs() >= _voicingMinCrossingChange &&
          ++changes >= _voicingMinChanges) {
        return true;
      }
      previousCrossings = crossings;
    }
    return false;
  }

  Future<String> _decodeVerified(int length) async {
    final decoded = await _decodeAtGain(length, 1.0);
    if (decoded.isEmpty || _cancelled || _closed) {
      return decoded;
    }

    var sumSquares = 0.0;
    var quietFrames = 0;
    var frameCount = 0;
    for (
      var start = 0;
      start < length;
      start += qwenWindowedQuietFrameSamples
    ) {
      final end = math.min(start + qwenWindowedQuietFrameSamples, length);
      var frameSquares = 0.0;
      for (var i = start; i < end; i++) {
        final sample = _ring[i];
        frameSquares += sample * sample;
      }
      sumSquares += frameSquares;
      frameCount++;
      if (frameSquares <=
          (end - start) * _verificationFrameRms * _verificationFrameRms) {
        quietFrames++;
      }
    }
    // A majority of quiet frames tests the upper median without sorting.
    if (sumSquares == 0.0 ||
        (!_recheckCurrentWindow && quietFrames * 2 <= frameCount)) {
      return decoded;
    }

    // Amplified quiet noise can yield an empty decode even when the original
    // decode hallucinates. Keep checking the window after a rejection so a
    // subsequent decode cannot bypass verification by crossing the gate.
    final rms = math.sqrt(sumSquares / length);
    final gain = (0.02 / rms).clamp(1.0, 256.0);
    final verified = await _decodeAtGain(length, gain, peakLimit: 0.9);
    if (verified.isEmpty) {
      _recheckCurrentWindow = true;
      return '';
    }
    return decoded;
  }

  Future<String> _decodeAtGain(
    int length,
    double gain, {
    double peakLimit = 1.0,
    QwenWindowPrompt prompt = QwenWindowPrompt.instructed,
  }) async {
    final wavBytes = encodePcm16WavInto(
      _ring,
      length,
      _wavBuffer,
      gain: gain,
      peakLimit: peakLimit,
    );
    try {
      return await _decodeWindow(
        wavBytes,
        prompt: prompt,
        confirmedPrefix: _confirmedText,
        registerCancel: (cancel) {
          _cancelActiveDecode = cancel;
        },
        isCancelled: () => _cancelled || _closed,
      );
    } finally {
      _cancelActiveDecode = null;
    }
  }

  @override
  Future<void> finish() {
    final existing = _finishFuture;
    if (existing != null) {
      return existing;
    }
    if (_cancelled) {
      return Future<void>.error(
        LlamaStateException('Speech recognition was cancelled.'),
      );
    }
    if (_closed) {
      return _done.future.then((_) {});
    }
    _finishing = true;
    final future = _runFinish();
    _finishFuture = future;
    return future;
  }

  Future<void> _runFinish() async {
    try {
      final inFlight = _inFlightPush;
      if (inFlight != null) {
        await inFlight;
      }
      if (_cancelled || _closed) {
        return;
      }
      if (_buffered > 0) {
        final String tailText;
        if (_lastDecodedLength == _buffered) {
          tailText = _pendingText;
        } else {
          tailText = await _decodeInterval(_buffered);
        }
        if (_cancelled || _closed) {
          return;
        }
        if (tailText.isNotEmpty) {
          _confirmedText = joinWindowTranscript(_confirmedText, tailText);
        }
        _pendingText = '';
      }
      if (_confirmedText.isEmpty) {
        throw LlamaSpeechException(
          'Speech recognition produced an empty transcript.',
          _emptyTranscriptDetails,
        );
      }

      final result = SpeechToTextResult(
        text: _confirmedText,
        segments: <TranscriptSegment>[TranscriptSegment(text: _confirmedText)],
        sourceFormat: _sourceFormat,
        audioDuration: _durationForSamples(_acceptedSamples),
      );
      final pending = _pendingPartial;
      _pendingPartial = null;
      if (!_events.isClosed) {
        if (pending != null) {
          _events.add(pending);
        }
        _events.add(SpeechToTextFinalEvent(result));
      }
      await _close();
      if (!_done.isCompleted) {
        _done.complete(SpeechToTextCompletion.completed(result));
      }
    } catch (error, stackTrace) {
      if (_cancelled) {
        await _close();
        if (!_done.isCompleted) {
          _done.complete(const SpeechToTextCompletion.cancelled());
        }
        return;
      }
      await _fail(error, stackTrace);
    }
  }

  @override
  Future<void> cancel() {
    final existing = _cancelFuture;
    if (existing != null) {
      return existing;
    }
    _cancelled = true;
    _finishing = true;
    _pendingPartial = null;
    _cancelActiveDecode?.call();
    final future = _runCancel();
    _cancelFuture = future;
    return future;
  }

  Future<void> _runCancel() async {
    try {
      final activeDecode = _activeDecode;
      if (activeDecode != null) {
        try {
          await activeDecode;
        } catch (_) {
          // Cancellation may abort the active decode.
        }
      }
      final inFlight = _inFlightPush;
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {
          // Cancellation may abort the in-flight push.
        }
      }
    } finally {
      await _close();
      if (!_done.isCompleted) {
        _done.complete(const SpeechToTextCompletion.cancelled());
      }
    }
  }

  void _emitPartial() {
    if (_closed || _cancelled) {
      return;
    }
    final text = joinWindowTranscript(_confirmedText, _pendingText);
    final event = SpeechToTextPartialEvent(
      text,
      confirmedText: _confirmedText,
      pendingText: _pendingText,
      acceptedAudioDuration: _durationForSamples(_acceptedSamples),
    );
    if (!_events.hasListener || _events.isPaused) {
      _pendingPartial = event;
      return;
    }
    _events.add(event);
  }

  void _flushPendingPartial() {
    final pending = _pendingPartial;
    if (pending == null ||
        _closed ||
        _cancelled ||
        _events.isClosed ||
        !_events.hasListener ||
        _events.isPaused) {
      return;
    }
    _pendingPartial = null;
    _events.add(pending);
  }

  Duration _durationForSamples(int samples) => Duration(
    microseconds:
        (samples * Duration.microsecondsPerSecond) ~/ qwenWindowedSampleRateHz,
  );

  Future<void> _fail(Object error, StackTrace stackTrace) async {
    if (_closed) {
      return;
    }
    if (_cancelled) {
      await _close();
      if (!_done.isCompleted) {
        _done.complete(const SpeechToTextCompletion.cancelled());
      }
      return;
    }
    _pendingPartial = null;
    final speechError = error is LlamaException
        ? error
        : LlamaSpeechException('Speech recognition failed.', error);
    if (!_events.isClosed) {
      _events.addError(speechError, stackTrace);
    }
    await _close();
    if (!_done.isCompleted) {
      _done.complete(SpeechToTextCompletion.failed(speechError));
    }
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _pendingPartial = null;
    if (!_events.isClosed) {
      unawaited(_events.close());
    }
    _onClosed();
  }
}
