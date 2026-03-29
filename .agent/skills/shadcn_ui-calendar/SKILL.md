---
name: shadcn_ui-calendar
description: Use ShadCalendar for single, multiple, or range date selection; caption layout, hide navigation, week numbers, outside days, fixed weeks. Use when building date pickers or calendar widgets in a Flutter shadcn_ui app.
---

# Shadcn UI — Calendar

## Instructions

`ShadCalendar` is a date field that lets users enter and edit dates. Modes: single date, multiple dates (`ShadCalendar.multiple`), or range (`ShadCalendar.range`). Use `fromMonth`/`toMonth` to limit range; `captionLayout` for dropdown months/years.

### Single

```dart
final today = DateTime.now();

ShadCalendar(
  selected: today,
  fromMonth: DateTime(today.year - 1),
  toMonth: DateTime(today.year, 12),
)
```

### Multiple

```dart
ShadCalendar.multiple(
  numberOfMonths: 2,
  fromMonth: DateTime(today.year),
  toMonth: DateTime(today.year + 1, 12),
  min: 5,
  max: 10,
)
```

### Range

```dart
const ShadCalendar.range(
  min: 2,
  max: 5,
)
```

### Caption layout

```dart
ShadCalendar(
  captionLayout: ShadCalendarCaptionLayout.dropdownMonths,
);

ShadCalendar(
  captionLayout: ShadCalendarCaptionLayout.dropdownYears,
);
```

### Options

- `hideNavigation: true` — Hide month navigation.
- `showWeekNumbers: true` — Show week numbers.
- `showOutsideDays: false` — Hide days from adjacent months.
- `fixedWeeks: true` — Fixed number of rows.
- `hideWeekdayNames: true` — Hide weekday headers.
