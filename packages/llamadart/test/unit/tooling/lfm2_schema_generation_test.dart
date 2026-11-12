@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../support/lfm2_schema_generation.dart' as capture;

void main() {
  late Directory directory;
  late Map<String, dynamic> row;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('lfm-generation-contract-');
    File('${directory.path}/existing.gguf').writeAsBytesSync([1]);
    row = {
      'set': 'fixture',
      'key': 'original',
      'model': 'existing.gguf',
      'system': 'Use a tool.',
      'prompt': 'Copy this.',
      'choice': 'auto',
      'parallel': false,
      'thinking': false,
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'clock',
            'description': 'Return time.',
            'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
          },
        },
      ],
      'sampling': <String, dynamic>{
        'maxTokens': 16,
        'temp': 0.0,
        'seed': 7,
        'topK': 40,
        'topP': 0.9,
        'minP': 0.0,
        'penalty': 1.1,
      },
    };
    addTearDown(() => directory.deleteSync(recursive: true));
  });

  Future<ProcessResult> run(List<Map<String, dynamic>> rows) async {
    final manifest = File('${directory.path}/manifest.json')
      ..writeAsStringSync(jsonEncode(rows));
    return Process.run('dart', [
      'run',
      'test/support/lfm2_schema_generation.dart',
      manifest.path,
      '${directory.path}/output.json',
      directory.path,
      'python',
      '--dry-run',
    ]);
  }

  test('live snapshot omits a row until parser replay finishes', () {
    final output = File('${directory.path}/output.json');
    final captures = <Map<String, dynamic>>[];
    final first = <String, dynamic>{'id': 'first', 'raw': 'first raw'};
    capture.recordLfm2Capture(
      output,
      captures,
      first,
      replay: (_) {
        expect(output.existsSync(), isFalse);
        expect(captures, isEmpty);
        expect(
          jsonDecode(File('${output.path}.jsonl').readAsStringSync()),
          first,
        );
        return {
          'calls': ['first call'],
        };
      },
    );
    final previous = output.readAsStringSync();
    final second = <String, dynamic>{'id': 'second', 'raw': 'second raw'};
    capture.recordLfm2Capture(
      output,
      captures,
      second,
      replay: (_) {
        // A polling monitor sees the complete previous snapshot during replay.
        expect(output.readAsStringSync(), previous);
        expect(captures, [first]);
        return {
          'calls': ['second call'],
        };
      },
    );
    final published = jsonDecode(output.readAsStringSync()) as List;
    expect(published.length, 2);
    expect(
      published.every((row) => (row as Map).containsKey('result')),
      isTrue,
    );
    expect(File('${output.path}.tmp').existsSync(), isFalse);
  });

  test('captured email wire publishes its production parser result', () {
    final output = File('${directory.path}/output.json');
    final record = <String, dynamic>{
      'id': 'email',
      'raw':
          r'<|tool_call_start|>[save_note(text="\w+@\w+\.com")]<|tool_call_end|>',
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'save_note',
            'description': 'Saves a note.',
            'parameters': {
              'type': 'object',
              'properties': {
                'text': {'type': 'string'},
              },
              'required': ['text'],
            },
          },
        },
      ],
    };
    capture.recordLfm2Capture(output, [], record);
    final published = (jsonDecode(output.readAsStringSync()) as List).single;
    expect(published['result']['calls'], [
      {
        'name': 'save_note',
        'arguments': {'text': r'\w+@\w+\.com'},
      },
    ]);
    expect(published.containsKey('error'), isFalse);
    expect(published['raw'], record['raw']);
  });

  test(
    'failed replay publishes an explicit error while retaining raw bytes',
    () {
      final output = File('${directory.path}/output.json');
      final captures = <Map<String, dynamic>>[];
      capture.recordLfm2Capture(
        output,
        captures,
        {'id': 'broken', 'raw': 'original raw bytes'},
        replay: (_) {
          expect(output.existsSync(), isFalse);
          throw const FormatException('deliberate parser failure');
        },
      );
      final published = (jsonDecode(output.readAsStringSync()) as List).single;
      expect(published['raw'], 'original raw bytes');
      expect(published['result'], isNull);
      expect(published['error']['type'], 'FormatException');
      expect(
        published['error']['message'],
        contains('deliberate parser failure'),
      );
      final rawJournal = jsonDecode(
        File('${output.path}.jsonl').readAsStringSync(),
      );
      expect(rawJournal['raw'], 'original raw bytes');
      expect(rawJournal.containsKey('result'), isFalse);
      expect(rawJournal.containsKey('error'), isFalse);
    },
  );

  test(
    'capture dry-run validates original declarations without loading weights',
    () async {
      final result = await run([row]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(result.stdout, contains('"tools_and_sampling":"validated"'));
      expect(File('${directory.path}/output.json').existsSync(), isFalse);
    },
  );

  test('capture rejects dropped sampling metadata before generation', () async {
    (row['sampling'] as Map).remove('seed');
    final result = await run([row]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Incomplete sampling metadata'));
    expect(File('${directory.path}/output.json').existsSync(), isFalse);
  });

  test(
    'capture rejects changed tool reconstruction before generation',
    () async {
      final function =
          ((row['tools'] as List).single as Map)['function'] as Map;
      (function['parameters'] as Map)['additionalProperties'] = false;
      final result = await run([row]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Tool reconstruction changed'));
    },
  );

  test('capture rejects duplicate row identities before generation', () async {
    final result = await run([row, row]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Duplicate capture identity'));
  });

  test('capture rejects sampling type changes before generation', () async {
    (row['sampling'] as Map)['seed'] = '7';
    final result = await run([row]);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Invalid original sampling'));
  });
}
