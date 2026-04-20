import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syntax_highlight/syntax_highlight.dart';
import '../../../../core/providers/highlighter_provider.dart';

class CodeBlock extends ConsumerWidget {
  const CodeBlock({super.key, required this.code, this.language});

  final String code;
  final String? language;

  String _mapLanguage(String? lang) {
    if (lang == null || lang.isEmpty) return '';

    final lower = lang.toLowerCase();
    switch (lower) {
      case 'dart':
      case 'flutter':
        return 'dart';
      case 'c':
        return 'c';
      case 'cpp':
      case 'c++':
      case 'cxx':
        return 'cpp';
      case 'csharp':
      case 'cs':
        return 'csharp';
      case 'go':
      case 'golang':
        return 'go';
      case 'java':
        return 'java';
      case 'javascript':
      case 'js':
        return 'javascript';
      case 'typescript':
      case 'ts':
        return 'typescript';
      case 'kotlin':
      case 'kt':
        return 'kotlin';
      case 'lua':
        return 'lua';
      case 'python':
      case 'py':
        return 'python';
      case 'rust':
      case 'rs':
        return 'rust';
      case 'swift':
        return 'swift';
      case 'yaml':
      case 'yml':
        return 'yaml';
      case 'html':
      case 'htm':
        return 'html';
      case 'css':
        return 'css';
      case 'json':
        return 'json';
      case 'sql':
        return 'sql';
      default:
        return lower;
    }
  }

  String _normalizeLanguage(String? lang) {
    if (lang == null || lang.isEmpty) return '';
    return lang.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themes = ref.watch(highlighterThemesProvider);

    final languageName = _mapLanguage(language);

    final backgroundColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF5F5F5);

    final headerBgColor = isDark
        ? const Color(0xFF2D2D2D)
        : const Color(0xFFE8E8E8);

    final borderColor = isDark
        ? const Color(0xFF3A3A3A)
        : const Color(0xFFE0E0E0);

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
                  _normalizeLanguage(language),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF666666),
                    fontFamily: 'monospace',
                  ),
                ),
                _CopyButton(code: code, isDark: isDark),
              ],
            ),
          ),
          themes.when(
            data: (themesData) {
    final loadedTheme = isDark ? themesData.dark : themesData.light;
    final highlighter = Highlighter(
      language: languageName.isNotEmpty ? languageName : 'dart',
      theme: loadedTheme,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
          children: <TextSpan>[
            highlighter.highlight(code),
          ],
        ),
      ),
    );
            },
            loading: () => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
            error: (e, _) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code, required this.isDark});

  final String code;
  final bool isDark;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

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
    return GestureDetector(
      onTap: _copyToClipboard,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _copied ? Icons.check : Icons.copy,
            size: 14,
            color: _copied
                ? Colors.green
                : (widget.isDark
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
                  : (widget.isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF666666)),
            ),
          ),
        ],
      ),
    );
  }
}
