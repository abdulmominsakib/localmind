@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart/src/backends/llama_cpp/safetensors.dart';
import 'package:llamadart/src/core/exceptions.dart';
import 'package:test/test.dart';

import '../../../support/safetensors_writer.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('llamadart_safetensors_');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  String pathOf(String name) => '${dir.path}${Platform.pathSeparator}$name';

  SafetensorsFile openFile(String path) {
    final file = SafetensorsFile.open(path);
    addTearDown(file.close);
    return file;
  }

  Matcher modelError(List<String> parts) => isA<LlamaModelException>().having(
    (error) => error.message,
    'message',
    allOf([for (final part in parts) contains(part)]),
  );

  test('reads tensors, shapes and metadata', () {
    final path = pathOf('head.safetensors');
    writeSafetensors(
      path,
      {
        'a': TestTensor.f32([2, 3], [1, 2, 3, 4, 5, 6]),
        'b': TestTensor.f32([2], [-1.5, 0.25]),
      },
      metadata: {'laya.config': '{"head_layers": 2}'},
    );

    final file = openFile(path);

    expect(file.path, path);
    expect(file.metadata, {'laya.config': '{"head_layers": 2}'});
    expect(file.tensors.keys, ['a', 'b']);
    expect(file.tensors['a']!.dtype, 'F32');
    expect(file.tensors['a']!.shape, [2, 3]);
    expect(file.readFloat32('b'), [-1.5, 0.25]);
    expect(file.readFloat32('a'), [1, 2, 3, 4, 5, 6]);
  });

  test('converts F16 values, including subnormals and specials', () {
    final path = pathOf('f16.safetensors');
    const bits = [
      0x3c00,
      0xc000,
      0x3555,
      0x0001,
      0x03ff,
      0x0400,
      0x7bff,
      0x8000,
      0x7c00,
      0xfc00,
      0x7e00,
    ];
    writeSafetensors(path, {
      'h': TestTensor.bits16('F16', [11], bits),
    });

    final values = openFile(path).readFloat32('h');

    expect(values.sublist(0, 10), [
      1.0,
      -2.0,
      0.333251953125,
      5.960464477539063e-8,
      6.097555160522461e-5,
      6.103515625e-5,
      65504.0,
      -0.0,
      double.infinity,
      double.negativeInfinity,
    ]);
    expect(values[7].isNegative, isTrue);
    expect(values[10].isNaN, isTrue);
  });

  test('converts BF16 values', () {
    final path = pathOf('bf16.safetensors');
    writeSafetensors(path, {
      'h': TestTensor.bits16('BF16', [3], [0x3f80, 0xc049, 0x7f80]),
    });

    expect(openFile(path).readFloat32('h'), [1.0, -3.140625, double.infinity]);
  });

  test('reads into a view of native memory', () {
    final path = pathOf('into.safetensors');
    writeSafetensors(path, {
      'f32': TestTensor.f32([3], [1.5, -2, 0.25]),
      'f16': TestTensor.bits16('F16', [2], [0x3c00, 0xc000]),
      'bf16': TestTensor.bits16('BF16', [2], [0x3f80, 0xc049]),
    });
    final file = openFile(path);
    final native = malloc<Float>(4);
    addTearDown(() => malloc.free(native));
    final values = native.asTypedList(4)..fillRange(0, 4, 9);

    file.readFloat32Into('f32', Float32List.sublistView(values, 1));
    expect(values, [9, 1.5, -2, 0.25]);
    file.readFloat32Into('f16', Float32List.sublistView(values, 2));
    expect(values, [9, 1.5, 1, -2]);
    file.readFloat32Into('bf16', Float32List.sublistView(values, 1, 3));
    expect(values, [9, 1, -3.140625, -2]);
    expect(
      () => file.readFloat32Into('f32', values),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          allOf(contains('"f32" has 3 elements'), contains('has 4')),
        ),
      ),
    );
    expect(
      () => file.readFloat32Into('f32', Float32List.sublistView(values, 0, 2)),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message,
          'message',
          contains('has 2'),
        ),
      ),
    );
    expect(values, [9, 1, -3.140625, -2]);
  });

  test('has empty metadata when the header has none', () {
    final path = pathOf('plain.safetensors');
    writeSafetensors(path, {
      'a': TestTensor.f32([1], [3]),
    });

    expect(openFile(path).metadata, isEmpty);
  });

  test('rejects a missing tensor and dtypes it cannot convert', () {
    final path = pathOf('dtypes.safetensors');
    writeSafetensors(path, {
      'ids': TestTensor('I64', [1], Uint8List(8)),
      'packed': TestTensor('Q9', [5], Uint8List(3)),
    });
    final file = openFile(path);

    expect(
      () => file.readFloat32('missing'),
      throwsA(modelError([path, '"missing"'])),
    );
    expect(
      () => file.readFloat32('ids'),
      throwsA(modelError([path, '"ids"', 'I64'])),
    );
    expect(
      () => file.readFloat32('packed'),
      throwsA(modelError([path, '"packed"', 'Q9'])),
    );
  });

  test('rejects reads after close and closes idempotently', () {
    final path = pathOf('closed.safetensors');
    writeSafetensors(path, {
      'a': TestTensor.f32([1], [3]),
    });
    final file = SafetensorsFile.open(path)..close();

    file.close();
    expect(
      () => file.readFloat32('a'),
      throwsA(
        isA<LlamaStateException>().having(
          (error) => error.message,
          'message',
          contains(path),
        ),
      ),
    );
  });

  test('ignores a failed close', () {
    final path = pathOf('close_fails.safetensors');
    writeSafetensors(path, {
      'a': TestTensor.f32([1], [3]),
    });
    final opened = _CloseFails(File(path).openSync());
    final file = IOOverrides.runZoned(
      () => SafetensorsFile.open(path),
      createFile: (_) => _OpensTo(opened),
    );
    expect(file.readFloat32('a'), [3]);

    file.close();

    expect(opened.closed, isTrue);
    expect(() => file.readFloat32('a'), throwsA(isA<LlamaStateException>()));
  });

  test(
    'reports a file that shrinks after open',
    () async {
      final path = pathOf('shrunk.safetensors');
      writeSafetensors(path, {
        'a': TestTensor.f32([4], [1, 2, 3, 4]),
      });
      final reply = ReceivePort();
      addTearDown(reply.close);
      final reader = await Isolate.spawn(_readAfterShrinking, (
        path,
        reply.sendPort,
      ));
      addTearDown(() => reader.kill(priority: Isolate.immediate));

      expect(
        await reply.first.timeout(const Duration(seconds: 20)),
        allOf(contains(path), contains('ended 8 bytes into a 16-byte read')),
      );
    },
    skip: Platform.isWindows
        ? 'Windows file sharing can block rewriting a file that is open.'
        : false,
  );

  group('rejects malformed files', () {
    final tensor = jsonEncode({
      'a': {
        'dtype': 'F32',
        'shape': [2],
        'data_offsets': [0, 8],
      },
    });

    void expectMalformed(String path, List<String> parts) {
      expect(
        () => SafetensorsFile.open(path),
        throwsA(modelError([path, ...parts])),
      );
    }

    test('a missing file', () {
      expectMalformed(pathOf('absent.safetensors'), ['Cannot open']);
    });

    test('a file shorter than the header length', () {
      final path = pathOf('short.safetensors');
      File(path).writeAsBytesSync([1, 2, 3]);

      expectMalformed(path, ['3 bytes']);
    });

    test('a header length past the end of the file', () {
      final path = pathOf('truncated.safetensors');
      writeRawSafetensors(
        path,
        tensor,
        Uint8List(8),
        headerLength: tensor.length + 9,
      );

      expectMalformed(path, ['header length ${tensor.length + 9}']);
    });

    test('an oversized header length', () {
      final path = pathOf('oversized.safetensors');
      writeRawSafetensors(path, tensor, Uint8List(8), headerLength: -1);

      expectMalformed(path, ['header length 18446744073709551615']);
    });

    test('a header that is not a JSON object', () {
      final notJson = pathOf('not_json.safetensors');
      writeRawSafetensors(notJson, '{"a": ', const []);
      final list = pathOf('list.safetensors');
      writeRawSafetensors(list, '[1, 2]', const []);

      expectMalformed(notJson, ['UTF-8 JSON']);
      expectMalformed(list, ['not a JSON object']);
    });

    test('non-string metadata', () {
      final path = pathOf('metadata.safetensors');
      writeRawSafetensors(path, '{"__metadata__": {"n": 1}}', const []);

      expectMalformed(path, ['__metadata__']);
    });

    test('tensor entries without a dtype, shape or offsets', () {
      final cases = {
        'entry': ('{"a": 1}', 'tensor "a" is not a JSON object'),
        'dtype': (
          '{"a": {"shape": [], "data_offsets": [0, 0]}}',
          'tensor "a" has no string dtype',
        ),
        'shape': (
          '{"a": {"dtype": "F32", "shape": [-1, -1], "data_offsets": [0, 4]}}',
          'tensor "a" shape [-1, -1] is not a list of sizes',
        ),
        'offsets': (
          '{"a": {"dtype": "F32", "shape": [], "data_offsets": [0]}}',
          'tensor "a" data_offsets [0] is not [begin, end]',
        ),
        'offset types': (
          '{"a": {"dtype": "F32", "shape": [1], "data_offsets": ["0", 4]}}',
          'tensor "a" data_offsets [0, 4] is not [begin, end]',
        ),
      };
      for (final MapEntry(key: name, value: (header, reason))
          in cases.entries) {
        final path = pathOf('$name.safetensors');
        writeRawSafetensors(path, header, Uint8List(4));

        expectMalformed(path, [reason]);
      }
    });

    test('offsets outside the data section', () {
      final pastEnd = pathOf('past_end.safetensors');
      writeRawSafetensors(pastEnd, tensor, Uint8List(4));
      final reversed = pathOf('reversed.safetensors');
      writeRawSafetensors(
        reversed,
        '{"a": {"dtype": "U8", "shape": [0], "data_offsets": [4, 0]}}',
        Uint8List(4),
      );

      final negative = pathOf('negative.safetensors');
      writeRawSafetensors(
        negative,
        '{"a": {"dtype": "F32", "shape": [1], "data_offsets": [-4, 0]}}',
        Uint8List(4),
      );

      expectMalformed(pastEnd, ['[0, 8]', '4-byte data section']);
      expectMalformed(reversed, ['[4, 0]']);
      expectMalformed(negative, ['[-4, 0]']);
    });

    test('a byte span that disagrees with the dtype and shape', () {
      final path = pathOf('span.safetensors');
      writeRawSafetensors(
        path,
        '{"a": {"dtype": "F16", "shape": [3], "data_offsets": [0, 8]}}',
        Uint8List(8),
      );

      expectMalformed(path, ['F16 [3]', '8 bytes']);
    });

    test('shapes whose element count overflows', () {
      for (final shape in [
        [1 << 62],
        [4, 1 << 62],
        [1 << 32, 1 << 32],
        [2, 2, 1 << 62],
      ]) {
        final path = pathOf('overflow_${shape.length}_${shape.first}.bin');
        writeRawSafetensors(
          path,
          jsonEncode({
            'a': {
              'dtype': 'F32',
              'shape': shape,
              'data_offsets': [0, 0],
            },
          }),
          Uint8List(16),
        );

        expectMalformed(path, ['F32 $shape', '0 bytes']);
      }
    });

    test(
      'without leaking the file handle',
      () {
        final malformed = pathOf('leak.safetensors');
        writeRawSafetensors(malformed, '[1, 2]', const []);
        final truncated = pathOf('leak_truncated.safetensors');
        writeRawSafetensors(
          truncated,
          '{"a": {"dtype": "F32", "shape": [2], "data_offsets": [0, 8]}}',
          Uint8List(4),
        );
        int openDescriptors() => [
          for (var fd = 0; fd < 1024; fd++)
            if (FileStat.statSync('/dev/fd/$fd').type !=
                FileSystemEntityType.notFound)
              fd,
        ].length;

        final before = openDescriptors();
        for (var i = 0; i < 64; i++) {
          for (final path in [malformed, truncated]) {
            expect(
              () => SafetensorsFile.open(path),
              throwsA(isA<LlamaModelException>()),
            );
          }
        }

        expect(openDescriptors() - before, lessThan(16));
      },
      skip: Platform.isWindows
          ? 'Windows has no /dev/fd; deleting the temporary directory in '
                'tearDown fails there if a handle leaks.'
          : false,
    );
  });
}

void _readAfterShrinking((String, SendPort) message) {
  final (path, reply) = message;
  final file = SafetensorsFile.open(path);
  try {
    final bytes = File(path).readAsBytesSync();
    File(path).writeAsBytesSync(bytes.sublist(0, bytes.length - 8));
    file.readFloat32('a');
    reply.send('read the whole tensor');
  } on LlamaModelException catch (error) {
    reply.send(error.message);
  } finally {
    file.close();
  }
}

final class _OpensTo implements File {
  _OpensTo(this._opened);

  final RandomAccessFile _opened;

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) => _opened;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _CloseFails implements RandomAccessFile {
  _CloseFails(this._file);

  final RandomAccessFile _file;
  bool closed = false;

  @override
  int lengthSync() => _file.lengthSync();

  @override
  void setPositionSync(int position) => _file.setPositionSync(position);

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) =>
      _file.readIntoSync(buffer, start, end);

  @override
  void closeSync() {
    _file.closeSync();
    closed = true;
    throw const FileSystemException('Injected close failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
