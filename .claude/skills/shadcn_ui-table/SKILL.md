---
name: shadcn_ui-table
description: Build tables with ShadTable.list or ShadTable builder; ShadTableCell.header, ShadTableCell.footer, columnSpanExtent (FixedTableSpanExtent, RemainingTableSpanExtent). Use when displaying tabular data or responsive tables in a Flutter shadcn_ui app.
---

# Shadcn UI — Table

## Instructions

`ShadTable` is a responsive table. Use `ShadTable.list` for small tables (all rows built at once): pass `header`, `footer` (lists of `ShadTableCell.header` / `ShadTableCell.footer`), and `children` (list of row lists of `ShadTableCell`). Use `ShadTable` with `columnCount`, `rowCount`, `header`, `builder`, `footer` for large tables (on-demand building). Use `columnSpanExtent` to set column widths: `FixedTableSpanExtent(130)` or `MaxTableSpanExtent(FixedTableSpanExtent(120), RemainingTableSpanExtent())`.

### List (small tables)

```dart
ShadTable.list(
  header: const [
    ShadTableCell.header(child: Text('Invoice')),
    ShadTableCell.header(child: Text('Status')),
    ShadTableCell.header(child: Text('Method')),
    ShadTableCell.header(
      alignment: Alignment.centerRight,
      child: Text('Amount'),
    ),
  ],
  footer: const [
    ShadTableCell.footer(child: Text('Total')),
    ShadTableCell.footer(child: Text('')),
    ShadTableCell.footer(child: Text('')),
    ShadTableCell.footer(
      alignment: Alignment.centerRight,
      child: Text(r'$2500.00'),
    ),
  ],
  columnSpanExtent: (index) {
    if (index == 2) return const FixedTableSpanExtent(130);
    if (index == 3) {
      return const MaxTableSpanExtent(
        FixedTableSpanExtent(120),
        RemainingTableSpanExtent(),
      );
    }
    return null;
  },
  children: invoices.map(
    (invoice) => [
      ShadTableCell(
        child: Text(
          invoice.invoice,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      ShadTableCell(child: Text(invoice.paymentStatus)),
      ShadTableCell(child: Text(invoice.paymentMethod)),
      ShadTableCell(
        alignment: Alignment.centerRight,
        child: Text(invoice.totalAmount),
      ),
    ],
  ),
)
```

### Builder (large tables)

Use `ShadTable(columnCount:, rowCount:, header: (context, column) => ..., columnSpanExtent: (index) => ..., builder: (context, index) => ShadTableCell(...), footer: (context, column) => ...)`. The builder receives a table index with `row` and `column`. Prefer builder for large data so only visible rows are built.

## Additional resources

Detailed column span and builder patterns: [reference.md](reference.md).
