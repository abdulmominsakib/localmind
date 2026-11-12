import 'dart:ffi';

import 'package:path/path.dart' as path;

/// File names, asset URIs and lookup paths the llama.cpp runtime tries when it
/// opens its native libraries, for one host.
///
/// Holds no state of its own: the host OS, the backend module directory and
/// the directory listing are injected, so every platform's naming can be
/// tested on any host. Opening and probing the candidates stays with the
/// caller.
final class LlamaCppLibraryCandidates {
  /// Creates the candidates for a host whose `Platform.operatingSystem` is
  /// [os], whose process runs [abi] and whose ggml backend modules live in
  /// [moduleDirectory], if known.
  ///
  /// [listFiles] returns the names of the regular files in a directory and
  /// may throw when it cannot be read; [fileExists] reports whether a path is
  /// an existing file.
  LlamaCppLibraryCandidates({
    required String os,
    required Abi abi,
    required String? moduleDirectory,
    required List<String> Function(String directory) listFiles,
    required bool Function(String filePath) fileExists,
  }) : _os = os,
       _abi = abi,
       _moduleDirectory = moduleDirectory,
       _listFiles = listFiles,
       _fileExists = fileExists;

  static const Map<String, int> _androidCpuVariantPriority = <String, int>{
    'android_armv9.2_2': 0,
    'android_armv9.2_1': 1,
    'android_armv9.0_1': 2,
    'android_armv8.6_1': 3,
    'android_armv8.2_2': 4,
    'android_armv8.2_1': 5,
    'android_armv8.0_1': 6,
  };

  // Highest ggml_backend_score first, so the first module that loads is the
  // one ggml_backend_load_all_from_path picks and ggml registers one CPU
  // backend when a process uses both. Unlisted variants stay behind the
  // baseline until their score is known.
  static const Map<String, int> _linuxArm64CpuVariantPriority = <String, int>{
    'linux_armv8.6_1': 0,
    'linux_armv8.2_2': 1,
  };

  static final Comparator<String> _androidCpuOrder = _cpuNameOrder(
    _androidCpuVariantPriority,
    unknownVariantRank: 900,
  );
  static final Comparator<String> _linuxArm64CpuOrder = _cpuNameOrder(
    _linuxArm64CpuVariantPriority,
    unknownVariantRank: 1500,
  );

  final String _os;
  final Abi _abi;
  final String? _moduleDirectory;
  final List<String> Function(String directory) _listFiles;
  final bool Function(String filePath) _fileExists;

  bool get _isWindows => _os == 'windows';
  bool get _isApple => _os == 'macos' || _os == 'ios';
  bool get _isAndroid => _os == 'android';
  bool get _isLinuxArm64 => _os == 'linux' && _abi == Abi.linuxArm64;

  /// The unsuffixed file name of the ggml [backend] module.
  String backendFileName(String backend) {
    if (_isWindows) {
      return 'ggml-$backend.dll';
    }
    if (_isApple) {
      return 'libggml-$backend.dylib';
    }
    return 'libggml-$backend.so';
  }

  /// File names of the ggml [backend] module, in the order to try them.
  ///
  /// With a module directory these are the matching files in it; without one,
  /// bare names for the platform library search path.
  List<String> backend(String backend) {
    final baseName = backendFileName(backend);
    final moduleDirectory = _moduleDirectory;
    final rankAndroidCpu = backend == 'cpu' && _isAndroid;
    if (moduleDirectory == null) {
      if (rankAndroidCpu) {
        final variants = _androidCpuVariantPriority.keys
            .map((variant) => 'libggml-cpu-$variant.so')
            .toList(growable: false);
        return <String>[...variants, baseName];
      }
      return <String>[baseName];
    }

    final candidates = <String>{};
    if (_fileExists(path.join(moduleDirectory, baseName))) {
      candidates.add(baseName);
    }
    final dynamicNames = _matchingNames(
      moduleDirectory,
      _backendPattern(backend),
    );
    if (rankAndroidCpu) {
      dynamicNames.sort(_androidCpuOrder);
    }
    candidates.addAll(dynamicNames);
    final resolved = candidates.toList(growable: false);
    if (rankAndroidCpu) {
      resolved.sort(_androidCpuOrder);
    } else if (backend == 'cpu' && _isLinuxArm64) {
      resolved.sort(_linuxArm64CpuOrder);
    }
    return resolved;
  }

  /// Code-asset URIs of the ggml [backend] module, in the order to try them.
  List<String> backendAssetUris(String backend) {
    final candidates = <String>{
      'package:llamadart/$backend',
      'package:llamadart/ggml_$backend',
      'package:llamadart/ggml-$backend',
    };

    if (backend == 'cpu' && _isAndroid) {
      for (final variant in _androidCpuVariantPriority.keys) {
        candidates.add(
          'package:llamadart/ggml-cpu-${variant.replaceAll('.', '_')}',
        );
      }
      candidates.add('package:llamadart/ggml-cpu');
    }

    return candidates.toList(growable: false);
  }

  /// File names of the ggml core library.
  List<String> ggml() =>
      _withModuleDirectoryMatches(<String>{_ggmlFileName()}, _ggmlPattern());

  /// Code-asset URIs of the ggml core library.
  List<String> ggmlAssetUris() {
    if (_isWindows) {
      return const <String>[
        'package:llamadart/ggml',
        'package:llamadart/ggml-base',
      ];
    }
    return const <String>['package:llamadart/ggml'];
  }

  /// File names of the llamadart wrapper library.
  List<String> wrapper() =>
      _withModuleDirectoryMatches(_wrapperStaticNames(), _wrapperPattern());

  /// Code-asset URIs of the llamadart wrapper library.
  List<String> wrapperAssetUris() {
    // Prefer asset-URI resolution so Windows split bundles can reliably resolve
    // the wrapper helper library without relying on process cwd/search paths.
    if (_isWindows) {
      return const <String>[
        'package:llamadart/llamadart_wrapper',
        'package:llamadart/llamadart',
      ];
    }
    return const <String>['package:llamadart/llamadart'];
  }

  /// Every wrapper library candidate, deduplicated: asset URIs, then each of
  /// [lookupDirectories] joined with the wrapper names and the matching files
  /// in it, then the bare names.
  List<String> wrapperPaths(Iterable<String> lookupDirectories) {
    final candidates = <String>[...wrapperAssetUris()];
    final fileNames = wrapper();
    final pattern = _wrapperPattern();
    for (final directoryPath in lookupDirectories) {
      for (final fileName in fileNames) {
        candidates.add(path.join(directoryPath, fileName));
      }
      for (final fileName in _matchingNames(directoryPath, pattern)) {
        candidates.add(path.join(directoryPath, fileName));
      }
    }
    candidates.addAll(fileNames);

    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate)) candidate,
    ];
  }

  /// File names of the mtmd multimodal library.
  List<String> mtmd() =>
      _withModuleDirectoryMatches(<String>{_mtmdFileName()}, _mtmdPattern());

  List<String> _withModuleDirectoryMatches(
    Set<String> candidates,
    RegExp pattern,
  ) {
    final moduleDirectory = _moduleDirectory;
    if (moduleDirectory != null) {
      candidates.addAll(_matchingNames(moduleDirectory, pattern));
    }
    return candidates.toList(growable: false);
  }

  String _ggmlFileName() {
    if (_isWindows) {
      return 'ggml.dll';
    }
    if (_isApple) {
      return 'libggml.dylib';
    }
    return 'libggml.so';
  }

  String _mtmdFileName() {
    if (_isWindows) {
      return 'mtmd.dll';
    }
    if (_isApple) {
      return 'libmtmd.dylib';
    }
    return 'libmtmd.so';
  }

  Set<String> _wrapperStaticNames() {
    final String baseName;
    if (_isWindows) {
      baseName = 'llamadart.dll';
    } else if (_isApple) {
      baseName = 'libllamadart.dylib';
    } else {
      baseName = 'libllamadart.so';
    }
    final candidates = <String>{baseName};
    if (_isWindows) {
      // Hook asset naming can expose wrapper helper as `llamadart_wrapper.dll`.
      candidates.add('llamadart_wrapper.dll');
    }
    if (_isApple) {
      // Flutter Apple apps embed the native asset as a framework rather than
      // as a bare libllamadart.dylib. Opening the framework binary directly
      // makes dynamically discovered wrapper ABIs visible to FFI.
      candidates.add(path.join('llamadart.framework', 'llamadart'));
      candidates.add(path.join('llama.framework', 'llama'));
    }
    return candidates;
  }

  RegExp _backendPattern(String backend) {
    final escapedBackend = RegExp.escape(backend);
    if (_isWindows) {
      return RegExp('^ggml-$escapedBackend(?:-[^\\\\/]+)*\\.dll\$');
    }
    if (_isApple) {
      return RegExp('^libggml-$escapedBackend(?:-[^\\\\/]+)*\\.dylib\$');
    }
    return RegExp('^libggml-$escapedBackend(?:-[^\\\\/]+)*\\.so\$');
  }

  RegExp _ggmlPattern() {
    if (_isWindows) {
      return RegExp(r'^ggml(?:-[^.\\/]+)*\.dll$');
    }
    if (_isApple) {
      return RegExp(r'^libggml(?:-[^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libggml(?:-[^.\\/]+)*\.so$');
  }

  RegExp _wrapperPattern() {
    if (_isWindows) {
      return RegExp(r'^llamadart(?:[-_][^.\\/]+)*\.dll$');
    }
    if (_isApple) {
      return RegExp(r'^libllamadart(?:[-_][^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libllamadart(?:[-_][^.\\/]+)*\.so$');
  }

  RegExp _mtmdPattern() {
    if (_isWindows) {
      return RegExp(r'^mtmd(?:-[^.\\/]+)*\.dll$');
    }
    if (_isApple) {
      return RegExp(r'^libmtmd(?:-[^.\\/]+)*\.dylib$');
    }
    return RegExp(r'^libmtmd(?:-[^.\\/]+)*\.so$');
  }

  List<String> _matchingNames(String directoryPath, RegExp pattern) {
    try {
      return _listFiles(directoryPath).where(pattern.hasMatch).toList()..sort();
    } catch (_) {
      return <String>[];
    }
  }

  static Comparator<String> _cpuNameOrder(
    Map<String, int> variantPriority, {
    required int unknownVariantRank,
  }) {
    int rank(String fileName) {
      final lowered = fileName.toLowerCase();
      if (lowered == 'libggml-cpu.so') {
        return 1000;
      }

      final variantMatch = RegExp(
        r'^libggml-cpu-([^/\\]+)\.so$',
      ).firstMatch(lowered);
      if (variantMatch == null) {
        return 2000;
      }

      final variant = variantMatch.group(1)!;
      return variantPriority[variant] ?? unknownVariantRank;
    }

    return (a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    };
  }
}
