---
name: shadcn_ui-accordion
description: Build collapsible accordions with ShadAccordion and ShadAccordionItem; single or multiple open items. Use when adding expandable sections, FAQs, or vertically stacked reveal content in a Flutter shadcn_ui app.
---

# Shadcn UI — Accordion

## Instructions

Use `ShadAccordion` for a vertically stacked set of headings that each reveal content. Each item is a `ShadAccordionItem` with `value`, `title`, and `child`.

### Single (one open at a time)

```dart
final details = [
  (title: 'Is it acceptable?', content: 'Yes. It adheres to the WAI-ARIA design pattern.'),
  (title: 'Is it styled?', content: "Yes. It comes with default styles that matches the other components' aesthetic."),
  (title: 'Is it animated?', content: "Yes. It's animated by default, but you can disable it if you prefer."),
];

ShadAccordion<({String content, String title})>(
  children: details.map(
    (detail) => ShadAccordionItem(
      value: detail,
      title: Text(detail.title),
      child: Text(detail.content),
    ),
  ),
)
```

### Multiple (several open at once)

Use `ShadAccordion.multiple`:

```dart
ShadAccordion<({String content, String title})>.multiple(
  children: details.map(
    (detail) => ShadAccordionItem(
      value: detail,
      title: Text(detail.title),
      child: Text(detail.content),
    ),
  ),
)
```
