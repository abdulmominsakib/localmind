import 'dart:io';

import 'process_memory_darwin.dart';
import 'process_memory_linux.dart';
import 'process_memory_windows.dart';

/// A per-platform count of the memory a process owns: what [read] reads,
/// named by [describe] so a report states what produced its numbers.
final class FootprintCounter {
  const FootprintCounter(this.describe, this.read);

  final String Function() describe;
  final int? Function() read;

  String get source => describe();
}

String _darwinSource() => darwinFootprintSource;

/// The footprint counter for [operatingSystem], a `Platform.operatingSystem`
/// value, or null when it has none.
FootprintCounter? footprintCounterFor(String operatingSystem) =>
    switch (operatingSystem) {
      'macos' ||
      'ios' => const FootprintCounter(_darwinSource, readDarwinFootprint),
      'linux' ||
      'android' => const FootprintCounter(linuxSource, readLinuxFootprint),
      'windows' => const FootprintCounter(windowsSource, readWindowsFootprint),
      _ => null,
    };

/// A positive byte count from [read], or null when [read] is null, throws or
/// returns no positive count.
int? sampleFootprint(int? Function()? read) {
  if (read == null) return null;
  try {
    final bytes = read();
    return bytes != null && bytes > 0 ? bytes : null;
  } catch (_) {
    return null;
  }
}

final _counter = footprintCounterFor(Platform.operatingSystem);

/// Names the counter behind [memoryFootprintBytes] on this platform.
final String memoryFootprintSource =
    _counter?.source ??
    'unavailable: no footprint counter on ${Platform.operatingSystem}';

/// Whole-process footprint bytes, or null when this platform has no counter or
/// the counter fails.
///
/// The value covers native allocations as well as the Dart heap. It is not
/// comparable across operating systems: each counter counts its own way.
int? memoryFootprintBytes() => sampleFootprint(_counter?.read);
