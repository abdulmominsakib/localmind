---
name: shadcn_ui-select
description: Use ShadSelect for dropdown option lists; ShadOption, placeholder, selectedOptionBuilder, scrollable groups, ShadSelect.withSearch, ShadSelect.multiple, ShadSelectFormField. Use when adding dropdowns, single/multi select, or searchable select in a Flutter shadcn_ui app.
---

# Shadcn UI — Select

## Instructions

`ShadSelect<T>` displays a list of options triggered by a button. Provide `options` (list of `ShadOption<T>` or section headers like `Padding` with text), `placeholder`, `selectedOptionBuilder: (context, value) => ...`, and `onChanged`. Use `initialValue` or controlled state for selected value. Set `minWidth`/`maxWidth`/`maxHeight` as needed. For forms use `ShadSelectFormField<T>` with `id`, `validator`. Use `allowDeselection: true` to allow clearing the selection.

### Basic

```dart
final fruits = {'apple': 'Apple', 'banana': 'Banana', ...};

ShadSelect<String>(
  placeholder: const Text('Select a fruit'),
  options: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        'Fruits',
        style: theme.textTheme.muted.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.popoverForeground,
        ),
        textAlign: TextAlign.start,
      ),
    ),
    ...fruits.entries.map((e) => ShadOption(value: e.key, child: Text(e.value))),
  ],
  selectedOptionBuilder: (context, value) => Text(fruits[value]!),
  onChanged: print,
)
```

### Form field

```dart
ShadSelectFormField<String>(
  id: 'email',
  minWidth: 350,
  initialValue: null,
  options: verifiedEmails
      .map((email) => ShadOption(value: email, child: Text(email)))
      .toList(),
  selectedOptionBuilder: (context, value) =>
      value == 'none' ? const Text('Select a verified email to display') : Text(value),
  placeholder: const Text('Select a verified email to display'),
  validator: (v) {
    if (v == null) return 'Please select an email to display';
    return null;
  },
)
```

### With search

Use `ShadSelect.withSearch`. Pass `onSearchChanged`, `searchPlaceholder`, and filter options in state (e.g. wrap options in `Offstage(offstage: !filtered.containsKey(key), child: ShadOption(...))` to avoid focus loss when results change).

### Multiple

Use `ShadSelect.multiple`. Pass `selectedOptionsBuilder: (context, values) => ...`, `onChanged`, and optionally `allowDeselection: true`, `closeOnSelect: false` to keep popover open after selection.

## Additional resources

Scrollable option lists (grouped sections) and full search/multiple examples: [reference.md](reference.md).
