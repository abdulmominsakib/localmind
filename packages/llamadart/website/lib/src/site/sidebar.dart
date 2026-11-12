/// A sidebar entry: a doc link, an external link, or a category.
sealed class SidebarEntry {
  const SidebarEntry();
}

final class SidebarDoc extends SidebarEntry {
  const SidebarDoc(this.id, {this.label});

  final String id;
  final String? label;
}

final class SidebarHref extends SidebarEntry {
  const SidebarHref(this.label, this.href);

  final String label;
  final String href;
}

final class SidebarCategory extends SidebarEntry {
  const SidebarCategory(this.label, this.items);

  final String label;
  final List<SidebarEntry> items;
}

/// Parses the sidebar JSON used by `sidebars.json` and
/// `versioned_sidebars/*.json`.
Map<String, List<SidebarEntry>> parseSidebars(Map<String, Object?> json) => {
  for (final MapEntry(:key, :value) in json.entries)
    key: parseSidebarItems(value as List<Object?>),
};

List<SidebarEntry> parseSidebarItems(List<Object?> items) => [
  for (final item in items)
    switch (item) {
      final String id => SidebarDoc(id),
      {'type': 'doc', 'id': final String id} => SidebarDoc(
        id,
        label: item['label'] as String?,
      ),
      {
        'type': 'link',
        'label': final String label,
        'href': final String href,
      } =>
        SidebarHref(label, href),
      {
        'type': 'category',
        'label': final String label,
        'items': final List<Object?> items,
      } =>
        SidebarCategory(label, parseSidebarItems(items)),
      _ => throw FormatException('Unsupported sidebar item: $item'),
    },
];

/// Doc ids in reading order, each with its top-level category label.
List<(String, String?)> flattenSidebar(
  List<SidebarEntry> entries, [
  String? category,
]) => [
  for (final entry in entries)
    ...switch (entry) {
      SidebarDoc(:final id) => [(id, category)],
      SidebarCategory(:final label, :final items) => flattenSidebar(
        items,
        category ?? label,
      ),
      SidebarHref() => const <(String, String?)>[],
    },
];
