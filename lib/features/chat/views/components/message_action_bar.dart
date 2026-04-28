import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../tts/providers/tts_providers.dart';

class MessageActionBar extends ConsumerStatefulWidget {
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
  ConsumerState<MessageActionBar> createState() => _MessageActionBarState();
}

class _MessageActionBarState extends ConsumerState<MessageActionBar> {
  bool _isSpeaking = false;
  bool _isInitializing = false;

  void _toggleTts() async {
    final ttsNotifier = ref.read(unifiedTtsProvider.notifier);
    final ttsState = ref.read(unifiedTtsProvider);

    if (_isSpeaking || ttsState.isSpeaking) {
      await ttsNotifier.stop();
      if (mounted) setState(() => _isSpeaking = false);
    } else {
      setState(() {
        _isInitializing = true;
        _isSpeaking = true;
      });
      try {
        await ttsNotifier.speak(widget.content);
      } finally {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _isInitializing = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ttsState = ref.watch(unifiedTtsProvider);
    final isTtsActive = _isSpeaking || ttsState.isSpeaking;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy,
          label: 'Copy',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: widget.content));
            widget.onCopy?.call();
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
        if (widget.onRetry != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.refresh,
            label: 'Retry',
            onTap: widget.onRetry,
          ),
        ],
        if (widget.onEdit != null) ...[
          const SizedBox(width: 4),
          _ActionButton(icon: Icons.edit, label: 'Edit', onTap: widget.onEdit),
        ],
        if (widget.onDelete != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.delete_outline,
            label: 'Delete',
            onTap: () => _showDeleteConfirmation(context),
            isDestructive: true,
          ),
        ],
        if (widget.onShare != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.ios_share,
            label: 'Share',
            onTap: widget.onShare,
          ),
        ],
        const SizedBox(width: 4),
        _ActionButton(
          icon: isTtsActive
              ? Icons.stop_circle
              : (_isInitializing ? Icons.hourglass_top : Icons.volume_up),
          label: isTtsActive
              ? 'Stop'
              : (_isInitializing ? 'Loading TTS...' : 'Read Aloud'),
          onTap: _isInitializing ? null : _toggleTts,
        ),
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
              widget.onDelete?.call();
            },
          ),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    final ttsState = ref.read(unifiedTtsProvider);
    final isTtsActive = _isSpeaking || ttsState.isSpeaking;

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
                Clipboard.setData(ClipboardData(text: widget.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied as Markdown')),
                );
              },
            ),
            ListTile(
              leading: Icon(isTtsActive ? Icons.stop : Icons.volume_up),
              title: Text(isTtsActive ? 'Stop Reading' : 'Read Aloud'),
              onTap: () {
                Navigator.of(context).pop();
                _toggleTts();
              },
            ),
            if (widget.onShare != null)
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Share'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onShare?.call();
                },
              ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: Text('${widget.content.length} characters'),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
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
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final baseColor = widget.isDestructive
        ? (isDark ? Colors.red[300] : Colors.red[600])
        : (isDark ? const Color(0xFF888888) : const Color(0xFF666666));

    final hoverColor = widget.isDestructive
        ? (isDark ? Colors.red[200] : Colors.red[500])
        : (isDark ? const Color(0xFFAAAAAA) : const Color(0xFF444444));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          onTapDown: widget.onTap != null ? (_) => _controller.forward() : null,
          onTapUp: widget.onTap != null ? (_) => _controller.reverse() : null,
          onTapCancel: widget.onTap != null
              ? () => _controller.reverse()
              : null,
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _scaleAnimation.value,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeInOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: _isHovered
                    ? (isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFE5E5E5))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                widget.icon,
                size: 16,
                color: _isHovered ? hoverColor : baseColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
