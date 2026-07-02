import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart' as tts;
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';

class TtsPlayerBar extends ConsumerWidget {
  final EdgeInsetsGeometry margin;

  const TtsPlayerBar({
    super.key,
    this.margin = const EdgeInsets.only(left: 16, right: 16, bottom: 8),
  });

  String? _truncateContent(String? content) {
    if (content == null || content.isEmpty) return null;
    if (content.length <= 50) return content;
    return '${content.substring(0, 47)}...';
  }

  String _formatDuration(Duration d, {bool unknown = false}) {
    if (unknown || d <= Duration.zero) return '--:--';
    if (d.inHours > 0) {
      final h = d.inHours.toString();
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      final s = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _scrollToPlayingMessage(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ttsState = ref.read(tts.ttsProvider);
    final messageId = ttsState.playingMessageId;
    if (messageId == null) return;

    ref.read(scrollToMessageIdProvider.notifier).scrollTo(messageId);

    final conversationId = ttsState.playingConversationId;
    if (conversationId != null) {
      final active = ref.read(activeConversationProvider);
      if (active?.id != conversationId) {
        final conversations = ref.read(conversationsProvider).value ?? [];
        Conversation? target;
        for (final conv in conversations) {
          if (conv.id == conversationId) {
            target = conv;
            break;
          }
        }
        if (target != null) {
          await ref.read(chatProvider.notifier).loadConversation(target);
        }
      }
    }

    if (context.mounted) {
      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
        Navigator.pop(context);
      }
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final ttsState = ref.watch(tts.ttsProvider);
    final notifier = ref.read(tts.ttsProvider.notifier);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    ref.listen<tts.TtsState>(tts.ttsProvider, (prev, next) {
      if (next.error != null && prev?.error != next.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    final isActivePlayback =
        ttsState.isSpeaking ||
        ttsState.isInitializing ||
        (ttsState.isPaused && ttsState.playingContent != null);
    if (!isActivePlayback || ttsState.isPreview) {
      return const SizedBox.shrink();
    }

    final preview = _truncateContent(ttsState.playingContent);
    final canJumpToMessage = ttsState.playingMessageId != null;
    final skipSeconds = ref.watch(settingsProvider).ttsSkipSeconds;
    final settingsEngine =
        ref.watch(settingsProvider.select((s) => s.ttsEngine));
    final isSystemTts = ttsState.activeEngine == EngineId.system ||
        settingsEngine == EngineId.system ||
        (ttsState.activeEngine == null && settingsEngine == EngineId.system);
    final showSeekControls = !isSystemTts;
    final hasTimeline = showSeekControls && ttsState.duration > Duration.zero;
    final progress = showSeekControls
        ? (ttsState.duration > Duration.zero
            ? (ttsState.position.inMilliseconds /
                    ttsState.duration.inMilliseconds)
                .clamp(0.0, 1.0)
            : 0.0)
        : null;
    final speedLabel =
        '${ttsState.playbackSpeed.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}x';

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Container(
        width: double.infinity,
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => notifier.togglePauseResume(),
                  child: Tooltip(
                    message: ttsState.isPaused ? l10n.resume : l10n.pause,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        ttsState.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canJumpToMessage
                          ? () => _scrollToPlayingMessage(context, ref)
                          : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              preview ??
                                  (ttsState.isInitializing
                                      ? l10n.loading
                                      : 'Playing'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (ttsState.isInitializing)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  l10n.initializing,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!ttsState.isInitializing) ...[
                  _WaveformIndicator(isPlaying: !ttsState.isPaused),
                  const SizedBox(width: 12),
                ],
                if (!ttsState.isInitializing)
                  TextButton(
                    onPressed: notifier.cyclePlaybackSpeed,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      speedLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                if (!ttsState.isInitializing &&
                    ttsState.activeEngine != EngineId.system)
                  IconButton(
                    icon: const Icon(Icons.download_outlined, size: 20),
                    tooltip: l10n.download_tts_audio,
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      final ok = await notifier.downloadCurrentAudio();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? l10n.tts_download_success
                                : l10n.tts_download_no_audio,
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => notifier.stop(),
                  child: Tooltip(
                    message: l10n.stop,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.stop_rounded,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (showSeekControls) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _TtsSkipButton(
                    icon: Icons.fast_rewind_rounded,
                    tooltip: '-${skipSeconds}s',
                    isLoading: ttsState.isSeekPending && !ttsState.canSeek,
                    onPressed: notifier.skipBackward,
                  ),
                  Expanded(
                    child: _TtsSeekSlider(
                      progress: progress ?? 0,
                      position: ttsState.position,
                      duration: ttsState.duration,
                      enabled: hasTimeline && !ttsState.isSeekPending,
                      onSeek: notifier.seekTo,
                      formatDuration: _formatDuration,
                    ),
                  ),
                  _TtsSkipButton(
                    icon: Icons.fast_forward_rounded,
                    tooltip: '+${skipSeconds}s',
                    isLoading: ttsState.isSeekPending && !ttsState.canSeek,
                    onPressed: notifier.skipForward,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TtsSkipButton extends StatelessWidget {
  const _TtsSkipButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isLoading = false,
  });

  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 22),
    );
  }
}

class _TtsSeekSlider extends StatefulWidget {
  const _TtsSeekSlider({
    required this.progress,
    required this.position,
    required this.duration,
    required this.enabled,
    required this.onSeek,
    required this.formatDuration,
  });

  final double progress;
  final Duration position;
  final Duration duration;
  final bool enabled;
  final Future<void> Function(Duration) onSeek;
  final String Function(Duration) formatDuration;

  @override
  State<_TtsSeekSlider> createState() => _TtsSeekSliderState();
}

class _TtsSeekSliderState extends State<_TtsSeekSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayProgress = _dragValue ?? widget.progress;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: displayProgress.clamp(0.0, 1.0),
            onChanged: widget.enabled
                ? (v) => setState(() => _dragValue = v)
                : null,
            onChangeEnd: widget.enabled
                ? (v) async {
                    setState(() => _dragValue = null);
                    await widget.onSeek(
                      Duration(
                        milliseconds:
                            (v * widget.duration.inMilliseconds).round(),
                      ),
                    );
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.formatDuration(
                  _dragValue != null
                      ? Duration(
                          milliseconds: (_dragValue! *
                                  widget.duration.inMilliseconds)
                              .round(),
                        )
                      : widget.position,
                ),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                widget.formatDuration(widget.duration),
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformIndicator extends StatefulWidget {
  final bool isPlaying;

  const _WaveformIndicator({required this.isPlaying});

  @override
  State<_WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<_WaveformIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _WaveformIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildBar(double height, Color color) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final barColor = theme.colorScheme.primary;

    return Container(
      height: 16,
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;

          final h1 = widget.isPlaying
              ? 4.0 + 12.0 * (0.5 + 0.5 * math.sin(t * 2 * math.pi))
              : 4.0;
          final h2 = widget.isPlaying
              ? 4.0 + 12.0 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + math.pi / 3))
              : 6.0;
          final h3 = widget.isPlaying
              ? 4.0 + 12.0 * (0.5 + 0.5 * math.sin(t * 2 * math.pi + 2 * math.pi / 3))
              : 4.0;

          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(h1, barColor),
              const SizedBox(width: 2),
              _buildBar(h2, barColor),
              const SizedBox(width: 2),
              _buildBar(h3, barColor),
            ],
          );
        },
      ),
    );
  }
}
