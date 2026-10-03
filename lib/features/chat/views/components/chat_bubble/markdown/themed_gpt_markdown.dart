import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:localmind/features/chat/utils/markdown_latex.dart';
import 'package:localmind/features/chat/utils/markdown_tables.dart';
import 'package:localmind/features/chat/views/components/audio_player_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'markdown_code_block.dart';
import 'markdown_table.dart';

class ThemedGptMarkdown extends StatelessWidget {
  const ThemedGptMarkdown({
    super.key,
    required this.content,
    required this.isDark,
    required this.style,
  });

  final String content;
  final bool isDark;
  final TextStyle style;

  static const _lightLinkColor = Color(0xFF1D4ED8);
  static const _darkLinkColor = Color(0xFF7AB4FF);

  static Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !const {'http', 'https', 'mailto'}.contains(uri.scheme)) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static bool _isAudioUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.wma') ||
        lower.endsWith('.opus');
  }

  @override
  Widget build(BuildContext context) {
    final gptTheme = GptMarkdownThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      highlightColor: isDark
          ? const Color(0xFF334155)
          : const Color(0xFFDBEAFE),
      linkColor: isDark ? _darkLinkColor : _lightLinkColor,
      linkHoverColor: isDark ? _darkLinkColor : _lightLinkColor,
      hrLineColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      hrLineThickness: 1.0,
      h1: style.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      h2: style.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
      h3: style.copyWith(fontSize: 19, fontWeight: FontWeight.w600),
      h4: style.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      h5: style.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h6: style.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    );

    return GptMarkdownTheme(
      gptThemeData: gptTheme,
      child: GptMarkdown(
        normalizeDollarLatex(normalizeMarkdownTables(content)),
        style: style,
        followLinkColor: true,
        imageBuilder: _buildImageOrAudio,
        codeBuilder: (context, name, code, closed) =>
            MarkdownCodeBlock(language: name, code: code, isDark: isDark),
        highlightBuilder: (context, text, style) =>
            MarkdownInlineCode(text: text, style: style, isDark: isDark),
        tableBuilder: (context, rows, textStyle, config) => MarkdownTable(
          rows: rows,
          style: textStyle,
          config: config,
          isDark: isDark,
        ),
        // gpt_markdown turns any `[digits]` into a citation chip, which
        // mangles code like `arr[0]`; local models don't cite sources.
        sourceTagBuilder: (context, content, _) =>
            Text('[$content]', style: style),
        onLinkTap: (url, title) {
          if (_isAudioUrl(url) && context.mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                contentPadding: const EdgeInsets.all(16),
                content: AudioPlayerWidget(source: url),
              ),
            );
            return;
          }
          _openLink(url);
        },
      ),
    );
  }

  Widget _buildImageOrAudio(
    BuildContext context,
    String url,
    double? width,
    double? height,
  ) {
    if (_isAudioUrl(url)) {
      return AudioPlayerWidget(source: url, height: 56);
    }
    return SizedBox(
      width: width,
      height: height,
      child: Image(
        image: NetworkImage(url),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[800],
          child: const Center(
            child: HugeIcon(
              icon: HugeIcons.strokeRoundedImageNotFound01,
              color: Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

class MarkdownContent extends StatelessWidget {
  const MarkdownContent({
    super.key,
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return MarkdownBodyContent(content: content, isDark: isDark);
  }
}

/// Renders formatted markdown body content.
///
/// Set [selectable] to false during active streaming to prevent Flutter
/// SelectionContainer concurrent modification crashes while the widget
/// tree is rapidly mutating (Issue #80).
class MarkdownBodyContent extends StatelessWidget {
  const MarkdownBodyContent({
    super.key,
    required this.content,
    required this.isDark,
    this.selectable = true,
  });

  final String content;
  final bool isDark;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final markdown = ThemedGptMarkdown(
      content: content,
      isDark: isDark,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black,
        fontSize: 15,
        height: 1.5,
      ),
    );

    if (!selectable) {
      return markdown;
    }

    return SelectionArea(child: markdown);
  }
}

/// Inline `code`: monospace on a subtle chip, instead of gpt_markdown's
/// default bold text on a highlight colour.
class MarkdownInlineCode extends StatelessWidget {
  const MarkdownInlineCode({
    super.key,
    required this.text,
    required this.style,
    required this.isDark,
  });

  final String text;
  final TextStyle style;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fontSize = (style.fontSize ?? 15) * 0.88;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFF0F0F2),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isDark ? const Color(0xFF3F3F3F) : const Color(0xFFE2E2E5),
        ),
      ),
      child: Text(
        text,
        style: style.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Roboto Mono', 'Courier'],
          fontSize: fontSize,
          height: 1.3,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
