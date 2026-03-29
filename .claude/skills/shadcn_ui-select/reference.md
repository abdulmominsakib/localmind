# Shadcn UI Select — Reference

## Scrollable / grouped options

Build `options` as a list of section headers (`Padding` with styled `Text`) followed by `ShadOption` widgets for that section. For large lists the select popover scrolls. Example for timezones by region:

```dart
List<Widget> getTimezonesWidgets(ShadThemeData theme) {
  final widgets = <Widget>[];
  for (final zone in timezones.entries) {
    widgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          zone.key,
          style: theme.textTheme.muted.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.popoverForeground,
          ),
          textAlign: TextAlign.start,
        ),
      ),
    );
    widgets.addAll(zone.value.entries
        .map((e) => ShadOption(value: e.key, child: Text(e.value))));
  }
  return widgets;
}

ShadSelect<String>(
  placeholder: const Text('Select a timezone'),
  options: getTimezonesWidgets(theme),
  selectedOptionBuilder: (context, value) {
    final timezone = timezones.entries
        .firstWhere((element) => element.value.containsKey(value))
        .value[value];
    return Text(timezone!);
  },
)
```

## With search

Use `ShadSelect<String>.withSearch`, maintain `searchValue` in state, compute `filteredFrameworks` (or similar), and pass `onSearchChanged: (value) => setState(() => searchValue = value)`. In `options`, show "No results" when filtered is empty; otherwise map entries and wrap each `ShadOption` in `Offstage(offstage: !filtered.containsKey(key), child: ShadOption(...))` so the widget stays in the tree and focus is preserved.

## Multiple selection

Use `ShadSelect<T>.multiple`. Provide `selectedOptionsBuilder: (context, values) => Text(values.join(', '))` (or similar), `onChanged`, and optionally `allowDeselection: true`, `closeOnSelect: false`. Tap outside the popover to close it.
