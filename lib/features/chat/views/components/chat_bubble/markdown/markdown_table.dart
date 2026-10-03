import 'package:flutter/material.dart';
import 'package:gpt_markdown/custom_widgets/markdown_config.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:localmind/features/chat/utils/markdown_tables.dart';

/// Widest a column grows before its cells wrap.
const _maxColumnWidth = 280.0;

final _lineBreakTag = RegExp(r'<br\s*/?>', caseSensitive: false);

/// A markdown table: rounded border, header band, soft row lines, cells
/// that wrap past [_maxColumnWidth], and sideways scrolling for wide tables.
class MarkdownTable extends StatelessWidget {
  const MarkdownTable({
    super.key,
    required this.rows,
    required this.style,
    required this.config,
    required this.isDark,
  });

  final List<CustomTableRow> rows;
  final TextStyle style;
  final GptMarkdownConfig config;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFE2E2E5);
    final headerColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFF4F4F5);
    final radius = BorderRadius.circular(10);
    final cellStyle = style.copyWith(
      fontSize: (style.fontSize ?? 15) - 1,
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: borderColor),
              ),
              child: Table(
                defaultColumnWidth: const MinColumnWidth(
                  IntrinsicColumnWidth(),
                  FixedColumnWidth(_maxColumnWidth),
                ),
                defaultVerticalAlignment: TableCellVerticalAlignment.top,
                border: TableBorder(
                  horizontalInside: BorderSide(color: borderColor),
                  verticalInside: BorderSide(color: borderColor),
                ),
                children: [
                  for (final row in rows)
                    TableRow(
                      decoration: row.isHeader
                          ? BoxDecoration(color: headerColor)
                          : null,
                      children: [
                        for (final field in row.fields)
                          MarkdownTableCell(
                            text: field.data,
                            alignment: field.alignment,
                            config: config.copyWith(
                              style: row.isHeader
                                  ? cellStyle.copyWith(
                                      fontWeight: FontWeight.w600,
                                    )
                                  : cellStyle,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarkdownTableCell extends StatelessWidget {
  const MarkdownTableCell({
    super.key,
    required this.text,
    required this.alignment,
    required this.config,
  });

  final String text;
  final TextAlign alignment;
  final GptMarkdownConfig config;

  @override
  Widget build(BuildContext context) {
    final content = text
        .trim()
        .replaceAll(escapedTablePipe, '|')
        .replaceAll(_lineBreakTag, '\n');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Align(
        alignment: switch (alignment) {
          TextAlign.center => Alignment.topCenter,
          TextAlign.right || TextAlign.end => AlignmentDirectional.topEnd,
          _ => AlignmentDirectional.topStart,
        },
        child: MdWidget(context, content, false, config: config),
      ),
    );
  }
}
