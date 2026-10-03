import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/highlighter_provider.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

const _monoFontFamily = 'monospace';
const _monoFallback = ['Menlo', 'Roboto Mono', 'Courier'];

/// Fence labels models commonly use for the grammars the highlighter has.
const _languageAliases = {
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'rs': 'rust',
  'golang': 'go',
  'yml': 'yaml',
  'jsonc': 'json',
  'htm': 'html',
  'xml': 'html',
};

/// Normalizes a fence info string ("Python title=x") to the grammar name
/// the highlighter knows, or null when it has no grammar for it.
String? highlighterLanguageFor(String infoString) {
  final label = infoString.trim().split(RegExp(r'\s+')).first.toLowerCase();
  final language = _languageAliases[label] ?? label;
  return supportedHighlighterLanguages.contains(language) ? language : null;
}

/// A fenced code block: language label, copy button, and syntax-highlighted
/// code that scrolls sideways instead of wrapping.
class MarkdownCodeBlock extends ConsumerWidget {
  const MarkdownCodeBlock({
    super.key,
    required this.language,
    required this.code,
    required this.isDark,
  });

  /// The fence's info string, e.g. "dart" or "python title=main.py".
  final String language;
  final String code;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeName = ref.watch(
      settingsProvider.select(
        (s) => isDark ? s.codeThemeDark : s.codeThemeLight,
      ),
    );
    final themes = ref.watch(highlighterThemesProvider).value;
    final darkCode = themeName == SyntaxThemeName.dark;
    final colors = CodeBlockColors(isDark: darkCode);
    final label = language.trim().split(RegExp(r'\s+')).first;
    // Models often end the code with a newline before the closing fence.
    final source = code.endsWith('\n')
        ? code.substring(0, code.length - 1)
        : code;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeBlockHeader(label: label, code: source, colors: colors),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: HighlightedCode(
              code: source,
              language: highlighterLanguageFor(language),
              theme: themes == null
                  ? null
                  : (darkCode ? themes.dark : themes.light),
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class CodeBlockColors {
  const CodeBlockColors({required this.isDark});

  final bool isDark;

  Color get background =>
      isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF6F6F7);
  Color get header =>
      isDark ? const Color(0xFF2A2A2A) : const Color(0xFFEDEDEF);
  Color get border =>
      isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE2E2E5);
  Color get text => isDark ? const Color(0xFFD4D4D4) : const Color(0xFF24292F);
  Color get muted => isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B);
}

class CodeBlockHeader extends StatefulWidget {
  const CodeBlockHeader({
    super.key,
    required this.label,
    required this.code,
    required this.colors,
  });

  final String label;
  final String code;
  final CodeBlockColors colors;

  @override
  State<CodeBlockHeader> createState() => _CodeBlockHeaderState();
}

class _CodeBlockHeaderState extends State<CodeBlockHeader> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = widget.colors;
    final labelStyle = TextStyle(
      fontFamily: _monoFontFamily,
      fontFamilyFallback: _monoFallback,
      fontSize: 12,
      color: colors.muted,
    );

    return Container(
      height: 36,
      color: colors.header,
      padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.label,
              style: labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: _copy,
            style: TextButton.styleFrom(
              foregroundColor: colors.muted,
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
            icon: HugeIcon(
              icon: _copied
                  ? HugeIcons.strokeRoundedTick01
                  : HugeIcons.strokeRoundedCopy01,
              size: 15,
              color: colors.muted,
            ),
            label: Text(_copied ? l10n.copied : l10n.copy),
          ),
        ],
      ),
    );
  }
}

/// Code text, syntax-highlighted when [language] has a grammar and the
/// highlighter themes have loaded; plain monospace otherwise.
class HighlightedCode extends StatelessWidget {
  const HighlightedCode({
    super.key,
    required this.code,
    required this.language,
    required this.theme,
    required this.color,
  });

  final String code;
  final String? language;
  final HighlighterTheme? theme;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: _monoFontFamily,
      fontFamilyFallback: _monoFallback,
      fontSize: 13,
      height: 1.5,
      color: color,
    );

    return Text.rich(
      TextSpan(style: style, children: [_highlight()]),
      softWrap: false,
    );
  }

  InlineSpan _highlight() {
    final language = this.language;
    final theme = this.theme;
    if (language == null || theme == null) return TextSpan(text: code);
    try {
      return Highlighter(language: language, theme: theme).highlight(code);
    } catch (_) {
      // A grammar that wasn't initialized or chokes on partial input.
      return TextSpan(text: code);
    }
  }
}
