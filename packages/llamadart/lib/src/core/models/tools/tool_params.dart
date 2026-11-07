/// Provides type-safe access to tool call arguments.
///
/// When a model invokes a tool, the arguments are parsed and wrapped
/// in a [ToolParams] instance, which provides typed getters for each
/// parameter type.
///
/// Example:
/// ```dart
/// handler: (params) async {
///   final location = params.getString('location');
///   final unit = params.getString('unit') ?? 'celsius';
///   return 'Weather in $location';
/// }
/// ```
class ToolParams {
  final Map<String, dynamic> _data;

  /// Creates a [ToolParams] wrapper around the raw argument map.
  const ToolParams(this._data);

  /// Returns the raw argument map.
  Map<String, dynamic> get raw => Map.unmodifiable(_data);

  /// Gets a string parameter by [name].
  ///
  /// Returns `null` if the parameter is not present.
  /// Throws [ArgumentError] if the value is not a string.
  String? getString(String name) {
    final value = _data[name];
    if (value == null) return null;
    if (value is! String) {
      throw ArgumentError('Parameter "$name" is not a string: $value');
    }
    return value;
  }

  /// Gets a required string parameter by [name].
  ///
  /// Throws [ArgumentError] if the parameter is missing or not a string.
  String getRequiredString(String name) {
    final value = getString(name);
    if (value == null) {
      throw ArgumentError('Required parameter "$name" is missing');
    }
    return value;
  }

  /// Gets an integer parameter by [name].
  ///
  /// Returns `null` if the parameter is not present.
  /// Throws [ArgumentError] if the value is not an integer.
  int? getInt(String name) {
    final value = _data[name];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw ArgumentError('Parameter "$name" is not an integer: $value');
  }

  /// Gets a required integer parameter by [name].
  ///
  /// Throws [ArgumentError] if the parameter is missing or not an integer.
  int getRequiredInt(String name) {
    final value = getInt(name);
    if (value == null) {
      throw ArgumentError('Required parameter "$name" is missing');
    }
    return value;
  }

  /// Gets a number (double) parameter by [name].
  ///
  /// Returns `null` if the parameter is not present.
  /// Throws [ArgumentError] if the value is not a number.
  double? getDouble(String name) {
    final value = _data[name];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw ArgumentError('Parameter "$name" is not a number: $value');
  }

  /// Gets a required number (double) parameter by [name].
  ///
  /// Throws [ArgumentError] if the parameter is missing or not a number.
  double getRequiredDouble(String name) {
    final value = getDouble(name);
    if (value == null) {
      throw ArgumentError('Required parameter "$name" is missing');
    }
    return value;
  }

  /// Gets a boolean parameter by [name].
  ///
  /// Returns `null` if the parameter is not present.
  /// Throws [ArgumentError] if the value is not a boolean.
  bool? getBool(String name) {
    final value = _data[name];
    if (value == null) return null;
    if (value is! bool) {
      throw ArgumentError('Parameter "$name" is not a boolean: $value');
    }
    return value;
  }

  /// Gets a required boolean parameter by [name].
  ///
  /// Throws [ArgumentError] if the parameter is missing or not a boolean.
  bool getRequiredBool(String name) {
    final value = getBool(name);
    if (value == null) {
      throw ArgumentError('Required parameter "$name" is missing');
    }
    return value;
  }

  /// Gets a list parameter by [name].
  ///
  /// Returns `null` if the parameter is not present.
  /// Throws [ArgumentError] if the value is not a list.
  List<T>? getList<T>(String name) {
    final value = _data[name];
    if (value == null) return null;
    if (value is! List) {
      throw ArgumentError('Parameter "$name" is not a list: $value');
    }
    return value.cast<T>();
  }

  /// Gets a required list parameter by [name].
  ///
  /// Throws [ArgumentError] if the parameter is missing or not a list.
  List<T> getRequiredList<T>(String name) {
    final value = getList<T>(name);
    if (value == null) {
      throw ArgumentError('Required parameter "$name" is missing');
    }
    return value;
  }

  /// Gets a nested object parameter by [name] as [ToolParams].
  ///
  /// Returns `null` if the parameter is not present.
  /// Throws [ArgumentError] if the value is not a map.
  ToolParams? getObject(String name) {
    final value = _data[name];
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw ArgumentError('Parameter "$name" is not an object: $value');
    }
    return ToolParams(value);
  }

  /// Gets a required nested object parameter by [name] as [ToolParams].
  ///
  /// Throws [ArgumentError] if the parameter is missing or not a map.
  ToolParams getRequiredObject(String name) {
    final value = getObject(name);
    if (value == null) {
      throw ArgumentError('Required parameter "$name" is missing');
    }
    return value;
  }

  /// Returns `true` if the parameter [name] exists in the arguments.
  bool has(String name) => _data.containsKey(name);

  /// Gets a raw dynamic value by [name].
  dynamic operator [](String name) => _data[name];

  @override
  String toString() => 'ToolParams($_data)';
}
