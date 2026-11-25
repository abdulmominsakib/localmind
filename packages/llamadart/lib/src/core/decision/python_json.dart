/// Encodes [value] exactly as Python's
/// `json.dumps(value, ensure_ascii=ensureAscii)` does with default settings.
///
/// Separators are `, ` and `: `. Doubles use Python's `repr` (`1.0`, `1e-05`,
/// `1e+16`), and `NaN`, `Infinity` and `-Infinity` are written bare, as
/// `allow_nan=True` does. Map keys must be [String].
///
/// With [ensureAscii], every character outside `0x20..0x7e` is escaped, as
/// `\uXXXX` per UTF-16 code unit unless it has a short escape such as `\n`.
/// Otherwise only `"`, `\` and control characters below `0x20` are escaped.
///
/// On the web, integral doubles are integers, so `1.0` encodes as `1` there.
///
/// Throws [ArgumentError] for any other value or key type.
String pythonJsonDumps(Object? value, {bool ensureAscii = false}) {
  final out = StringBuffer();
  _writeValue(out, value, ensureAscii);
  return out.toString();
}

void _writeValue(StringBuffer out, Object? value, bool ensureAscii) {
  switch (value) {
    case null:
      out.write('null');
    case bool():
      out.write(value ? 'true' : 'false');
    case int():
      out.write(value);
    case double():
      out.write(_floatRepr(value));
    case String():
      _writeString(out, value, ensureAscii);
    case List():
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(', ');
        _writeValue(out, value[i], ensureAscii);
      }
      out.write(']');
    case Map():
      out.write('{');
      var first = true;
      for (final MapEntry(:key, value: item) in value.entries) {
        if (!first) out.write(', ');
        first = false;
        if (key is! String) {
          throw ArgumentError.value(key, 'key', 'Map keys must be String');
        }
        _writeString(out, key, ensureAscii);
        out.write(': ');
        _writeValue(out, item, ensureAscii);
      }
      out.write('}');
    default:
      throw ArgumentError.value(
        value,
        'value',
        'Object of type ${value.runtimeType} is not JSON serializable',
      );
  }
}

String _floatRepr(double value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value > 0 ? 'Infinity' : '-Infinity';
  if (value == 0) return value.isNegative ? '-0.0' : '0.0';

  final sign = value < 0 ? '-' : '';
  final shortest = value.abs().toStringAsExponential();
  final e = shortest.indexOf('e');
  final mantissa = shortest.substring(0, e);
  final exponent = int.parse(shortest.substring(e + 1));
  if (exponent < -4 || exponent >= 16) {
    final digits = '${exponent.abs()}'.padLeft(2, '0');
    return '$sign${mantissa}e${exponent < 0 ? '-' : '+'}$digits';
  }

  final digits = mantissa.replaceFirst('.', '');
  final point = exponent + 1;
  if (point <= 0) return '${sign}0.${'0' * -point}$digits';
  if (point >= digits.length) {
    return '$sign$digits${'0' * (point - digits.length)}.0';
  }
  return '$sign${digits.substring(0, point)}.${digits.substring(point)}';
}

void _writeString(StringBuffer out, String value, bool ensureAscii) {
  out.write('"');
  for (final unit in value.codeUnits) {
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      default:
        if (unit < 0x20 || (ensureAscii && unit > 0x7e)) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
}
