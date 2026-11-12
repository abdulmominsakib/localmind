import 'dart:convert';
import 'dart:io';

/// Lanes that split root test files across CI jobs, each mapped to the
/// weights it is balanced by.
const Map<String, String> testShardLanes = {
  'linux-vm': 'linux-vm',
  'chrome': 'chrome',
  'macos': 'macos',
  'windows-tooling': 'windows',
  'windows-runtime': 'windows',
};

/// Timing sources in the weights file.
const List<String> weightLanes = ['linux-vm', 'chrome', 'macos', 'windows'];

/// Suites `windows-tooling` runs and `windows-runtime` does not. On Windows a
/// tooling suite's `dart run` child cannot replace `.dart_tool/lib` DLLs that
/// native suites in the same test process hold open.
const List<String> windowsToolingPaths = [
  'test/unit/tooling/',
  'test/unit/hook/',
  'test/unit/test_structure/',
  'test/unit/web_setup/',
  'test/unit/public_entrypoints_test.dart',
  'test/unit/public_entrypoints_web_test.dart',
];

const String weightsPath = 'tool/ci/test_shard_weights.json';

// Paths reach the workflow as shell words, so anything else is rejected.
final RegExp _safeTestPath = RegExp(r'^test/[A-Za-z0-9_./-]+_test\.dart$');

/// Test areas whose behavior depends on the host OS by subject: native
/// runtimes, the build hook, `lib/src/platform/io`, native integration and
/// device E2E suites. A trailing `/` covers the whole tree; `*` covers only
/// the directory's own files.
const List<String> hostBoundAreas = [
  'test/unit/backends/llama_cpp/',
  'test/unit/backends/litert_lm/',
  'test/unit/backends/stable_diffusion/',
  'test/unit/backends/native/',
  'test/unit/backends/*',
  'test/unit/hook/',
  'test/unit/platform/',
  'test/integration/*',
  'test/integration/backends/',
  'test/e2e/',
];

/// Suites the rules below miss but whose subject has failed on one host OS
/// only, with that evidence. An entry the rules already cover is rejected by
/// `test_shards_test.dart`.
const Map<String, String> hostHistoryTests = {
  'test/unit/tooling/prepare_workspace_test.dart':
      'Windows-only SDK command launch failure (#678)',
};

/// Imports that reach a native runtime, the hook, or host IO code. A test
/// that reaches one, itself or through a `test/` helper, runs on every OS.
final RegExp _hostImport = RegExp(
  r'^(dart:ffi$|package:ffi/|lib/src/backends/(llama_cpp|litert_lm|'
  r'stable_diffusion|native)/|lib/src/platform/io/|lib/src/hook/|hook/)',
);

/// Loading a test model, itself or through a `test/` helper.
final RegExp _modelLoad = RegExp(r'\bTestHelper\b|LLAMADART_TEST_MODELS_DIR');

/// `LlamaBackend()` picks the native backend on the VM.
final RegExp _platformBackend = RegExp(r'\bLlamaBackend\(\)');

/// A host OS check in the test's own source.
final RegExp _hostCheck = RegExp(
  r'\bPlatform\.(isWindows|isMacOS|isLinux|isIOS|isAndroid|operatingSystem)\b'
  r"|@TestOn\([^)]*(windows|mac-os|linux|posix)|\bonPlatform:",
);

/// `skip: Platform.isWindows ? <reason> : false`: a POSIX-only guard that
/// leaves the test running on Linux, so it alone is no host check.
final RegExp _windowsSkipGuard = RegExp(
  r"skip:\s*Platform\.isWindows\s*(\?\s*('[^']*'|_\w+)\s*:\s*(false|null))?\s*[,)]",
);

final RegExp _directive = RegExp(
  r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]"""
  r"""((?:\s+if\s*\([^)]*\)\s*['"][^'"]+['"])*)""",
  multiLine: true,
);
final RegExp _conditionalUri = RegExp(r"""if\s*\([^)]*\)\s*['"]([^'"]+)['"]""");
final RegExp _pathImport = RegExp(r"""['"]package:path/""");
final RegExp _ioImport = RegExp(r"""['"]dart:io['"]""");

/// Why [file] runs on macOS and Windows as well as Linux; empty when it is
/// platform-neutral and runs on Linux only.
///
/// `doc/ci_selection.md` ("Host OS lanes") states the rule.
List<String> hostReasons(String file, [String root = '.']) {
  final reasons = <String>{};
  for (final area in hostBoundAreas) {
    final inArea = area.endsWith('*')
        ? file.startsWith(area.substring(0, area.length - 1)) &&
              !file.substring(area.length - 1).contains('/')
        : file.startsWith(area);
    if (inArea) reasons.add('host-bound area $area');
  }
  if (file.endsWith('_io_test.dart')) reasons.add('dart:io implementation');
  final history = hostHistoryTests[file];
  if (history != null) reasons.add('host history: $history');
  final own = _read(root, file);
  if (_hostCheck.hasMatch(own.replaceAll(_windowsSkipGuard, ''))) {
    reasons.add('checks the host OS');
  }
  if (_pathImport.hasMatch(own) && _ioImport.hasMatch(own)) {
    reasons.add('builds host paths');
  }
  final seen = <String>{};
  final pending = [file];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (!seen.add(current)) continue;
    final source = current == file ? own : _read(root, current);
    final via = current == file ? '' : ' via $current';
    if (_modelLoad.hasMatch(source)) reasons.add('loads a test model$via');
    if (_platformBackend.hasMatch(source)) {
      reasons.add('constructs the platform backend$via');
    }
    for (final uri in _imports(source)) {
      final target = _resolve(current, uri);
      if (_hostImport.hasMatch(target)) {
        reasons.add('imports $target$via');
      } else if (target.startsWith('test/') && target.endsWith('.dart')) {
        pending.add(target);
      }
    }
  }
  return reasons.toList()..sort();
}

String _read(String root, String path) {
  final file = File('$root/$path');
  return file.existsSync() ? file.readAsStringSync() : '';
}

Iterable<String> _imports(String source) sync* {
  for (final match in _directive.allMatches(source)) {
    yield match[1]!;
    for (final conditional in _conditionalUri.allMatches(match[2] ?? '')) {
      yield conditional[1]!;
    }
  }
}

/// [uri] from [from] as a repository path, or unchanged for `dart:` and
/// other packages.
String _resolve(String from, String uri) {
  if (uri.startsWith('package:llamadart/')) {
    return 'lib/${uri.substring('package:llamadart/'.length)}';
  }
  if (uri.contains(':')) return uri;
  final parts = from.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else if (segment != '.') {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

/// Every `*_test.dart` file under `test/`, as sorted `/`-separated paths.
List<String> rootTestFiles([String root = '.']) {
  final files = [
    for (final entity in Directory(
      '$root/test',
    ).listSync(recursive: true, followLinks: false))
      if (entity is File && entity.path.endsWith('_test.dart'))
        entity.path
            .substring(root.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
  ]..sort();
  for (final file in files) {
    if (!_safeTestPath.hasMatch(file) || file.split('/').contains('..')) {
      throw FormatException('Unsupported test file path: $file');
    }
  }
  return files;
}

/// The files of [files] that [lane] runs. Linux VM and Chrome run every
/// file; macOS and Windows run the files [hostReasons] names a reason for.
List<String> laneFiles(String lane, List<String> files, [String root = '.']) {
  bool host(String file) => hostReasons(file, root).isNotEmpty;
  bool tooling(String file) => windowsToolingPaths.any(file.startsWith);
  return switch (lane) {
    'macos' => [
      for (final file in files)
        if (host(file)) file,
    ],
    'windows-tooling' => [
      for (final file in files)
        if (tooling(file) && host(file)) file,
    ],
    'windows-runtime' => [
      for (final file in files)
        if (!tooling(file) && host(file)) file,
    ],
    _ => files,
  };
}

/// Splits [files] into [count] shards with about equal summed [weights].
///
/// Longest first, each onto the lightest shard, ties to the lower index, so
/// the result is deterministic and every file lands in exactly one shard.
/// Files without a measured weight count as the median measured weight.
List<List<String>> partitionTests(
  List<String> files,
  Map<String, int> weights,
  int count,
) {
  if (count < 1) throw ArgumentError.value(count, 'count');
  final known = weights.values.toList()..sort();
  final fallback = known.isEmpty ? 1 : known[known.length ~/ 2];
  int weightOf(String file) => weights[file] ?? fallback;
  final ordered = [...files]
    ..sort((a, b) {
      final byWeight = weightOf(b).compareTo(weightOf(a));
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  final shards = List.generate(count, (_) => <String>[]);
  final loads = List.filled(count, 0);
  for (final file in ordered) {
    var lightest = 0;
    for (var i = 1; i < count; i++) {
      if (loads[i] < loads[lightest]) lightest = i;
    }
    shards[lightest].add(file);
    loads[lightest] += weightOf(file);
  }
  for (final shard in shards) {
    shard.sort();
  }
  return shards;
}

/// Per-suite wall time in milliseconds from `native_test_timing.dart`
/// summaries: from the suite's first start (its load) to its last end or, if
/// later, to the next suite's start, which adds the coverage collection a
/// `-j 1` VM run spends between suites. A suite in several summaries, such as
/// several runs' artifacts, gets its mean time.
Map<String, int> suiteWeights(Iterable<Map<String, dynamic>> summaries) {
  final times = <String, List<int>>{};
  for (final summary in summaries) {
    final paths = {
      for (final suite in (summary['suites'] as List).cast<Map>())
        suite['id'] as int: suite['path'] as String,
    };
    final spans = <int, (int, int)>{};
    for (final test in (summary['tests'] as List).cast<Map>()) {
      final start = test['startMs'] as int;
      final end = start + ((test['durationMs'] as int?) ?? 0);
      final id = test['suiteId'] as int;
      final (first, last) = spans[id] ?? (start, end);
      spans[id] = (start < first ? start : first, end > last ? end : last);
    }
    final starts = spans.values.map((span) => span.$1).toList()..sort();
    final elapsed = summary['reporterElapsedMs'] as int? ?? 0;
    for (final MapEntry(key: id, value: (first, last)) in spans.entries) {
      final path = paths[id]!;
      if (!_safeTestPath.hasMatch(path)) continue;
      final next = starts.firstWhere(
        (start) => start > first,
        orElse: () => elapsed,
      );
      (times[path] ??= []).add((next > last ? next : last) - first);
    }
  }
  return {
    for (final MapEntry(key: path, value: runs) in times.entries)
      path: runs.reduce((a, b) => a + b) ~/ runs.length,
  };
}

Map<String, Map<String, int>> readWeights([String file = weightsPath]) {
  final decoded = jsonDecode(File(file).readAsStringSync()) as Map;
  return {
    for (final MapEntry(:key, :value) in decoded.entries)
      key as String: (value as Map).cast<String, int>(),
  };
}

const String _usage =
    '''
Usage:
  dart tool/ci/test_shards.dart <lane> <shard> <shards>
      Prints the test files of 1-based <shard> of <shards> for <lane>, and
      writes them as `files` to \$GITHUB_OUTPUT when that is set.
      Lanes: linux-vm, chrome, macos, windows-tooling, windows-runtime.
  dart tool/ci/test_shards.dart hosts [<test file>...]
      Prints whether each root test file (default: all) runs on Linux only
      or on every OS, and why.
  dart tool/ci/test_shards.dart weights <source> <timing.json>...
      Replaces <source>'s weights in $weightsPath with the suite times of
      native_test_timing.dart summaries, such as one lane's CI artifacts.
      Sources: linux-vm, chrome, macos, windows.''';

void main(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.first == 'hosts') {
    final files = arguments.length > 1 ? arguments.skip(1) : rootTestFiles();
    for (final file in files) {
      final reasons = hostReasons(file);
      stdout.writeln(
        reasons.isEmpty
            ? '$file: Linux only'
            : '$file: every OS (${reasons.join('; ')})',
      );
    }
    return;
  }
  if (arguments.length >= 3 && arguments.first == 'weights') {
    final lane = arguments[1];
    if (!weightLanes.contains(lane)) return _fail('Unknown lane: $lane');
    final summaries = [
      for (final file in arguments.skip(2))
        jsonDecode(File(file).readAsStringSync()) as Map<String, dynamic>,
    ];
    final all = File(weightsPath).existsSync()
        ? readWeights()
        : <String, Map<String, int>>{};
    final measured = suiteWeights(summaries);
    // A file the lane did not run (platform-skipped) costs nothing there.
    all[lane] = {
      for (final file in {
        ...rootTestFiles(),
        ...measured.keys,
      }.toList()..sort())
        file: measured[file] ?? 0,
    };
    File(weightsPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({for (final lane in weightLanes) lane: all[lane] ?? <String, int>{}})}\n',
    );
    return;
  }
  if (arguments.length != 3) return _fail(_usage);
  final [lane, shardText, countText] = arguments;
  final shard = int.tryParse(shardText);
  final count = int.tryParse(countText);
  if (!testShardLanes.containsKey(lane) ||
      count == null ||
      shard == null ||
      shard < 1 ||
      shard > count) {
    return _fail(_usage);
  }
  final files = partitionTests(
    laneFiles(lane, rootTestFiles()),
    readWeights()[testShardLanes[lane]] ?? const {},
    count,
  )[shard - 1];
  if (files.isEmpty) return _fail('Shard $shard of $count has no test files.');
  stdout.writeln(files.join('\n'));
  final output = Platform.environment['GITHUB_OUTPUT'];
  if (output != null && output.isNotEmpty) {
    File(
      output,
    ).writeAsStringSync('files=${files.join(' ')}\n', mode: FileMode.append);
  }
}

void _fail(String message) {
  stderr.writeln(message);
  exitCode = 64;
}
