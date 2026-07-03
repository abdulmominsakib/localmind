import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/views/components/audio_player_widget.dart';
import 'deferred_markdown.dart';

final _blockDollarLatex = RegExp(r'\$\$([\s\S]+?)\$\$');
final _inlineDollarLatex = RegExp(r'\$([^\$\n]+?)\$');
final _currencyLike = RegExp(r'^\s*\d[\d,]*(\.\d+)?\s*$');

/// gpt_markdown only recognizes `\(...\)` / `\[...\]` for LaTeX, not the
/// `$...$` / `$$...$$` delimiters models most commonly output. Convert the
/// dollar forms to the ones gpt_markdown understands, skipping anything
/// that looks like plain currency (e.g. "$5" or "$10.99") so ordinary
/// prices aren't mistaken for math.
String normalizeDollarLatex(String input) {
  if (!input.contains(r'$')) return input;

  var result = input.replaceAllMapped(
    _blockDollarLatex,
    (m) => '\\[${m[1]!.trim()}\\]',
  );

  result = result.replaceAllMapped(_inlineDollarLatex, (m) {
    final inner = m[1]!;
    if (inner.trim().isEmpty || _currencyLike.hasMatch(inner)) {
      return m[0]!;
    }
    return '\\(${inner.trim()}\\)';
  });

  return result;
}

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
      highlightColor: isDark ? const Color(0xFF334155) : const Color(0xFFDBEAFE),
      linkColor: isDark ? AppColors.darkAccent : AppColors.lightAccent,
      linkHoverColor: isDark ? AppColors.darkAccent : AppColors.lightAccent,
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
        normalizeDollarLatex(content),
        style: style,
        followLinkColor: true,
        imageBuilder: _buildImageOrAudio,
        onLinkTap: (url, title) {
          if (_isAudioUrl(url) && context.mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                contentPadding: const EdgeInsets.all(16),
                content: AudioPlayerWidget(source: url),
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildImageOrAudio(
      BuildContext context, String url, double? width, double? height) {
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
          child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
        ),
      ),
    );
  }
}

class MarkdownContent extends StatelessWidget {
  const MarkdownContent({super.key, required this.content, required this.isDark});

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (content.length > 2000) {
      return DeferredMarkdownContent(content: content, isDark: isDark);
    }
    return MarkdownBodyContent(content: content, isDark: isDark);
  }
}

class MarkdownBodyContent extends StatelessWidget {
  const MarkdownBodyContent({super.key, required this.content, required this.isDark});

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ThemedGptMarkdown(
        content: content,
        isDark: isDark,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 15,
          height: 1.5,
        ),
      ),
    );
  }
}
