/// Returns the container nesting depth of a JSON value, or `null` when
/// [value] is not JSON (a non-string key, non-finite number, cycle or other
/// object). Iterative so deep untrusted input cannot exhaust the stack.
int? jsonValueDepth(Object? value) {
  bool scalar(Object? value) =>
      value == null ||
      value is String ||
      value is bool ||
      value is num && value.isFinite;
  Iterator<Object?>? children(Object? value) => switch (value) {
    Map() => value.entries.iterator,
    List() => value.iterator,
    _ => null,
  };
  if (scalar(value)) return 0;
  final root = children(value);
  if (root == null) return null;
  final active = Set<Object>.identity()..add(value!);
  final path = <(Object, Iterator<Object?>)>[(value, root)];
  var depth = 1;
  while (path.isNotEmpty) {
    final (container, iterator) = path.last;
    if (!iterator.moveNext()) {
      active.remove(container);
      path.removeLast();
      continue;
    }
    var child = iterator.current;
    if (container is Map) {
      final entry = child as MapEntry;
      if (entry.key is! String) return null;
      child = entry.value;
    }
    if (scalar(child)) continue;
    final next = children(child);
    if (next == null || !active.add(child!)) return null;
    path.add((child, next));
    if (path.length > depth) depth = path.length;
  }
  return depth;
}
