@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_bindings.dart'
    as sd;
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_calls.dart';
import 'package:llamadart/src/backends/stable_diffusion/stable_diffusion_log.dart';
import 'package:llamadart/src/core/models/config/log_level.dart';

/// A recorder that keeps the messages it is given, numbered from
/// [firstSequence], and answers like `sd_dart_log_read`.
final class _Recorder {
  _Recorder(this.messages, {this.firstSequence = 1, this.dropped = 0});

  final List<(int, List<int>)> messages;
  final int firstSequence;
  int dropped;
  final List<String> calls = [];
  final List<int> capacities = [];
  List<int> lastError = const [];

  late final StableDiffusionLogCalls log = StableDiffusionLogCalls(
    enable: () => calls.add('enable'),
    setLevel: (level) => calls.add('setLevel $level'),
    read: (after, text, capacity, level, length) {
      calls.add('read $after');
      capacities.add(capacity);
      final index = after < firstSequence ? 0 : after - firstSequence + 1;
      if (index >= messages.length) {
        return 0;
      }
      final (messageLevel, bytes) = messages[index];
      text.cast<Uint8>().asTypedList(capacity)
        ..setAll(0, bytes)
        ..[bytes.length] = 0;
      level.value = messageLevel;
      return firstSequence + index;
    },
    dropped: () {
      calls.add('dropped');
      return dropped;
    },
    lastError: (text, capacity) {
      calls.add('lastError');
      capacities.add(capacity);
      text.cast<Uint8>().asTypedList(capacity)
        ..setAll(0, lastError)
        ..[lastError.length] = 0;
      return lastError.length;
    },
  );
}

void main() {
  test('each log level records from its own sd_log_level_t, and none '
      'records nothing', () {
    expect(
      {
        for (final level in LlamaLogLevel.values)
          level: stableDiffusionLogThreshold(level),
      },
      {
        LlamaLogLevel.none: 5,
        LlamaLogLevel.debug: 0,
        LlamaLogLevel.info: 2,
        LlamaLogLevel.warn: 3,
        LlamaLogLevel.error: 4,
      },
    );
    expect(
      stableDiffusionLogThreshold(LlamaLogLevel.none),
      greaterThan(sd.sd_log_level_t.SD_LOG_ERROR.value),
    );
  });

  test('a recorded message gets the level of its sd_log_level_t, with '
      'verbose as debug and anything above error as an error', () {
    expect(
      [
        for (var level = -1; level <= 6; level++)
          stableDiffusionLogLevel(level),
      ],
      [
        LlamaLogLevel.debug,
        LlamaLogLevel.debug,
        LlamaLogLevel.debug,
        LlamaLogLevel.info,
        LlamaLogLevel.warn,
        LlamaLogLevel.error,
        LlamaLogLevel.error,
        LlamaLogLevel.error,
      ],
    );
    for (final level in LlamaLogLevel.values.skip(1)) {
      expect(
        stableDiffusionLogLevel(stableDiffusionLogThreshold(level)),
        level,
      );
    }
  });

  test('recording enables the recorder, then sets its level', () {
    final recorder = _Recorder([]);

    recordStableDiffusionLog(recorder.log, LlamaLogLevel.warn);
    recordStableDiffusionLog(recorder.log, LlamaLogLevel.none);

    expect(recorder.calls, ['enable', 'setLevel 3', 'enable', 'setLevel 5']);
  });

  test('text ends at its terminator, and malformed UTF-8 decodes instead of '
      'throwing', () {
    using((arena) {
      final text = arena<Char>(16);
      final bytes = text.cast<Uint8>().asTypedList(16);

      bytes.setAll(0, [...utf8.encode('héllo'), 0, 0x41]);
      expect(stableDiffusionText(text, 16), 'héllo');

      // A lone continuation byte, and a sequence cut after its first byte.
      bytes.setAll(0, [0x61, 0x80, 0x62, 0xe2, 0]);
      expect(stableDiffusionText(text, 16), 'a\u{fffd}b\u{fffd}');

      bytes.fillRange(0, 16, 0x78);
      expect(stableDiffusionText(text, 16), 'x' * 16);
    });
  });

  group('drainStableDiffusionLog', () {
    test('reads the messages after the position in order until there are '
        'none, with a buffer that holds the longest message', () {
      final recorder = _Recorder([
        (2, utf8.encode('first')),
        (0, utf8.encode('second')),
        (4, utf8.encode('third')),
      ]);

      final drain = drainStableDiffusionLog(recorder.log, (
        after: 1,
        dropped: 0,
      ));

      expect(drain.messages, [
        (LlamaLogLevel.debug, 'second'),
        (LlamaLogLevel.error, 'third'),
      ]);
      expect(drain.position, (after: 3, dropped: 0));
      expect(drain.dropped, 0);
      expect(recorder.calls, ['read 1', 'read 2', 'read 3', 'dropped']);
      expect(recorder.capacities, everyElement(sd.SD_DART_LOG_TEXT_SIZE));
    });

    test('an empty log costs one read', () {
      final recorder = _Recorder([], dropped: 2);

      final drain = drainStableDiffusionLog(recorder.log, (
        after: 7,
        dropped: 2,
      ));

      expect(drain.messages, isEmpty);
      expect(drain.position, (after: 7, dropped: 2));
      expect(recorder.calls, ['read 7', 'dropped']);
    });

    test('continues behind the messages that left the buffer, and reports '
        'how many the runtime dropped since the last drain', () {
      final recorder = _Recorder(
        [(2, utf8.encode('kept'))],
        firstSequence: 40,
        dropped: 37,
      );

      final drain = drainStableDiffusionLog(recorder.log, (
        after: 3,
        dropped: 1,
      ));

      expect(drain.messages, [(LlamaLogLevel.info, 'kept')]);
      expect(drain.position, (after: 40, dropped: 37));
      expect(drain.dropped, 36);
    });

    test('stops at its read limit and leaves the rest for the next drain', () {
      final recorder = _Recorder([
        for (var i = 1; i <= 5; i++) (2, utf8.encode('message $i')),
      ]);

      final first = drainStableDiffusionLog(recorder.log, (
        after: 0,
        dropped: 0,
      ), maxReads: 2);
      final second = drainStableDiffusionLog(recorder.log, first.position);

      expect(first.messages.map((message) => message.$2), [
        'message 1',
        'message 2',
      ]);
      expect(second.messages.map((message) => message.$2), [
        'message 3',
        'message 4',
        'message 5',
      ]);
      expect(stableDiffusionLogReadsPerDrain, 4096);
    });
  });

  group('readStableDiffusionLastError', () {
    test('reads the errors with a buffer that holds all 32 of them', () {
      final recorder = _Recorder([])
        ..lastError = utf8.encode('first error\nsecond error');

      expect(
        readStableDiffusionLastError(recorder.log),
        'first error\nsecond error',
      );
      expect(recorder.capacities, [32 * 512]);
    });

    test('is empty when the runtime kept no error', () {
      expect(readStableDiffusionLastError(_Recorder([]).log), '');
    });

    test('decodes malformed UTF-8 instead of throwing', () {
      final recorder = _Recorder([])..lastError = [0x62, 0x61, 0x64, 0xff];

      expect(readStableDiffusionLastError(recorder.log), 'bad\u{fffd}');
    });
  });

  group('stableDiffusionPathRedactor', () {
    final redact = stableDiffusionPathRedactor({
      'model': '/Users/ada/models/sd/sdxs.gguf',
      'taesd': '/Users/ada/models/taesd.safetensors',
      'clipL': r'C:\Users\ada\cache\clip_l.gguf',
    });

    test('names each file by its role', () {
      expect(
        redact(
          "cannot inspect model source '/Users/ada/models/sd/sdxs.gguf': "
          'No such file or directory',
        ),
        "cannot inspect model source '<checkpoint file>': "
        'No such file or directory',
      );
      expect(
        redact(
          'loading /Users/ada/models/taesd.safetensors and '
          r'C:\Users\ada\cache\clip_l.gguf',
        ),
        'loading <taesd file> and <clipL file>',
      );
    });

    test('hides the directories of the files in other paths', () {
      expect(
        redact(
          'no /Users/ada/models/sd/sdxs.gguf.tmp beside '
          r'/Users/ada/models/other.bin or C:\Users\ada\cache\vae.bin',
        ),
        'no <checkpoint file>.tmp beside <model directory>/other.bin or '
        r'<model directory>\vae.bin',
      );
    });

    test('leaves a text without those paths alone', () {
      expect(
        redact("get sd version from file failed: ''"),
        "get sd version from file failed: ''",
      );
      expect(stableDiffusionPathRedactor({})('/any/path'), '/any/path');
    });
  });

  group('stableDiffusionFailureReason', () {
    String redact(String text) => text.replaceAll('/m/x.gguf', '<file>');

    test('joins the errors on one line without their paths', () {
      expect(
        stableDiffusionFailureReason(
          "model_loader.cpp:1061 - cannot inspect '/m/x.gguf'\n"
          'stable-diffusion.cpp:300 - init model loader from file failed',
          redact,
        ),
        "model_loader.cpp:1061 - cannot inspect '<file>'; "
        'stable-diffusion.cpp:300 - init model loader from file failed',
      );
    });

    test('removes control characters, empty lines and the padding of '
        'upstream\'s source locations', () {
      expect(
        stableDiffusionFailureReason(
          '\n  first\ttab\r\n\n\x1b[31msecond\x00\n'
          'diffusion_engine.cpp:727  - failed',
          redact,
        ),
        'first tab; [31msecond; diffusion_engine.cpp:727 - failed',
      );
    });

    test('is null when nothing is left', () {
      expect(stableDiffusionFailureReason('', redact), isNull);
      expect(stableDiffusionFailureReason(' \n\t\n', redact), isNull);
    });

    test('cuts a long reason to 1000 characters', () {
      final reason = stableDiffusionFailureReason('e' * 5000, redact)!;

      expect(reason, '${'e' * 1000}...');
    });
  });
}
