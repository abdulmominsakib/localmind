import 'dart:ffi';
import 'dart:io';

/// Names the Linux footprint counter where the C library provides
/// `malloc_trim`, as glibc does.
const linuxFootprintSource =
    '/proc/self/status RssAnon + RssShmem + VmSwap after malloc_trim(0)';

/// Names the Linux and Android footprint counter where the C library has no
/// `malloc_trim`, such as Android's Bionic or musl.
const linuxUntrimmedFootprintSource =
    '/proc/self/status RssAnon + RssShmem + VmSwap (malloc_trim unavailable: '
    'freed memory the allocator keeps is counted)';

/// `RssAnon` plus `RssShmem` plus `VmSwap` in bytes from `/proc/<pid>/status`
/// text, or null unless all three lines are present with a `kB` value.
///
/// Kernels before 4.5 have no `RssAnon` or `RssShmem` line.
int? linuxFootprintFrom(String status) {
  int? kib(String field) {
    final match = RegExp(
      '^$field:\\s*(\\d+) kB\$',
      multiLine: true,
    ).firstMatch(status);
    return match == null ? null : int.parse(match.group(1)!);
  }

  final anonymous = kib('RssAnon');
  final shared = kib('RssShmem');
  final swapped = kib('VmSwap');
  return anonymous == null || shared == null || swapped == null
      ? null
      : (anonymous + shared + swapped) * 1024;
}

/// The counter that calls [trim] with 0 before each [read], named
/// [linuxFootprintSource], or [read] alone, named
/// [linuxUntrimmedFootprintSource], when [trim] is null.
({String source, int? Function() read}) linuxCounterFrom(
  int Function(int)? trim,
  int? Function() read,
) => trim == null
    ? (source: linuxUntrimmedFootprintSource, read: read)
    : (
        source: linuxFootprintSource,
        read: () {
          trim(0);
          return read();
        },
      );

/// `malloc_trim` from [library], or null when it does not export one.
int Function(int)? lookUpMallocTrim(DynamicLibrary library) =>
    library.providesSymbol('malloc_trim')
    ? library.lookupFunction<Int32 Function(Size), int Function(int)>(
        'malloc_trim',
      )
    : null;

final _linuxCounter = linuxCounterFrom(
  lookUpMallocTrim(DynamicLibrary.process()),
  () => linuxFootprintFrom(File('/proc/self/status').readAsStringSync()),
);

/// Names the counter [readLinuxFootprint] reads in this process.
String linuxSource() => _linuxCounter.source;

/// This process's `RssAnon` plus `RssShmem` plus `VmSwap` in bytes, read after
/// `malloc_trim(0)` where the C library provides it, or null when
/// `/proc/self/status` cannot be read or lacks any of those lines.
int? readLinuxFootprint() => _linuxCounter.read();
