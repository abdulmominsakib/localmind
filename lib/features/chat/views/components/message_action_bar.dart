import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class MessageActionBar extends StatelessWidget {
  const MessageActionBar({
    super.key,
    required this.content,
    this.onCopy,
    this.onRetry,
    this.onDelete,
    this.onEdit,
    this.onShare,
  });

  final String content;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy,
          label: 'Copy',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: content));
            onCopy?.call();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
        if (onRetry != null) ...[
          const SizedBox(width: 4),
          _ActionButton(icon: Icons.refresh, label: 'Retry', onTap: onRetry),
        ],
        if (onEdit != null) ...[
          const SizedBox(width: 4),
          _ActionButton(icon: Icons.edit, label: 'Edit', onTap: onEdit),
        ],
        if (onDelete != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onTap: () => _showDeleteConfirmation(context),
            isDestructive: true,
          ),
        ],
        if (onShare != null) ...[
          const SizedBox(width: 4),
          _ActionButton(icon: Icons.ios_share, label: 'Share', onTap: onShare),
        ],
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.more_horiz,
          label: 'More',
          onTap: () => _showMoreOptions(context),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('Delete message?'),
        description: const Text('This action cannot be undone.'),
        actions: [
          ShadButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ShadButton(
            child: const Text('Delete'),
            onPressed: () {
              Navigator.of(context).pop();
              onDelete?.call();
            },
          ),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showShadSheet(
      context: context,
      builder: (context) => ShadSheet(
        title: const Text('Message options'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Copy as Markdown'),
              onTap: () {
                Navigator.of(context).pop();
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied as Markdown')),
                );
              },
            ),
            if (onShare != null)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Share'),
                onTap: () {
                  Navigator.of(context).pop();
                  onShare?.call();
                },
              ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text('${content.length} characters'),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final color = isDestructive
        ? (isDark ? Colors.red[300] : Colors.red[600])
        : (isDark ? const Color(0xFF888888) : const Color(0xFF666666));

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
