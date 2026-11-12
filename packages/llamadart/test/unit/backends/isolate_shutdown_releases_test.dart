@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';

import 'package:llamadart/src/backends/isolate_shutdown_releases.dart';

// Each held object is a stdio stream appending to one file, freed by
// `fclose`. A stream's text stays in its buffer until it is closed, so the
// file shows which streams were freed, and in what order.
void main() {
  late Directory directory;
  late String file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('shutdown_releases_');
    file = '${directory.path}/log.txt';
    File(file).writeAsStringSync('');
  });

  tearDown(() => directory.deleteSync(recursive: true));

  test('frees held objects when their isolate shuts down, in stage '
      'order', () async {
    await Isolate.run(() {
      _hold(file, 'model ', ShutdownStage.model);
      _hold(file, 'context ', ShutdownStage.context);
      _hold(file, 'backend ', ShutdownStage.backend);
      _hold(file, 'session ', ShutdownStage.session);
      _hold(file, 'buffer ', ShutdownStage.modelUser);
      _hold(file, 'scheduler ', ShutdownStage.scheduler);
      _hold(file, 'model2 ', ShutdownStage.model);
    });

    // Each object goes before the objects it uses.
    expect(
      File(file).readAsStringSync(),
      'session scheduler context buffer backend model model2 ',
    );
  });

  test('does not free a released object', () async {
    final released = await Isolate.run(() {
      _hold(file, 'kept ', ShutdownStage.context);
      final stream = _hold(file, 'released ', ShutdownStage.session);
      IsolateShutdownReleases.current.release(stream);
      return stream.address;
    });

    expect(File(file).readAsStringSync(), 'kept ');
    _fclose(Pointer.fromAddress(released));
    expect(File(file).readAsStringSync(), 'kept released ');
  });

  test('ignores a null object and an object it does not hold', () async {
    await Isolate.run(() {
      final releases = IsolateShutdownReleases.current;
      releases.hold(ShutdownStage.model, _fcloseAddress, nullptr);
      releases.release(Pointer<Void>.fromAddress(8));
      _hold(file, 'held ', ShutdownStage.model);
    });

    expect(File(file).readAsStringSync(), 'held ');
  });
}

Pointer<Void> _hold(String file, String text, ShutdownStage stage) {
  final stream = using((arena) {
    final opened = _fopen(
      file.toNativeUtf8(allocator: arena),
      'a'.toNativeUtf8(allocator: arena),
    );
    _fputs(text.toNativeUtf8(allocator: arena), opened);
    return opened;
  });
  IsolateShutdownReleases.current.hold(stage, _fcloseAddress, stream);
  return stream;
}

final DynamicLibrary _libc = Platform.isWindows
    ? DynamicLibrary.open('ucrtbase.dll')
    : DynamicLibrary.process();

final Pointer<Void> Function(Pointer<Utf8> path, Pointer<Utf8> mode) _fopen =
    _libc.lookupFunction<
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>),
      Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>)
    >('fopen');

final int Function(Pointer<Utf8> text, Pointer<Void> stream) _fputs = _libc
    .lookupFunction<
      Int Function(Pointer<Utf8>, Pointer<Void>),
      int Function(Pointer<Utf8>, Pointer<Void>)
    >('fputs');

final int Function(Pointer<Void> stream) _fclose = _libc
    .lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'fclose',
    );

final Pointer<NativeFinalizerFunction> _fcloseAddress = _libc.lookup('fclose');
