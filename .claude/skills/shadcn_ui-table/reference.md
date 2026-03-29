# Shadcn UI Table — Reference

## columnSpanExtent

Return `TableSpanExtent?` per column index:
- `FixedTableSpanExtent(130)` — fixed width.
- `MaxTableSpanExtent(FixedTableSpanExtent(120), RemainingTableSpanExtent())` — min 120, then remaining space.
- `null` — default extent.

## Builder API

`ShadTable` with:
- `columnCount`, `rowCount`
- `header: (context, column) => ShadTableCell.header(...)`
- `columnSpanExtent: (index) => ...`
- `builder: (context, index) => ShadTableCell(...)` where `index` has `index.row`, `index.column`
- `footer: (context, column) => ShadTableCell.footer(...)` or empty cell

Use for large tables so widgets are created on demand.
