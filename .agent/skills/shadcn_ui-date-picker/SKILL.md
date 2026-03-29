---
name: shadcn_ui-date-picker
description: Use ShadDatePicker and ShadDatePicker.range for single or range date selection; presets, ShadDatePickerFormField, ShadDateRangePickerFormField. Use when adding date pickers or date range fields in a Flutter shadcn_ui app or ShadForm.
---

# Shadcn UI — Date Picker

## Instructions

`ShadDatePicker` is a date picker with optional range and presets. Use `ShadDatePicker.range()` for range selection. For forms use `ShadDatePickerFormField` and `ShadDateRangePickerFormField` with `id`, `label`, `validator`, and optional `fromValueTransformer`/`toValueTransformer`.

### Single

```dart
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 600),
  child: const ShadDatePicker(),
)
```

### Range

```dart
ConstrainedBox(
  constraints: const BoxConstraints(maxWidth: 600),
  child: const ShadDatePicker.range(),
)
```

### With presets

Use a `header` widget (e.g. `ShadSelect`) and shared `groupId` so the date picker popover stays open when the select popover closes. Set `selected` from preset choice (e.g. today + days offset).

```dart
ShadDatePicker(
  groupId: groupId,
  header: Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ShadSelect<int>(
      groupId: groupId,
      minWidth: 276,
      placeholder: const Text('Select'),
      options: presets.entries
          .map((e) => ShadOption(value: e.key, child: Text(e.value)))
          .toList(),
      selectedOptionBuilder: (context, value) => Text(presets[value]!),
      onChanged: (value) {
        if (value == null) return;
        setState(() => selected = today.add(Duration(days: value)));
      },
    ),
  ),
  selected: selected,
  calendarDecoration: theme.calendarTheme.decoration,
  popoverPadding: const EdgeInsets.all(4),
)
```

### Form fields

```dart
ShadDatePickerFormField(
  label: const Text('Date of birth'),
  onChanged: print,
  description: const Text('Your date of birth is used to calculate your age.'),
  validator: (v) {
    if (v == null) return 'A date of birth is required.';
    return null;
  },
)

ShadDateRangePickerFormField(
  label: const Text('Range of dates'),
  onChanged: print,
  description: const Text('Select the range of dates you want to search between.'),
  validator: (v) {
    if (v == null) return 'A range of dates is required.';
    if (v.start == null) return 'The start date is required.';
    if (v.end == null) return 'The end date is required.';
    return null;
  },
)
```

For form initial value as string (e.g. `'date': '2024-02-01'`), use `fromValueTransformer` and `toValueTransformer` on `ShadDatePickerFormField` to convert to/from `DateTime`. See [reference.md](reference.md) or the Form skill for value transformers.
