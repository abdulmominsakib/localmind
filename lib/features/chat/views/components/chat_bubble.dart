import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/views/components/code_block.dart';
import 'package:localmind/features/chat/views/components/message_action_bar.dart';
import 'package:localmind/features/chat/views/components/typing_indicator.dart';
import 'package:localmind/features/chat/views/components/reasoning_widget.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onRetry,
    this.onDelete,
    this.isStreaming = false,
  });

  final Message message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    switch (message.role) {
      case MessageRole.user:
        return _UserBubble(message: message);
      case MessageRole.assistant:
        return _AssistantBubble(
          message: message,
          onCopy: onCopy,
          onRetry: onRetry,
          onDelete: onDelete,
          isStreaming: isStreaming,
        );
      case MessageRole.system:
        return _SystemBubble(message: message);
      case MessageRole.tool:
        return _ToolBubble(message: message);
    }
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(left: 48, right: 8, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
          borderRadius: BorderRadius.circular(
            18,
          ).copyWith(bottomRight: const Radius.circular(4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MarkdownBody(
              data: message.content,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
              ),
              shrinkWrap: true,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                if (message.status == MessageStatus.error) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.error_outline, size: 14, color: Colors.red[200]),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.message,
    this.onCopy,
    this.onRetry,
    this.onDelete,
    this.isStreaming = false,
  });

  final Message message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.only(left: 8, right: 48, top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(
            18,
          ).copyWith(bottomLeft: const Radius.circular(4)),
          border: Border.all(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.reasoningContent != null &&
                message.reasoningContent!.isNotEmpty)
              ReasoningWidget(
                reasoningContent: message.reasoningContent,
                isStreaming: isStreaming,
              ),
            if (isStreaming && message.content.isEmpty)
              const TypingIndicator()
            else
              _MarkdownContent(content: message.content, isDark: isDark),
            if (isStreaming && message.content.isNotEmpty)
              const StreamingIndicator(),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF666666)
                        : const Color(0xFF999999),
                  ),
                ),
                if (message.status == MessageStatus.error) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
                ],
              ],
            ),
            if (!isStreaming && message.status == MessageStatus.complete) ...[
              const SizedBox(height: 4),
              MessageActionBar(
                content: message.content,
                onCopy: onCopy,
                onRetry: onRetry,
                onDelete: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarkdownContent extends StatelessWidget {
  const _MarkdownContent({required this.content, required this.isDark});

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 15,
          height: 1.5,
        ),
        h1: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        h2: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        h3: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        h4: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        code: TextStyle(
          backgroundColor: isDark
              ? const Color(0xFF2D2D2D)
              : const Color(0xFFE8E8E8),
          color: isDark ? const Color(0xFF9CDCFE) : const Color(0xFF001080),
          fontFamily: 'monospace',
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: TextStyle(
          color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 16),
        listBullet: TextStyle(color: isDark ? Colors.white : Colors.black),
        tableHead: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
        ),
        tableBody: TextStyle(color: isDark ? Colors.white : Colors.black),
        tableBorder: TableBorder.all(
          color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
            ),
          ),
        ),
        a: TextStyle(
          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
          decoration: TextDecoration.underline,
        ),
      ),
      builders: {'code': CodeBlockBuilder(isDark: isDark)},
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;

  CodeBlockBuilder({required this.isDark});

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final code = element.textContent;
    String? language;

    if (element.attributes.containsKey('class')) {
      final classes = element.attributes['class']!;
      final langMatch = RegExp(r'language-(\w+)').firstMatch(classes);
      if (langMatch != null) {
        language = langMatch.group(1);
      }
    }

    return CodeBlock(code: code, language: language);
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ToolBubble extends StatelessWidget {
  const _ToolBubble({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: const EdgeInsets.only(left: 8, right: 48, top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF374151) : const Color(0xFFC7D2FE),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.build_outlined,
                  size: 14,
                  color: isDark
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 4),
                Text(
                  'Tool: ${message.toolCallId ?? "Unknown"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message.content,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : Colors.black87,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
