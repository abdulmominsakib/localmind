import 'dart:async';
import 'package:flutter/material.dart';
import 'themed_gpt_markdown.dart';
import 'streaming_text.dart';

class DeferredMarkdownContent extends StatefulWidget {
  const DeferredMarkdownContent({
    super.key,
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  State<DeferredMarkdownContent> createState() =>
      _DeferredMarkdownContentState();
}

class _DeferredMarkdownContentState extends State<DeferredMarkdownContent> {
  bool _showMarkdown = false;
  Timer? _deferTimer;

  @override
  void initState() {
    super.initState();
    _deferTimer = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        setState(() => _showMarkdown = true);
      }
    });
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(DeferredMarkdownContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.isDark != widget.isDark) {
      _showMarkdown = false;
      _deferTimer?.cancel();
      _deferTimer = Timer(const Duration(milliseconds: 120), () {
        if (mounted) {
          setState(() => _showMarkdown = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showMarkdown) {
      return StreamingTextContent(
        content: widget.content,
        isDark: widget.isDark,
      );
    }
    return MarkdownBodyContent(content: widget.content, isDark: widget.isDark);
  }
}
