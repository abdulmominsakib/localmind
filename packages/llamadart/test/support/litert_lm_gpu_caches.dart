import 'dart:io';

/// Writes the GPU weight and program caches LiteRT-LM v0.18 keeps next to
/// [bundle] for its text model, named after the bundle path, its mtime in
/// seconds and its size. [suffixes] picks which of the two to write.
void writeLiteRtLmGpuTextCaches(
  File bundle, {
  List<String> suffixes = const [
    '_mldrift_program_cache.bin',
    '_mldrift_weight_cache.bin',
  ],
}) {
  final stat = bundle.statSync();
  final seconds = stat.modified.millisecondsSinceEpoch ~/ 1000;
  for (final suffix in suffixes) {
    File(
      '${bundle.absolute.path}_${seconds}_${stat.size}$suffix',
    ).writeAsStringSync('cache');
  }
}
