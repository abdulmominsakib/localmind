import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Summarizes reporter intervals, which may overlap and are not CPU/billed time.
class NativeTestTiming {
  final String root;
  final Map<int, String> _suites = {};
  final Map<int, Map<String, Object?>> _tests = {};
  bool _started = false;
  bool _done = false;
  bool? _success;
  int _lastTime = 0;

  NativeTestTiming(this.root);

  void add(Map<String, dynamic> event) {
    final int time = event['time'] as int;
    if (time < 0 ||
        time < _lastTime ||
        _done ||
        (!_started && event['type'] != 'start')) {
      throw const FormatException('Invalid reporter event order');
    }
    _lastTime = time;
    switch (event['type']) {
      case 'start':
        if (_started) {
          throw const FormatException('Duplicate reporter start');
        }
        _started = true;
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        final id = suite['id'] as int;
        if (_suites.containsKey(id)) {
          throw const FormatException('Duplicate suite');
        }
        final source = suite['path'] as String?;
        final relative = source == null
            ? null
            : path.relative(source, from: root);
        _suites[id] =
            relative != null &&
                !path.isAbsolute(relative) &&
                relative != '..' &&
                !relative.startsWith('..${path.separator}')
            ? path.split(relative).join('/')
            : '<external-or-loading-suite>';
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        final id = test['id'] as int;
        if (_tests.containsKey(id)) {
          throw const FormatException('Duplicate test start');
        }
        final suiteId = test['suiteID'] as int;
        if (!_suites.containsKey(suiteId)) {
          throw const FormatException('Unknown suite');
        }
        _tests[id] = {
          'id': id,
          'suiteId': suiteId,
          'line': test['line'] as int?,
          'startMs': time,
          'durationMs': null,
          'result': null,
          'hidden': null,
          'skipped': null,
        };
      case 'testDone':
        final test = _tests[event['testID']];
        if (test == null || test['durationMs'] != null) {
          throw const FormatException('Unpaired test completion');
        }
        test['durationMs'] = time - (test['startMs'] as int);
        // Errors may arrive after testDone; never overwrite one with success.
        test['result'] ??= event['result'] as String;
        test['hidden'] = test['result'] != 'success'
            ? false
            : event['hidden'] as bool;
        test['skipped'] = event['skipped'] as bool;
      case 'error':
        final test = _tests[event['testID']];
        if (test == null) {
          throw const FormatException('Error for unknown test');
        }
        test['result'] = event['isFailure'] == true ? 'failure' : 'error';
        test['hidden'] = false;
      case 'done':
        _done = true;
        _success = event['success'] as bool?;
    }
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'complete':
        _done &&
        _success != null &&
        _tests.values.every((test) => test['durationMs'] != null),
    'success': _success,
    'reporterElapsedMs': _lastTime,
    'intervalMeaning':
        'Reporter wall intervals can overlap; excludes startup '
        'before the reporter and is not CPU, billing or build-hook time.',
    'suites': [
      for (final entry in _suites.entries)
        {'id': entry.key, 'path': entry.value},
    ],
    'tests': _tests.values.toList(),
  };
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: native_test_timing.dart <events.jsonl> <summary.json>',
    );
    exitCode = 64;
    return;
  }
  final timing = NativeTestTiming(Directory.current.path);
  final output = File(arguments[1]);
  try {
    if (path.equals(File(arguments[0]).absolute.path, output.absolute.path)) {
      throw const FormatException('Input and output must differ');
    }
    if (await output.exists()) await output.delete();
    await for (final line in File(
      arguments[0],
    ).openRead().transform(utf8.decoder).transform(const LineSplitter())) {
      timing.add(jsonDecode(line) as Map<String, dynamic>);
    }
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(timing.toJson())}\n',
    );
  } on Object {
    // Reporter messages/errors may contain credentials or machine paths.
    stderr.writeln(
      'Native timing report unavailable: invalid or missing input.',
    );
    exitCode = 1;
  }
}
