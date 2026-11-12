double? asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

int? asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

bool? asBool(Object? value) {
  return value is bool ? value : null;
}

List<String>? asStringList(Object? value) {
  if (value is List) {
    final strings = value.whereType<String>().toList(growable: false);
    if (strings.length == value.length) {
      return strings;
    }
  }
  return null;
}

Map<String, dynamic>? asStringDynamicMap(Object? value) {
  return value is Map ? value.cast<String, dynamic>() : null;
}
