import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CodeBlock extends StatefulWidget {
  const CodeBlock({super.key, required this.code, this.language});

  final String code;
  final String? language;

  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;

  String _normalizeLanguage(String? lang) {
    if (lang == null || lang.isEmpty) return '';
    return lang.toUpperCase();
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF5F5F5);

    final headerBgColor = isDark
        ? const Color(0xFF2D2D2D)
        : const Color(0xFFE8E8E8);

    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFE0E0E0);

    final textColor = isDark
        ? const Color(0xFF9CDCFE)
        : const Color(0xFF001080);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: headerBgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(7),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _normalizeLanguage(widget.language),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF666666),
                    fontFamily: 'monospace',
                  ),
                ),
                GestureDetector(
                  onTap: _copyToClipboard,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 14,
                        color: _copied
                            ? Colors.green
                            : (isDark
                                  ? const Color(0xFF888888)
                                  : const Color(0xFF666666)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _copied ? 'Copied!' : 'Copy',
                        style: TextStyle(
                          fontSize: 11,
                          color: _copied
                              ? Colors.green
                              : (isDark
                                    ? const Color(0xFF888888)
                                    : const Color(0xFF666666)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
