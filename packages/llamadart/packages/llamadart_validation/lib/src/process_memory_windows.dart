import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Names the Windows footprint counter.
const windowsFootprintSource =
    'GetProcessMemoryInfo PROCESS_MEMORY_COUNTERS_EX2 '
    'PrivateUsage + SharedCommitUsage';

/// Names the Windows counter used where `PROCESS_MEMORY_COUNTERS_EX2` is
/// unavailable.
const windowsPrivateFootprintSource =
    'GetProcessMemoryInfo PROCESS_MEMORY_COUNTERS_EX PrivateUsage '
    '(PROCESS_MEMORY_COUNTERS_EX2 unavailable: pagefile-backed shared '
    'sections are not counted)';

/// Written to `SharedCommitUsage` before the call, so a Windows build that
/// accepts the structure but does not fill that field is detected.
const windowsUnfilledSentinel = -1;

/// `PROCESS_MEMORY_COUNTERS_EX` in `<psapi.h>`.
final class ProcessMemoryCountersEx extends Struct {
  @Uint32()
  external int cb;
  @Uint32()
  external int pageFaultCount;
  @Size()
  external int peakWorkingSetSize;
  @Size()
  external int workingSetSize;
  @Size()
  external int quotaPeakPagedPoolUsage;
  @Size()
  external int quotaPagedPoolUsage;
  @Size()
  external int quotaPeakNonPagedPoolUsage;
  @Size()
  external int quotaNonPagedPoolUsage;
  @Size()
  external int pagefileUsage;
  @Size()
  external int peakPagefileUsage;
  @Size()
  external int privateUsage;
}

/// `PROCESS_MEMORY_COUNTERS_EX2` in `<psapi.h>`.
final class ProcessMemoryCountersEx2 extends Struct {
  @Uint32()
  external int cb;
  @Uint32()
  external int pageFaultCount;
  @Size()
  external int peakWorkingSetSize;
  @Size()
  external int workingSetSize;
  @Size()
  external int quotaPeakPagedPoolUsage;
  @Size()
  external int quotaPagedPoolUsage;
  @Size()
  external int quotaPeakNonPagedPoolUsage;
  @Size()
  external int quotaNonPagedPoolUsage;
  @Size()
  external int pagefileUsage;
  @Size()
  external int peakPagefileUsage;
  @Size()
  external int privateUsage;
  @Size()
  external int privateWorkingSetSize;
  @Uint64()
  external int sharedCommitUsage;
}

/// `PrivateUsage` plus `SharedCommitUsage` from a `GetProcessMemoryInfo` call
/// that returned [succeeded], or null when it failed or left
/// `SharedCommitUsage` at [windowsUnfilledSentinel].
int? windowsFootprintFrom(int succeeded, ProcessMemoryCountersEx2 counters) =>
    succeeded == 0 || counters.sharedCommitUsage == windowsUnfilledSentinel
    ? null
    : counters.privateUsage + counters.sharedCommitUsage;

/// `PrivateUsage` from a `GetProcessMemoryInfo` call that returned
/// [succeeded], or null when it failed.
int? windowsPrivateFootprintFrom(
  int succeeded,
  ProcessMemoryCountersEx counters,
) => succeeded == 0 ? null : counters.privateUsage;

/// `K32GetProcessMemoryInfo` for this process into [size] bytes at
/// [counters].
int _getProcessMemoryInfo(Pointer<Void> counters, int size) {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final process = kernel32
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetCurrentProcess',
      )();
  return kernel32.lookupFunction<
    Int32 Function(Pointer<Void>, Pointer<Void>, Uint32),
    int Function(Pointer<Void>, Pointer<Void>, int)
  >('K32GetProcessMemoryInfo')(process, counters, size);
}

/// Calls `K32GetProcessMemoryInfo` with `PROCESS_MEMORY_COUNTERS_EX2` for this
/// process, or [call] in its place, and passes the result to [read].
R? readProcessMemoryCounters<R>(
  R? Function(int succeeded, ProcessMemoryCountersEx2 counters) read, {
  int Function(Pointer<Void> counters, int size) call = _getProcessMemoryInfo,
}) {
  final size = sizeOf<ProcessMemoryCountersEx2>();
  final counters = calloc<ProcessMemoryCountersEx2>()
    ..ref.cb = size
    ..ref.sharedCommitUsage = windowsUnfilledSentinel;
  try {
    return read(call(counters.cast(), size), counters.ref);
  } finally {
    calloc.free(counters);
  }
}

/// This process's private and shared committed bytes, or null when
/// `K32GetProcessMemoryInfo` fails or does not report shared commit.
int? readWindowsSharedFootprint() =>
    readProcessMemoryCounters(windowsFootprintFrom);

/// This process's private committed bytes from `PROCESS_MEMORY_COUNTERS_EX`,
/// or null when `K32GetProcessMemoryInfo` fails.
int? readWindowsPrivateFootprint() {
  final size = sizeOf<ProcessMemoryCountersEx>();
  final counters = calloc<ProcessMemoryCountersEx>()..ref.cb = size;
  try {
    return windowsPrivateFootprintFrom(
      _getProcessMemoryInfo(counters.cast(), size),
      counters.ref,
    );
  } finally {
    calloc.free(counters);
  }
}

/// The Windows counter: [readShared] and [windowsFootprintSource] when a
/// first [readShared] call measures, otherwise [readPrivate] and
/// [windowsPrivateFootprintSource]. The choice holds for every later sample,
/// so one report never mixes counters.
({String source, int? Function() read}) windowsCounterFrom(
  int? Function() readShared,
  int? Function() readPrivate,
) {
  int? shared;
  try {
    shared = readShared();
  } catch (_) {
    shared = null;
  }
  return shared == null
      ? (source: windowsPrivateFootprintSource, read: readPrivate)
      : (source: windowsFootprintSource, read: readShared);
}

final _windowsCounter = windowsCounterFrom(
  readWindowsSharedFootprint,
  readWindowsPrivateFootprint,
);

/// Names the counter [readWindowsFootprint] reads on this Windows build.
String windowsSource() => _windowsCounter.source;

/// This process's footprint from the counter [windowsSource] names.
int? readWindowsFootprint() => _windowsCounter.read();
