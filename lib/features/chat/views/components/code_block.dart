import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_syntax_view/flutter_syntax_view.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../settings/data/models/app_settings.dart';

class CodeBlock extends ConsumerWidget {
  const CodeBlock({super.key, required this.code, this.language});

  final String code;
  final String? language;

  Syntax? _mapLanguage(String? lang) {
    if (lang == null || lang.isEmpty) return null;

    switch (lang.toLowerCase()) {
      case 'dart':
      case 'flutter':
        return Syntax.DART;
      case 'c':
        return Syntax.C;
      case 'cpp':
      case 'c++':
      case 'cxx':
        return Syntax.CPP;
      case 'java':
        return Syntax.JAVA;
      case 'javascript':
      case 'js':
        return Syntax.JAVASCRIPT;
      case 'kotlin':
      case 'kt':
        return Syntax.KOTLIN;
      case 'lua':
        return Syntax.LUA;
      case 'python':
      case 'py':
        return Syntax.PYTHON;
      case 'rust':
      case 'rs':
        return Syntax.RUST;
      case 'swift':
        return Syntax.SWIFT;
      case 'yaml':
      case 'yml':
        return Syntax.YAML;
      default:
        return null;
    }
  }

  SyntaxTheme _getSyntaxTheme(SyntaxThemeName themeName) {
    switch (themeName) {
      case SyntaxThemeName.vscodeDark:
        return SyntaxTheme.vscodeDark();
      case SyntaxThemeName.vscodeLight:
        return SyntaxTheme.vscodeLight();
      case SyntaxThemeName.dracula:
        return SyntaxTheme.dracula();
      case SyntaxThemeName.monokaiSublime:
        return SyntaxTheme.monokaiSublime();
      case SyntaxThemeName.ayuLight:
        return SyntaxTheme.ayuLight();
      case SyntaxThemeName.ayuDark:
        return SyntaxTheme.ayuDark();
      case SyntaxThemeName.gravityLight:
        return SyntaxTheme.gravityLight();
      case SyntaxThemeName.gravityDark:
        return SyntaxTheme.gravityDark();
      case SyntaxThemeName.obsidian:
        return SyntaxTheme.obsidian();
      case SyntaxThemeName.oceanSunset:
        return SyntaxTheme.oceanSunset();
      case SyntaxThemeName.standard:
        return SyntaxTheme.standard();
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
    final settings = ref.watch(settingsProvider);
    final themeName = isDark ? settings.codeThemeDark : settings.codeThemeLight;
    final codeTheme = _getSyntaxTheme(themeName);

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

    final syntax = _mapLanguage(language);
    final syntaxTheme = codeTheme.copyWith(backgroundColor: Colors.transparent);

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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: syntax != null
                ? SelectableText.rich(
                    TextSpan(
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.5,
                      ),
                      children: <TextSpan>[
                        getSyntax(syntax, syntaxTheme).format(code),
                      ],
                    ),
                  )
                : SelectableText(
                    code,
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
