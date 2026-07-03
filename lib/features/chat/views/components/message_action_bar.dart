import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/theme/colors.dart';
import '../../../saved_messages/providers/saved_message_providers.dart';
import '../../../tts/providers/tts_providers.dart' as tts;
import '../../providers/message_selection_provider.dart';

class MessageActionBar extends ConsumerStatefulWidget {
  const MessageActionBar({
    super.key,
    required this.content,
    this.messageId,
    this.conversationId,
    this.tokenCount,
    this.inputTokenCount,
    this.generationTimeMs,
    this.ttftMs,
    this.tokensPerSecond,
    this.stopReason,
    this.onCopy,
    this.onRetry,
    this.onDelete,
    this.onEdit,
    this.onShare,
    this.onBranch,
    this.onContinue,
    this.onSave,
  });

  final String content;
  final String? messageId;
  final String? conversationId;
  final int? tokenCount;
  final int? inputTokenCount;
  final int? generationTimeMs;
  final int? ttftMs;
  final double? tokensPerSecond;
  final String? stopReason;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onBranch;
  final VoidCallback? onContinue;
  final VoidCallback? onSave;

  @override
  ConsumerState<MessageActionBar> createState() => _MessageActionBarState();
}

class _MessageActionBarState extends ConsumerState<MessageActionBar> {
  void _toggleTts() async {
    final ttsNotifier = ref.read(tts.ttsProvider.notifier);
    final ttsState = ref.read(tts.ttsProvider);
    final isThisActive = _isMessageActive(ttsState);

    if (isThisActive) {
      ttsNotifier.togglePauseResume();
    } else {
      if (ttsState.isSpeaking || ttsState.isPaused) {
        await ttsNotifier.stop();
      }
      try {
        await ttsNotifier.speak(
          widget.content,
          messageId: widget.messageId,
          conversationId: widget.conversationId,
        );
      } catch (_) {}
    }
  }

  bool _isMessageActive(tts.TtsState ttsState) {
    if (widget.messageId != null &&
        ttsState.playingMessageId == widget.messageId) {
      return ttsState.isSpeaking || ttsState.isPaused;
    }
    return ttsState.playingContent == widget.content &&
        (ttsState.isSpeaking || ttsState.isPaused);
  }

  String _formatMs(int ms) {
    if (ms >= 1000) {
      return '${(ms / 1000).toStringAsFixed(2)}s';
    }
    return '${ms}ms';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ttsState = ref.watch(tts.ttsProvider);
    final isThisActive = _isMessageActive(ttsState);
    final isThisPlaying =
        isThisActive && ttsState.isSpeaking && !ttsState.isPaused;
    final isThisInitializing = isThisActive && ttsState.isInitializing;
    final isSaved = widget.messageId != null
        ? ref.watch(isMessageSavedProvider(widget.messageId!)).value ?? false
        : false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: Icons.copy,
          label: l10n.copy,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: widget.content));
            widget.onCopy?.call();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.copied_to_clipboard),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
        if (widget.onSave != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
            label: isSaved ? l10n.message_already_saved : l10n.save_message,
            onTap: widget.onSave,
            isActive: isSaved,
          ),
        ],
        if (widget.onRetry != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.refresh,
            label: l10n.retry,
            onTap: widget.onRetry,
          ),
        ],
        if (widget.onContinue != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.arrow_forward,
            label: l10n.continue_action,
            onTap: widget.onContinue,
          ),
        ],
        if (widget.onEdit != null) ...[
          const SizedBox(width: 4),
          _ActionButton(icon: Icons.edit, label: l10n.edit, onTap: widget.onEdit),
        ],
        if (widget.onDelete != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.delete_outline,
            label: l10n.delete,
            onTap: () => _showDeleteConfirmation(context),
            isDestructive: true,
          ),
        ],
        if (widget.onShare != null) ...[
          const SizedBox(width: 4),
          _ActionButton(
            icon: Icons.ios_share,
            label: l10n.share,
            onTap: widget.onShare,
          ),
        ],
        const SizedBox(width: 4),
        _ActionButton(
          icon: isThisActive
              ? (isThisPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled)
              : (isThisInitializing ? Icons.hourglass_top : Icons.volume_up),
          label: isThisActive
              ? (isThisPlaying ? l10n.pause : l10n.resume)
              : (isThisInitializing ? l10n.initializing : l10n.read_aloud),
          onTap: isThisInitializing ? null : _toggleTts,
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.more_horiz,
          label: l10n.more,
          onTap: () => _showMoreOptions(context, isSaved),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    final dlgL10n = AppLocalizations.of(context)!;
    showShadDialog(
      context: context,
      builder: (context) => ShadDialog(
        title: Text(dlgL10n.delete_message_title),
        description: Text(dlgL10n.cannot_undo),
        actions: [
          ShadButton(
            child: Text(dlgL10n.cancel),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ShadButton(
            child: Text(dlgL10n.delete),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDelete?.call();
            },
          ),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context, bool isSaved) {
    final sheetL10n = AppLocalizations.of(context)!;
    final ttsState = ref.read(tts.ttsProvider);
    final isThisActive = _isMessageActive(ttsState);
    final isThisPlaying =
        isThisActive && ttsState.isSpeaking && !ttsState.isPaused;
    final theme = Theme.of(context);

    final stats = <({String label, String value})>[];
    stats.add((
      label: sheetL10n.characters_label,
      value: '${widget.content.length}',
    ));
    if (widget.ttftMs != null) {
      stats.add((
        label: sheetL10n.stream_ttft,
        value: _formatMs(widget.ttftMs!),
      ));
    }
    if (widget.generationTimeMs != null) {
      stats.add((
        label: sheetL10n.stream_generation_time,
        value: _formatMs(widget.generationTimeMs!),
      ));
    }
    if (widget.inputTokenCount != null) {
      stats.add((
        label: sheetL10n.stream_input_tokens,
        value: '${widget.inputTokenCount}',
      ));
    }
    if (widget.tokenCount != null) {
      stats.add((
        label: sheetL10n.stream_output_tokens,
        value: '${widget.tokenCount}',
      ));
    }
    if (widget.tokensPerSecond != null) {
      stats.add((
        label: sheetL10n.stream_tokens_per_sec,
        value: widget.tokensPerSecond!.toStringAsFixed(1),
      ));
    }
    if (widget.stopReason != null && widget.stopReason!.isNotEmpty) {
      stats.add((
        label: sheetL10n.stream_stop_reason,
        value: widget.stopReason!,
      ));
    }

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  sheetL10n.message_options,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              _CompactOptionTile(
                icon: Icons.code,
                label: sheetL10n.copy_markdown,
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: widget.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(sheetL10n.copied_markdown)),
                  );
                },
              ),
              if (widget.messageId != null)
                _CompactOptionTile(
                  icon: Icons.checklist_outlined,
                  label: sheetL10n.select,
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(messageSelectionModeProvider.notifier).enable();
                    ref
                        .read(selectedMessageIdsProvider.notifier)
                        .toggle(widget.messageId!);
                  },
                ),
              _CompactOptionTile(
                icon: isThisActive
                    ? (isThisPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled)
                    : Icons.volume_up,
                label: isThisActive
                    ? (isThisPlaying ? sheetL10n.pause : sheetL10n.resume)
                    : sheetL10n.read_aloud,
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleTts();
                },
              ),
              if (widget.onShare != null)
                _CompactOptionTile(
                  icon: Icons.ios_share,
                  label: sheetL10n.share,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onShare?.call();
                  },
                ),
              if (widget.onBranch != null)
                _CompactOptionTile(
                  icon: Icons.call_split,
                  label: sheetL10n.branch_chat,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onBranch?.call();
                  },
                ),
              if (widget.onSave != null)
                _CompactOptionTile(
                  icon: isSaved ? Icons.bookmark : Icons.bookmark_outline,
                  label: isSaved
                      ? sheetL10n.message_already_saved
                      : sheetL10n.save_message,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onSave?.call();
                  },
                ),
              if (stats.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 3.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: stats.length,
                    itemBuilder: (context, index) {
                      final stat = stats[index];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              stat.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              stat.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactOptionTile extends StatelessWidget {
  const _CompactOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: onTap,
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.isActive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isActive;

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

    final baseColor = widget.isActive
        ? theme.colorScheme.primary
        : widget.isDestructive
            ? (isDark ? Colors.red[300] : Colors.red[600])
            : (isDark ? AppColors.darkMutedText : AppColors.lightMutedText);

    final hoverColor = widget.isDestructive
        ? (isDark ? Colors.red[200] : Colors.red[500])
        : (isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText);

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
                          ? AppColors.darkSurfaceCard
                          : AppColors.lightBorder)
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
