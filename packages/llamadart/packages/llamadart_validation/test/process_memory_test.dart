import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:llamadart_validation/src/process_memory.dart';
import 'package:llamadart_validation/src/process_memory_darwin.dart';
import 'package:llamadart_validation/src/process_memory_io.dart'
    show footprintCounterFor, sampleFootprint;
import 'package:llamadart_validation/src/process_memory_linux.dart';
import 'package:llamadart_validation/src/process_memory_windows.dart';
import 'package:test/test.dart';

const mib = 1024 * 1024;

/// `/proc/self/status` from Linux 6.8, trimmed.
const linuxStatus = '''
Name:\tdart
Umask:\t0022
State:\tS (sleeping)
VmPeak:\t 3050212 kB
VmSize:\t 2983540 kB
VmHWM:\t  402940 kB
VmRSS:\t  398212 kB
RssAnon:\t  150020 kB
RssFile:\t  247168 kB
RssShmem:\t    1024 kB
VmData:\t  612300 kB
VmSwap:\t    2048 kB
HugetlbPages:\t       0 kB
Threads:\t12
''';

/// `/proc/self/status` from Linux 4.4, which has no `RssAnon` or `RssShmem`,
/// trimmed.
const linux44Status = '''
Name:\tdart
VmHWM:\t  402940 kB
VmRSS:\t  398212 kB
VmData:\t  612300 kB
VmSwap:\t       0 kB
Threads:\t12
''';

/// Zeroes a [TaskVmInfoRev1] and writes [value] as 8 bytes at [offset].
TaskVmInfoRev1 taskVmInfoWith(
  Pointer<TaskVmInfoRev1> memory,
  int offset,
  int value,
) {
  final size = sizeOf<TaskVmInfoRev1>();
  memory.cast<Uint8>().asTypedList(size).fillRange(0, size, 0);
  (memory.cast<Uint8>() + offset).cast<Uint64>().value = value;
  return memory.ref;
}

void main() {
  group('Linux /proc/self/status', () {
    test('sums RssAnon, RssShmem and VmSwap, ignoring file pages', () {
      expect(linuxFootprintFrom(linuxStatus), (150020 + 1024 + 2048) * 1024);
    });
    test('without a RssShmem line is unmeasurable', () {
      expect(
        linuxFootprintFrom(
          linuxStatus.replaceFirst(RegExp('RssShmem.*\n'), ''),
        ),
        isNull,
      );
    });
    test('without a VmSwap line is unmeasurable', () {
      expect(
        linuxFootprintFrom(linuxStatus.replaceFirst(RegExp('VmSwap.*\n'), '')),
        isNull,
      );
    });
    test('without RssAnon, as before Linux 4.5, is unmeasurable', () {
      expect(linuxFootprintFrom(linux44Status), isNull);
    });
    test('a value without a kB unit is unmeasurable', () {
      expect(
        linuxFootprintFrom(linuxStatus.replaceFirst('150020 kB', '150020')),
        isNull,
      );
    });
    test('calls malloc_trim(0) before each read, and says so', () {
      final calls = <String>[];
      final counter = linuxCounterFrom(
        (pad) {
          calls.add('trim $pad');
          return 1;
        },
        () {
          calls.add('read');
          return 7;
        },
      );
      expect(counter.source, linuxFootprintSource);
      expect(counter.source, endsWith('after malloc_trim(0)'));
      expect(counter.read(), 7);
      expect(counter.read(), 7);
      expect(calls, ['trim 0', 'read', 'trim 0', 'read']);
    });
    test(
      'without malloc_trim, as on Android, reads untrimmed, and says so',
      () {
        int? read() => 7;
        final counter = linuxCounterFrom(null, read);
        expect(counter.source, linuxUntrimmedFootprintSource);
        expect(counter.source, contains('malloc_trim unavailable'));
        expect(identical(counter.read, read), isTrue);
      },
    );
    test('glibc provides malloc_trim to this process', () {
      expect(lookUpMallocTrim(DynamicLibrary.process()), isNotNull);
      expect(linuxSource(), linuxFootprintSource);
    }, testOn: 'linux');
    test('a process without malloc_trim reads untrimmed', () {
      expect(lookUpMallocTrim(DynamicLibrary.process()), isNull);
      expect(linuxSource(), linuxUntrimmedFootprintSource);
    }, testOn: 'mac-os');
  });

  group('Darwin task_vm_info', () {
    test('matches the revision 1 layout of <mach/task_info.h>', () {
      expect(taskVmInfoFlavor, 22);
      expect(taskVmInfoRev1Count, 38);
      expect(sizeOf<TaskVmInfoRev1>(), taskVmInfoRev1Count * 4);
      final memory = calloc<TaskVmInfoRev1>();
      addTearDown(() => calloc.free(memory));
      expect(
        taskVmInfoWith(memory, 144, 0x1234567890).physFootprint,
        0x1234567890,
      );
      expect(taskVmInfoWith(memory, 120, 77).compressed, 77);
      expect(taskVmInfoWith(memory, 16, 99).residentSize, 99);
    });
    test('matches the offsets the macOS SDK compiles', () async {
      final dir = await Directory.systemTemp.createTemp('task_vm_info');
      addTearDown(() => dir.delete(recursive: true));
      final source = File('${dir.path}/layout.c')
        ..writeAsStringSync('''
#include <stddef.h>
#include <stdio.h>
#include <mach/mach.h>
int main(void) {
  printf("%d %d %zu %zu %zu", TASK_VM_INFO, (int)TASK_VM_INFO_REV1_COUNT,
         offsetof(task_vm_info_data_t, phys_footprint),
         offsetof(task_vm_info_data_t, compressed),
         offsetof(task_vm_info_data_t, min_address));
  return 0;
}
''');
      final binary = '${dir.path}/layout';
      final compiled = await Process.run('cc', [source.path, '-o', binary]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      final printed = (await Process.run(binary, [])).stdout as String;
      expect(printed, '$taskVmInfoFlavor $taskVmInfoRev1Count 144 120 152');
    }, testOn: 'mac-os');
    test('reads phys_footprint only from a call that filled it', () {
      final memory = calloc<TaskVmInfoRev1>();
      addTearDown(() => calloc.free(memory));
      final info = taskVmInfoWith(memory, 144, 4096);
      expect(darwinFootprintFrom(0, taskVmInfoRev1Count, info), 4096);
      expect(darwinFootprintFrom(0, 93, info), 4096);
      expect(darwinFootprintFrom(5, taskVmInfoRev1Count, info), isNull);
      expect(darwinFootprintFrom(0, taskVmInfoRev1Count - 1, info), isNull);
    });
  });

  group('Windows PROCESS_MEMORY_COUNTERS_EX2', () {
    test('matches the <psapi.h> layout', () {
      final word = sizeOf<IntPtr>();
      expect(sizeOf<ProcessMemoryCountersEx2>(), 8 + 10 * word + 8);
      final memory = calloc<ProcessMemoryCountersEx2>();
      addTearDown(() => calloc.free(memory));
      final bytes = memory.cast<Uint8>();
      memory.ref
        ..cb = 1
        ..privateUsage = 0x1234
        ..privateWorkingSetSize = 0x5678
        ..sharedCommitUsage = 0x9abc;
      int sizeAt(int offset) => word == 8
          ? (bytes + offset).cast<Uint64>().value
          : (bytes + offset).cast<Uint32>().value;
      expect(bytes.cast<Uint32>().value, 1);
      expect(sizeAt(8 + 8 * word), 0x1234);
      expect(sizeAt(8 + 9 * word), 0x5678);
      expect((bytes + 8 + 10 * word).cast<Uint64>().value, 0x9abc);
    });
    test('the fallback PROCESS_MEMORY_COUNTERS_EX matches <psapi.h>', () {
      final word = sizeOf<IntPtr>();
      expect(sizeOf<ProcessMemoryCountersEx>(), 8 + 9 * word);
      final memory = calloc<ProcessMemoryCountersEx>();
      addTearDown(() => calloc.free(memory));
      memory.ref.privateUsage = 0x1234;
      final privateUsage = memory.cast<Uint8>() + (8 + 8 * word);
      expect(
        word == 8
            ? privateUsage.cast<Uint64>().value
            : privateUsage.cast<Uint32>().value,
        0x1234,
      );
      expect(windowsPrivateFootprintFrom(1, memory.ref), 0x1234);
      expect(windowsPrivateFootprintFrom(0, memory.ref), isNull);
    });
    test('falls back to PrivateUsage, named, when EX2 does not measure', () {
      int? shared() => 3;
      int? private() => 2;
      for (final unavailable in [() => null, () => throw StateError('EX2')]) {
        final counter = windowsCounterFrom(unavailable, private);
        expect(counter.source, windowsPrivateFootprintSource);
        expect(identical(counter.read, private), isTrue);
      }
      final counter = windowsCounterFrom(shared, private);
      expect(counter.source, windowsFootprintSource);
      expect(identical(counter.read, shared), isTrue);
      expect(
        windowsPrivateFootprintSource,
        contains('pagefile-backed shared sections are not counted'),
      );
    });
    test('the fallback counter measures this process', () {
      final counter = windowsCounterFrom(
        () => null,
        readWindowsPrivateFootprint,
      );
      expect(counter.source, windowsPrivateFootprintSource);
      expect(counter.read(), isPositive);
      expect(counter.read()!, lessThanOrEqualTo(readWindowsSharedFootprint()!));
    }, testOn: 'windows');
    test('a call that leaves SharedCommitUsage unwritten measures nothing', () {
      int fill(Pointer<Void> memory, int size, {int? shared}) {
        final counters = memory.cast<ProcessMemoryCountersEx2>().ref;
        expect(counters.cb, size);
        counters.privateUsage = 8192;
        if (shared != null) counters.sharedCommitUsage = shared;
        return 1;
      }

      expect(
        readProcessMemoryCounters(windowsFootprintFrom, call: fill),
        isNull,
      );
      expect(
        readProcessMemoryCounters(
          windowsFootprintFrom,
          call: (memory, size) => fill(memory, size, shared: 4096),
        ),
        12288,
      );
    });
    test('sums PrivateUsage and SharedCommitUsage from a filled call', () {
      final memory = calloc<ProcessMemoryCountersEx2>();
      addTearDown(() => calloc.free(memory));
      memory.ref
        ..privateUsage = 8192
        ..privateWorkingSetSize = 1
        ..sharedCommitUsage = 4096;
      expect(windowsFootprintFrom(1, memory.ref), 12288);
      expect(windowsFootprintFrom(0, memory.ref), isNull);
      memory.ref.sharedCommitUsage = windowsUnfilledSentinel;
      expect(windowsFootprintFrom(1, memory.ref), isNull);
    });
  });

  group('counter selection', () {
    test('names the counter each platform reads', () {
      for (final os in ['macos', 'ios']) {
        final counter = footprintCounterFor(os)!;
        expect(counter.source, darwinFootprintSource, reason: os);
        expect(identical(counter.read, readDarwinFootprint), isTrue);
      }
      for (final os in ['linux', 'android']) {
        final counter = footprintCounterFor(os)!;
        expect(identical(counter.describe, linuxSource), isTrue, reason: os);
        expect(identical(counter.read, readLinuxFootprint), isTrue, reason: os);
      }
      final windows = footprintCounterFor('windows')!;
      expect(identical(windows.describe, windowsSource), isTrue);
      expect(identical(windows.read, readWindowsFootprint), isTrue);
      expect(footprintCounterFor('fuchsia'), isNull);
      expect(footprintCounterFor(''), isNull);
    });
    test('a failing, absent or empty counter samples null', () {
      expect(sampleFootprint(null), isNull);
      expect(sampleFootprint(() => throw StateError('no counter')), isNull);
      expect(sampleFootprint(() => null), isNull);
      expect(sampleFootprint(() => 0), isNull);
      expect(sampleFootprint(() => -1), isNull);
      expect(sampleFootprint(() => 1), 1);
    });
  });

  group('this process', () {
    // Precompiled, so no front end compiles source inside the probe and moves
    // its footprint by hundreds of MiB.
    late String probeKernel;
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('footprint_probe');
      addTearDown(() => dir.delete(recursive: true));
      probeKernel = '${dir.path}/probe.dill';
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'kernel',
        'test/fixtures/process_memory_probe.dart',
        '-o',
        probeKernel,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
    });

    /// The probe's JSON output.
    Future<Map<String, dynamic>> probe(List<String> args) async {
      final result = await Process.run(Platform.resolvedExecutable, [
        probeKernel,
        ...args,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return jsonDecode(result.stdout as String) as Map<String, dynamic>;
    }

    List<Map<String, dynamic>> lastRound(Map<String, dynamic> output) =>
        ((output['rounds'] as List).last as List).cast<Map<String, dynamic>>();

    /// Memory kinds a process can dirty on this platform.
    final kinds = [
      'private',
      if (Platform.isMacOS || Platform.isLinux) 'shared_anon',
      if (Platform.isLinux) 'memfd',
      if (Platform.isWindows) 'section',
    ];

    test('reports the counter for this platform', () {
      expect(
        memoryFootprintSource,
        Platform.isWindows
            ? windowsFootprintSource
            : footprintCounterFor(Platform.operatingSystem)!.source,
      );
      expect(memoryFootprintBytes(), isPositive);
    });
    for (final kind in kinds) {
      test('counts $kind memory it dirties, whatever is resident', () async {
        const size = 256 * mib;
        final output = await probe(['dirty', kind, '$size']);
        final [before, after, trimmed] = lastRound(output);
        final reason = '$output';
        expect(
          after['footprint'] - before['footprint'],
          greaterThan(240 * mib),
          reason: reason,
        );
        expect(
          (trimmed['footprint'] - after['footprint']).abs(),
          lessThan(16 * mib),
          reason: reason,
        );
        if (Platform.isWindows) {
          expect(
            after['rss'] - trimmed['rss'],
            greaterThan(200 * mib),
            reason: reason,
          );
        }
      });
      test('a $kind leak on every load fails both memory bounds', () async {
        final output = await probe(['leak', kind, '${16 * mib}']);
        final reason = '$output';
        expect(output['measurement'], memoryFootprintSource);
        expect(output['peak_memory_bound'], 'FAIL', reason: reason);
        expect(output['leak_slope_bound'], 'FAIL', reason: reason);
      });
    }

    /// Whether [path] is on a tmpfs or ramfs, whose file pages are shared
    /// memory the footprint counts, as Ubuntu 26.04's /tmp is.
    Future<bool> inSharedMemory(String path) async {
      if (!Platform.isLinux) return false;
      final result = await Process.run('stat', ['-f', '-c', '%T', path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final type = (result.stdout as String).trim();
      return type == 'tmpfs' || type == 'ramfs';
    }

    /// A [size]-byte file in page cache, in the system temporary directory or,
    /// when that is in shared memory, under `.dart_tool`.
    Future<File> pagesFile(int size) async {
      final parents = [Directory.systemTemp, Directory('.dart_tool')];
      Directory? parent;
      for (final candidate in parents) {
        if (!await inSharedMemory(candidate.path)) {
          parent = candidate;
          break;
        }
      }
      if (parent == null) {
        fail('No file system outside shared memory among $parents');
      }
      final dir = await parent.createTemp('footprint');
      addTearDown(() => dir.delete(recursive: true));
      return File('${dir.path}/pages.bin')
        ..writeAsBytesSync(Uint8List(size)..fillRange(0, size, 7));
    }

    test('does not count freed heap memory the allocator keeps', () async {
      const size = 256 * mib;
      final output = await probe(['freed', '$size']);
      final reason = '$output';
      expect(
        output['untrimmed']! - output['before']!,
        greaterThan(200 * mib),
        reason: reason,
      );
      expect(
        (output['footprint']! - output['before']!).abs(),
        lessThan(64 * mib),
        reason: reason,
      );
    }, testOn: 'linux');
    test('counts committed memory never written', () async {
      const size = 256 * mib;
      final output = await probe(['dirty', 'committed', '$size']);
      final [before, after, _] = lastRound(output);
      final reason = '$output';
      expect(
        after['footprint'] - before['footprint'],
        greaterThan(240 * mib),
        reason: reason,
      );
      expect(after['rss'] - before['rss'], lessThan(64 * mib), reason: reason);
    }, testOn: 'windows');
    test('ignores mapped file pages entering and leaving residency', () async {
      const size = 256 * mib;
      final output = await probe([
        'mapped',
        (await pagesFile(size)).path,
        'read',
      ]);
      final [before, touched, evicted] = lastRound(output);
      final reason = '$output';
      expect(output['sum'], size ~/ 4096 * 7);
      expect(
        touched['rss'] - before['rss'],
        greaterThan(200 * mib),
        reason: reason,
      );
      expect(
        touched['rss'] - evicted['rss'],
        greaterThan(200 * mib),
        reason: reason,
      );
      expect(
        (touched['footprint'] - before['footprint']).abs(),
        lessThan(64 * mib),
        reason: reason,
      );
      expect(
        (evicted['footprint'] - touched['footprint']).abs(),
        lessThan(64 * mib),
        reason: reason,
      );
    });
    test('ignores file pages written through a shared mapping', () async {
      const size = 256 * mib;
      final output = await probe([
        'mapped',
        (await pagesFile(size)).path,
        'write',
      ]);
      final [before, written, _] = lastRound(output);
      final reason = '$output';
      expect(
        written['rss'] - before['rss'],
        greaterThan(200 * mib),
        reason: reason,
      );
      expect(
        (written['footprint'] - before['footprint']).abs(),
        lessThan(64 * mib),
        reason: reason,
      );
    });
    test('counts file pages written through a private mapping', () async {
      const size = 256 * mib;
      final output = await probe([
        'mapped',
        (await pagesFile(size)).path,
        'copy',
      ]);
      final [_, written, _] = lastRound(output);
      final unmapped = output['unmapped'] as Map<String, dynamic>;
      expect(
        written['footprint'] - unmapped['footprint'],
        greaterThan(240 * mib),
        reason: '$output',
      );
    });
  });
}
