/// Parses a parameter size (in billions) from a model name, repo id, or
/// filename. Returns `null` when no reliable size can be extracted.
///
/// Supports forms like `7B`, `135M`, `0.5B`, `8x7B` (MoE, multiplied out).
/// Callers may override the result with a more authoritative value (e.g.
/// `gguf.total`) when model info is available.
double? parseParameterSizeBillions(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  // MoE style: NxMB (e.g. "8x7B", "8x7b").
  final moe = RegExp(
    r'(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)\s*([BbMmKk])',
  ).firstMatch(text);
  if (moe != null) {
    final count = double.tryParse(moe.group(1)!);
    final size = double.tryParse(moe.group(2)!);
    final unit = moe.group(3)!.toUpperCase();
    if (count != null && size != null && count > 0 && size > 0) {
      return count * _toBillions(size, unit);
    }
  }

  // Single size token: number followed by B/M/K (case-insensitive).
  final single = RegExp(r'(\d+(?:\.\d+)?)\s*([BbMmKk])').firstMatch(text);
  if (single != null) {
    final value = double.tryParse(single.group(1)!);
    final unit = single.group(2)!.toUpperCase();
    if (value != null && value > 0) {
      return _toBillions(value, unit);
    }
  }

  return null;
}

double _toBillions(double value, String unit) {
  switch (unit) {
    case 'B':
      return value;
    case 'M':
      return value / 1000.0;
    case 'K':
      return value / 1000000.0;
    default:
      return value;
  }
}

/// Formats a size in billions into a compact label (e.g. 7.0 -> "7B",
/// 0.135 -> "135M").
String formatParameterSize(double billions) {
  if (billions >= 1) {
    final rounded = billions == billions.roundToDouble()
        ? billions.toStringAsFixed(0)
        : billions.toStringAsFixed(1);
    return '${rounded}B';
  }
  final millions = (billions * 1000).round();
  return '${millions}M';
}
