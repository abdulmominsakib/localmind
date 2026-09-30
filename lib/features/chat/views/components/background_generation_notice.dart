import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cue/cue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/services/app_haptics.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';

import '../../../conversations/providers/conversation_providers.dart' as conv;
import '../../providers/chat_providers.dart';
import 'heartbeat_dot.dart';

/// Shown above the input while replies for other chats are still generating
/// in the background (#94). Styled as a stacked card layer on top of the chat
/// input bar with a circular progress indicator at the right.
///
/// When several remote chats are generating, tapping the notice expands it
/// upwards to list them so the user can switch to any of them. Tapping a
/// single generation, or the notice while the on-device engine blocks
/// sending, opens that chat directly.
class BackgroundGenerationNotice extends ConsumerStatefulWidget {
  const BackgroundGenerationNotice({
    super.key,
    required this.generations,
    required this.blocksSending,
  });

  /// Replies running for chats other than the open one, in start order.
  final List<ActiveGeneration> generations;

  /// True when the on-device engine is busy, so sending here has to wait.
  final bool blocksSending;

  @override
  ConsumerState<BackgroundGenerationNotice> createState() =>
      _BackgroundGenerationNoticeState();
}

class _BackgroundGenerationNoticeState
    extends ConsumerState<BackgroundGenerationNotice> {
  bool _isExpanded = false;

  /// The list is only useful when several chats reply and nothing is blocked;
  /// a blocked send points at the one on-device chat to wait for instead.
  bool get _canExpand => widget.generations.length > 1 && !widget.blocksSending;

  @override
  void didUpdateWidget(covariant BackgroundGenerationNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canExpand) _isExpanded = false;
  }

  void _toggleExpand() {
    ref.read(appHapticsProvider).light();
    setState(() => _isExpanded = !_isExpanded);
  }

  void _collapse() {
    if (!_isExpanded) return;
    setState(() => _isExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Collapses on its own when the list stops being available.
    final canExpand = _canExpand;
    final isExpanded = _isExpanded && canExpand;

    final target = widget.blocksSending
        ? widget.generations.where((g) => g.isOnDevice).firstOrNull ??
              widget.generations.last
        : widget.generations.last;
    final conversationId = target.conversationId;
    final conversation = ref.watch(
      conv.conversationsProvider.select(
        (value) =>
            value.value?.where((c) => c.id == conversationId).firstOrNull,
      ),
    );
    final title = conversation?.title.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final message = widget.blocksSending
        ? (hasTitle
              ? l10n.background_generation_notice(title)
              : l10n.background_generation_notice_untitled)
        : canExpand
        ? l10n.background_generation_notice_multiple(widget.generations.length)
        : (hasTitle
              ? l10n.background_generation_notice_info(title)
              : l10n.background_generation_notice_info_untitled);

    final collapsedHeight = canExpand ? 34.0 : 40.0;
    final targetExpandedHeight =
        (collapsedHeight + 6.0 + (widget.generations.length * 28.0)).clamp(
          collapsedHeight,
          220.0,
        );

    return Cue.onMount(
      motion: .smooth(),
      acts: [.fadeIn(), .slideY(from: 0.15)],
      child: Cue.onToggle(
        toggled: isExpanded,
        motion: .smooth(),
        child: TweenActor<double>.value(
          from: 0,
          to: 1,
          builder: (context, value, _) {
            final t = value.clamp(0.0, 1.0);
            final visibleHeight = lerpDouble(
              collapsedHeight,
              targetExpandedHeight,
              t,
            )!;
            const overlap = 4.0;
            final containerHeight = visibleHeight + overlap;

            return SizedBox(
              height: visibleHeight,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: containerHeight,
                maxHeight: containerHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceInput
                          : AppColors.lightSurface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorder.withValues(alpha: 0.6)
                            : AppColors.lightBorder,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.22 : 0.05,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            onTap: () {
                              if (canExpand) {
                                _toggleExpand();
                              } else if (conversation != null) {
                                ref.read(appHapticsProvider).light();
                                ref
                                    .read(chatProvider.notifier)
                                    .loadConversation(conversation);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: HugeIcon(
                                      icon: HugeIcons.strokeRoundedBackground,
                                      size: 13,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontSize: 12,
                                            height: 1.25,
                                            color: theme.colorScheme.onSurface
                                                .withValues(alpha: 0.9),
                                          ),
                                    ),
                                  ),
                                  if (canExpand) ...[
                                    const SizedBox(width: 6),
                                    Transform.rotate(
                                      angle: t * math.pi,
                                      child: HugeIcon(
                                        icon: HugeIcons.strokeRoundedArrowUp01,
                                        size: 14,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (t > 0.01)
                          Expanded(
                            child: ClipRect(
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Opacity(
                                  opacity: t,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Divider(
                                        height: 4,
                                        thickness: 0.5,
                                        color: isDark
                                            ? AppColors.darkBorder.withValues(
                                                alpha: 0.6,
                                              )
                                            : AppColors.lightBorder,
                                      ),
                                      for (final gen in widget.generations)
                                        BackgroundGenerationChatItem(
                                          key: ValueKey(
                                            'gen-item-${gen.conversationId}',
                                          ),
                                          generation: gen,
                                          onTap: () {
                                            final itemConv = ref.read(
                                              conv.conversationsProvider.select(
                                                (val) => val.value
                                                    ?.where(
                                                      (c) =>
                                                          c.id ==
                                                          gen.conversationId,
                                                    )
                                                    .firstOrNull,
                                              ),
                                            );
                                            if (itemConv != null) {
                                              ref
                                                  .read(appHapticsProvider)
                                                  .light();
                                              ref
                                                  .read(chatProvider.notifier)
                                                  .loadConversation(itemConv);
                                              _collapse();
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A single listed conversation item in the expanded background generation notice.
class BackgroundGenerationChatItem extends ConsumerWidget {
  const BackgroundGenerationChatItem({
    super.key,
    required this.generation,
    required this.onTap,
  });

  final ActiveGeneration generation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final conversation = ref.watch(
      conv.conversationsProvider.select(
        (value) => value.value
            ?.where((c) => c.id == generation.conversationId)
            .firstOrNull,
      ),
    );
    final title = conversation?.title.trim();
    final displayTitle = (title != null && title.isNotEmpty)
        ? title
        : l10n.background_generation_chat_untitled;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: conversation == null ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedChatting01,
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ),
              if (generation.isOnDevice) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l10n.server_type_on_device,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              const HeartbeatDot(size: 7),
              const SizedBox(width: 6),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
