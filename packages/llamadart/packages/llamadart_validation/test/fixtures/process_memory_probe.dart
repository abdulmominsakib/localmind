import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llamadart_validation/src/process_memory.dart';
import 'package:llamadart_validation/src/process_memory_linux.dart';
import 'package:llamadart_validation/src/speech_runner.dart';

/// Prints resident set and footprint samples as JSON, in a process of its own
/// so no other test suite moves them.
///
/// `dirty <kind> <bytes>` samples before dirtying that many bytes of [allocate]
/// memory, after, and after Windows trims the working set, [_rounds] times so
/// the last round runs away from VM start-up. `mapped <file> <access>` maps
/// the file as [_mapped] describes. `leak <kind> <bytes>` runs
/// [runSpeechValidation] with an adapter whose every `load` leaks that many
/// dirtied bytes, and prints the memory bounds. `freed <bytes>` runs
/// [_freed].
Future<void> main(List<String> args) async {
  Map<String, int> sample() => {
    'rss': ProcessInfo.currentRss,
    'footprint': memoryFootprintBytes()!,
  };
  final samples = switch (args) {
    ['dirty', final kind, final size] => _dirty(kind, int.parse(size), sample),
    ['mapped', final path, final access] => _mapped(path, access, sample),
    ['leak', final kind, final size] => await _leak(kind, int.parse(size)),
    ['freed', final size] => _freed(int.parse(size)),
    _ => throw ArgumentError(
      'Usage: dirty <kind> <bytes> | mapped <file> <read|write|copy> | '
      'leak <kind> <bytes> | freed <bytes>',
    ),
  };
  stdout.writeln(jsonEncode(samples));
}

const _rounds = 3;

/// [size] bytes of `private` (`malloc`), `shared_anon`
/// (`MAP_SHARED | MAP_ANONYMOUS`), `memfd` (Linux `memfd_create`, mapped
/// shared) or `section` (a Windows pagefile-backed section) memory, all
/// dirtied and never freed, or `committed` Windows memory left unwritten.
Pointer<Uint8> allocate(String kind, int size) {
  final Pointer<Uint8> memory;
  switch (kind) {
    case 'private':
      memory = malloc<Uint8>(size);
    case 'shared_anon' || 'memfd':
      final libc = DynamicLibrary.process();
      final mmap = libc
          .lookupFunction<
            Pointer<Uint8> Function(
              Pointer<Void>,
              Size,
              Int32,
              Int32,
              Int32,
              Int64,
            ),
            Pointer<Uint8> Function(Pointer<Void>, int, int, int, int, int)
          >('mmap');
      const protReadWrite = 3, mapShared = 1;
      var fd = -1;
      var flags = mapShared;
      if (kind == 'memfd') {
        final name = 'leak'.toNativeUtf8();
        fd = libc
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Uint32),
              int Function(Pointer<Utf8>, int)
            >('memfd_create')(name, 0);
        malloc.free(name);
        final ftruncate = libc
            .lookupFunction<
              Int32 Function(Int32, Int64),
              int Function(int, int)
            >('ftruncate');
        if (fd < 0 || ftruncate(fd, size) != 0) {
          throw StateError('memfd_create failed');
        }
      } else {
        flags |= Platform.isMacOS ? 0x1000 : 0x20;
      }
      memory = mmap(nullptr, size, protReadWrite, flags, fd, 0);
      if (memory.address == -1) throw StateError('mmap failed');
    case 'section':
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final create = kernel32
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Uint32,
              Uint32,
              Pointer<Void>,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Void>,
              int,
              int,
              int,
              Pointer<Void>,
            )
          >('CreateFileMappingW');
      final map = kernel32
          .lookupFunction<
            Pointer<Uint8> Function(
              Pointer<Void>,
              Uint32,
              Uint32,
              Uint32,
              Size,
            ),
            Pointer<Uint8> Function(Pointer<Void>, int, int, int, int)
          >('MapViewOfFile');
      const pageReadWrite = 0x04, fileMapWrite = 0x02;
      final section = create(
        Pointer.fromAddress(-1),
        nullptr,
        pageReadWrite,
        size >> 32,
        size & 0xFFFFFFFF,
        nullptr,
      );
      if (section == nullptr) throw StateError('CreateFileMappingW failed');
      memory = map(section, fileMapWrite, 0, 0, size);
      if (memory == nullptr) throw StateError('MapViewOfFile failed');
    case 'committed':
      final virtualAlloc = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>, Size, Uint32, Uint32),
            Pointer<Uint8> Function(Pointer<Void>, int, int, int)
          >('VirtualAlloc');
      const memCommitReserve = 0x3000, pageReadWrite = 0x04;
      memory = virtualAlloc(nullptr, size, memCommitReserve, pageReadWrite);
      if (memory == nullptr) throw StateError('VirtualAlloc failed');
      return memory;
    default:
      throw ArgumentError('Unknown memory kind: $kind');
  }
  final bytes = memory.asTypedList(size);
  for (var offset = 0; offset < size; offset += 512) {
    bytes[offset] = offset >> 9 & 0xFF | 1;
  }
  return memory;
}

/// Asks Windows to trim this process's working set; elsewhere a no-op.
void _trimWorkingSet() {
  if (!Platform.isWindows) return;
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final process = kernel32
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetCurrentProcess',
      )();
  final empty = kernel32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('K32EmptyWorkingSet');
  if (empty(process) == 0) throw StateError('K32EmptyWorkingSet failed');
}

Map<String, Object> _dirty(
  String kind,
  int size,
  Map<String, int> Function() sample,
) {
  final rounds = <List<Map<String, int>>>[];
  for (var i = 0; i < _rounds; i++) {
    final before = sample();
    allocate(kind, size);
    final after = sample();
    _trimWorkingSet();
    rounds.add([before, after, sample()]);
  }
  return {'rounds': rounds};
}

/// Maps [path] for `read`, `write` (shared, so pages stay file-backed) or
/// `copy` (private, so written pages become the process's own).
Pointer<Uint8> _mapFile(String path, String access, int size) {
  if (Platform.isWindows) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final createFile = kernel32
        .lookupFunction<
          Pointer<Void> Function(
            Pointer<Utf16>,
            Uint32,
            Uint32,
            Pointer<Void>,
            Uint32,
            Uint32,
            Pointer<Void>,
          ),
          Pointer<Void> Function(
            Pointer<Utf16>,
            int,
            int,
            Pointer<Void>,
            int,
            int,
            Pointer<Void>,
          )
        >('CreateFileW');
    final createMapping = kernel32
        .lookupFunction<
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Void>,
            Uint32,
            Uint32,
            Uint32,
            Pointer<Void>,
          ),
          Pointer<Void> Function(
            Pointer<Void>,
            Pointer<Void>,
            int,
            int,
            int,
            Pointer<Void>,
          )
        >('CreateFileMappingW');
    final map = kernel32
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Void>, Uint32, Uint32, Uint32, Size),
          Pointer<Uint8> Function(Pointer<Void>, int, int, int, int)
        >('MapViewOfFile');
    const genericRead = 0x80000000, genericWrite = 0x40000000;
    const openExisting = 3, attributeNormal = 0x80;
    const pageReadOnly = 0x02, pageReadWrite = 0x04, pageWriteCopy = 0x08;
    const fileMapRead = 0x04, fileMapWrite = 0x02, fileMapCopy = 0x01;
    final nativePath = path.toNativeUtf16();
    final file = createFile(
      nativePath,
      access == 'write' ? genericRead | genericWrite : genericRead,
      0,
      nullptr,
      openExisting,
      attributeNormal,
      nullptr,
    );
    malloc.free(nativePath);
    if (file.address == -1) throw StateError('CreateFileW failed');
    final mapping = createMapping(
      file,
      nullptr,
      switch (access) {
        'write' => pageReadWrite,
        'copy' => pageWriteCopy,
        _ => pageReadOnly,
      },
      0,
      0,
      nullptr,
    );
    if (mapping == nullptr) throw StateError('CreateFileMappingW failed');
    final view = map(
      mapping,
      switch (access) {
        'write' => fileMapWrite,
        'copy' => fileMapCopy,
        _ => fileMapRead,
      },
      0,
      0,
      size,
    );
    if (view == nullptr) throw StateError('MapViewOfFile failed');
    return view;
  }
  final libc = DynamicLibrary.process();
  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('open');
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );
  final mmap = libc
      .lookupFunction<
        Pointer<Uint8> Function(
          Pointer<Void>,
          Size,
          Int32,
          Int32,
          Int32,
          Int64,
        ),
        Pointer<Uint8> Function(Pointer<Void>, int, int, int, int, int)
      >('mmap');
  const oReadOnly = 0, oReadWrite = 2, protRead = 1, protWrite = 2;
  const mapShared = 1, mapPrivate = 2;
  final nativePath = path.toNativeUtf8();
  final fd = open(nativePath, access == 'write' ? oReadWrite : oReadOnly);
  malloc.free(nativePath);
  if (fd < 0) throw StateError('open failed');
  final pages = mmap(
    nullptr,
    size,
    access == 'read' ? protRead : protRead | protWrite,
    access == 'copy' ? mapPrivate : mapShared,
    fd,
    0,
  );
  close(fd);
  if (pages.address == -1) throw StateError('mmap failed');
  return pages;
}

/// Drops the mapped [pages] from this process's resident set.
void _evict(Pointer<Uint8> pages, int size) {
  if (Platform.isWindows) {
    _trimWorkingSet();
    return;
  }
  final libc = DynamicLibrary.process();
  final call = libc
      .lookupFunction<
        Int32 Function(Pointer<Uint8>, Size, Int32),
        int Function(Pointer<Uint8>, int, int)
      >(Platform.isMacOS ? 'msync' : 'madvise');
  const msInvalidate = 2, madvDontNeed = 4;
  if (call(pages, size, Platform.isMacOS ? msInvalidate : madvDontNeed) != 0) {
    throw StateError('eviction failed');
  }
}

/// Samples before mapping [path] as `unmapped`, then, in each round, before
/// touching every page of the mapping, after, and after evicting it. `read`
/// reads each page; `write` and `copy` write each page and are not evicted.
Map<String, Object> _mapped(
  String path,
  String access,
  Map<String, int> Function() sample,
) {
  final size = File(path).lengthSync();
  final unmapped = sample();
  final pages = _mapFile(path, access, size);
  final bytes = pages.asTypedList(size);
  var sum = 0;
  final rounds = <List<Map<String, int>>>[];
  for (var i = 0; i < (access == 'read' ? _rounds : 1); i++) {
    final before = sample();
    sum = 0;
    for (var offset = 0; offset < size; offset += 4096) {
      if (access == 'read') {
        sum += bytes[offset];
      } else {
        bytes[offset] = 9;
      }
    }
    final touched = sample();
    if (access == 'read') _evict(pages, size);
    rounds.add([before, touched, sample()]);
  }
  return {'unmapped': unmapped, 'rounds': rounds, 'sum': sum};
}

/// Linux only. Samples the footprint, dirties [size] bytes of 64 KiB `malloc`
/// blocks and frees all but the last, so the allocator keeps the rest, then
/// reads `/proc/self/status` untrimmed before sampling the footprint again.
Map<String, int> _freed(int size) {
  const block = 64 * 1024;
  final before = memoryFootprintBytes()!;
  final blocks = [
    for (var i = 0; i < size ~/ block; i++) allocate('private', block),
  ];
  blocks.take(blocks.length - 1).forEach(malloc.free);
  final untrimmed = linuxFootprintFrom(
    File('/proc/self/status').readAsStringSync(),
  )!;
  return {
    'before': before,
    'untrimmed': untrimmed,
    'footprint': memoryFootprintBytes()!,
  };
}

Future<Map<String, Object?>> _leak(String kind, int size) async {
  final result = await runSpeechValidation(
    _LeakingSpeech(kind, size),
    operatingSystem: Platform.operatingSystem,
    backend: 'cpu',
  );
  Map<String, Object?> row(String id) => (result['checks'] as List)
      .cast<Map<String, Object?>>()
      .singleWhere((row) => row['id'] == id);
  final peak = row('peak_memory_bound');
  final leak = row('leak_slope_bound');
  return {
    'measurement': peak['measurement'],
    'peak_memory_bound': peak['status'],
    'peak_footprint_growth': peak['peak_footprint_growth'],
    'leak_slope_bound': leak['status'],
    'cycle_growth_bytes': leak['cycle_growth_bytes'],
    'slope_bytes_per_cycle': leak['slope_bytes_per_cycle'],
  };
}

/// Passes every lifecycle check, and leaks [size] bytes of [kind] memory on
/// each `load`.
final class _LeakingSpeech implements SpeechValidationAdapter {
  _LeakingSpeech(this.kind, this.size);

  final String kind;
  final int size;

  @override
  Future<void> load() async => allocate(kind, size);

  @override
  Future<void> dispose() async {}

  @override
  Future<Map<String, Object?>> execute({
    bool cancel = false,
    bool cancelImmediately = false,
    bool invalid = false,
    bool bytesInput = false,
  }) async {
    if (invalid) throw ArgumentError('invalid');
    if (cancelImmediately) {
      return {
        'cancelled': true,
        'cancel_latency_ms': 1.0,
        'cancel_after_ms': 0.0,
        'cancel_immediate': true,
      };
    }
    return {
      'predicate_passed': true,
      if (cancel) ...{
        'cancelled': true,
        'cancel_latency_ms': 1.0,
        'cancel_after_ms': 100.0,
        'cancel_in_flight': true,
      },
    };
  }
}
