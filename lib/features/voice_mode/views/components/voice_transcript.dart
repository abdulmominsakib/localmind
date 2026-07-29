import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tts/providers/tts_providers.dart';
import '../../providers/voice_mode_provider.dart';
import '../../voice_mode_palette.dart';

/// Displays the current voice phase badge and auto-scrolling response text
/// container. Designed to sit below the waveform visualizer.
class VoiceTranscript extends ConsumerStatefulWidget {
  final VoiceModePhase phase;
  final String transcript;
  final String response;
  final String? error;

  const VoiceTranscript({
    super.key,
    required this.phase,
    required this.transcript,
    required this.response,
    this.error,
  });

  @override
  ConsumerState<VoiceTranscript> createState() => _VoiceTranscriptState();
}

class _VoiceTranscriptState extends ConsumerState<VoiceTranscript> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(VoiceTranscript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.response != oldWidget.response &&
        widget.phase == VoiceModePhase.processing) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTtsInitializing = ref.watch(
      ttsProvider.select((s) => s.isInitializing),
    );

    final (label, badgeColor, isSynthesizing) =
        _resolveStatusBadge(isTtsInitializing);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey(label),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: badgeColor.withValues(alpha: isDark ? 0.32 : 0.28),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PulsingDot(
                  color: badgeColor,
                  active: widget.phase != VoiceModePhase.idle,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: badgeColor,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: _buildTextContent(context, isDark, isSynthesizing),
        ),
      ],
    );
  }

  (String, Color, bool) _resolveStatusBadge(bool isTtsInitializing) {
    if (widget.phase == VoiceModePhase.speaking && isTtsInitializing) {
      return ('SYNTHESIZING VOICE', const Color(0xFFF59E0B), true);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (widget.phase) {
      case VoiceModePhase.listening:
        return ('LISTENING',
            VoiceModePalette.accentFor(VoiceModePhase.listening, isDark: isDark),
            false);
      case VoiceModePhase.processing:
        final hasResponse = widget.response.trim().isNotEmpty;
        if (isTtsInitializing) {
          return ('SYNTHESIZING VOICE', const Color(0xFFF59E0B), true);
        }
        return (
          hasResponse ? 'RESPONDING' : 'THINKING',
          VoiceModePalette.accentFor(VoiceModePhase.processing, isDark: isDark),
          false,
        );
      case VoiceModePhase.speaking:
        return ('SPEAKING',
            VoiceModePalette.accentFor(VoiceModePhase.speaking, isDark: isDark),
            false);
      case VoiceModePhase.idle:
        return ('READY',
            VoiceModePalette.accentFor(VoiceModePhase.idle, isDark: isDark),
            false);
      case VoiceModePhase.error:
        final errorText = widget.error ?? '';
        final isSpeechError = errorText.toLowerCase().contains('speech');
        return (
          isSpeechError ? 'NO SPEECH DETECTED' : 'ERROR',
          VoiceModePalette.accentFor(VoiceModePhase.error, isDark: isDark),
          false,
        );
    }
  }

  Widget _buildTextContent(
    BuildContext context,
    bool isDark,
    bool isSynthesizing,
  ) {
    switch (widget.phase) {
      case VoiceModePhase.processing:
        final hasResponse = widget.response.trim().isNotEmpty;
        if (!hasResponse) {
          return Text(
            'Thinking...',
            key: const ValueKey('thinking'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.6)
                  : Colors.black.withValues(alpha: 0.5),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          );
        }

        return Container(
          key: const ValueKey('responding-container'),
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 130),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Text(
              widget.response,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.75)
                    : Colors.black.withValues(alpha: 0.7),
                height: 1.45,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        );

      case VoiceModePhase.listening:
        final displayText =
            widget.transcript.isEmpty ? 'Listening...' : widget.transcript;
        return Text(
          displayText,
          key: const ValueKey('listening'),
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w500,
            color: isDark
                ? Colors.white.withValues(alpha: 0.9)
                : Colors.black.withValues(alpha: 0.85),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );

      case VoiceModePhase.speaking:
        return _buildSpeakingContent(isDark);

      case VoiceModePhase.idle:
        return Text(
          'Tap to start speaking',
          key: const ValueKey('idle'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: isDark
                ? Colors.white.withValues(alpha: 0.5)
                : Colors.black.withValues(alpha: 0.4),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );

      case VoiceModePhase.error:
        final errorText = (widget.error != null && widget.error!.isNotEmpty)
            ? widget.error!
            : 'No speech recognized. Tap to try again.';
        return Text(
          errorText,
          key: ValueKey('error-${errorText.hashCode}'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: const Color(0xFFEF4444).withValues(alpha: 0.95),
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        );
    }
  }

  /// Renders the assistant's response with the currently-spoken word
  /// highlighted. Estimate per-chunk timing proportionally from chunk
  /// character counts (TTS exposes real per-chunk durations internally,
  /// but not via [TtsState], so character-ratio is a good approximation).
  Widget _buildSpeakingContent(bool isDark) {
    final response = widget.response;
    if (response.isEmpty) {
      return Text(
        '...',
        key: const ValueKey('speaking'),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: isDark
              ? Colors.white.withValues(alpha: 0.7)
              : Colors.black.withValues(alpha: 0.7),
          height: 1.45,
        ),
        textAlign: TextAlign.center,
      );
    }

    final tts = ref.watch(ttsProvider);
    final accent = VoiceModePalette.accentFor(
      VoiceModePhase.speaking,
      isDark: isDark,
    );
    final mutedColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.black.withValues(alpha: 0.7);

    final highlightedWordIndex = _activeWordIndex(response, tts);

    final base = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: mutedColor,
      height: 1.45,
    );

    final spans = _buildWordSpans(
      response: response,
      activeIndex: highlightedWordIndex,
      base: base,
      active: base.copyWith(
        color: accent,
        fontWeight: FontWeight.w700,
      ),
    );

    return RichText(
      key: const ValueKey('speaking'),
      textAlign: TextAlign.center,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: base, children: spans),
    );
  }

  /// Returns the index of the word currently being spoken, or -1 if no
  /// word is currently active (e.g. between sentences, before TTS has
  /// populated `chunks`).
  int _activeWordIndex(String response, TtsState tts) {
    if (!tts.isSpeaking ||
        tts.chunks.isEmpty ||
        tts.currentChunkIndex < 0 ||
        tts.currentChunkIndex >= tts.chunks.length) {
      return -1;
    }

    final chunkStartChars = _chunkCharStarts(response, tts.chunks);
    final charIdx = _globalCharIndex(
      chunkIndex: tts.currentChunkIndex,
      chunkStartChars: chunkStartChars,
      chunks: tts.chunks,
      duration: tts.duration,
      position: tts.position,
    );
    if (charIdx < 0) return -1;

    return _wordIndexAtChar(response, charIdx);
  }

  /// Maps each TTS chunk to a starting character offset within the
  /// original response string so we can locate the spoken character.
  /// Falls back to char-proportional split when the TTS chunks don't
  /// map cleanly (e.g. markdown was stripped, text was rephrased).
  List<int> _chunkCharStarts(String response, List<String> chunks) {
    final starts = <int>[];
    int cursor = 0;
    for (final chunk in chunks) {
      final idx = response.indexOf(chunk, cursor);
      starts.add(idx >= 0 ? idx : cursor);
      cursor = (idx >= 0 ? idx : cursor) + chunk.length;
    }
    return starts;
  }

  /// Approximates the global character index that's currently being
  /// spoken, by combining the chunk-of-the-moment's start offset with
  /// the chunk's share of the total `duration` and the live `position`.
  int _globalCharIndex({
    required int chunkIndex,
    required List<int> chunkStartChars,
    required List<String> chunks,
    required Duration duration,
    required Duration position,
  }) {
    if (chunks.isEmpty) return -1;

    final totalChars = chunks.fold<int>(0, (sum, c) => sum + c.length);
    if (totalChars == 0) return -1;

    final prevChunkChars = <int>[0];
    for (var i = 0; i < chunks.length; i++) {
      prevChunkChars.add(prevChunkChars.last + chunks[i].length);
    }

    final safeDuration = duration.inMilliseconds > 0
        ? duration.inMilliseconds
        : totalChars * 60;
    final safePosition = position.inMilliseconds.clamp(0, safeDuration);
    final globalCharIdx =
        ((safePosition / safeDuration) * totalChars).round().clamp(0, totalChars);

    // Within which chunk does that character fall?
    int targetChunk = chunks.length - 1;
    for (var i = 0; i < chunks.length; i++) {
      if (globalCharIdx < prevChunkChars[i + 1]) {
        targetChunk = i;
        break;
      }
    }

    final chunkStart = chunkStartChars[targetChunk];
    final charInChunk = (globalCharIdx - prevChunkChars[targetChunk])
        .clamp(0, chunks[targetChunk].length);
    return chunkStart + charInChunk;
  }

  /// Builds the highlighted word index for a text by walking whitespace-
  /// separated tokens and returning the index of the one containing
  /// [charIdx].
  int _wordIndexAtChar(String text, int charIdx) {
    if (charIdx < 0 || charIdx >= text.length) return -1;
    var inWord = false;
    var wordIndex = -1;
    for (var i = 0; i < text.length; i++) {
      final isWordChar = _isWordChar(text.codeUnitAt(i));
      if (isWordChar && !inWord) {
        wordIndex++;
        inWord = true;
      } else if (!isWordChar && inWord) {
        inWord = false;
      }
      if (i == charIdx && inWord) {
        return wordIndex;
      }
    }
    // If charIdx is the last char and is inside a word.
    return inWord ? wordIndex : -1;
  }

  bool _isWordChar(int codeUnit) {
    // Letters, digits, and apostrophes (don't break "don't" into two).
    final isAlnum = (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
        (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
        (codeUnit >= 0x61 && codeUnit <= 0x7A) || // a-z
        (codeUnit >= 0xC0 && codeUnit <= 0x024F); // Latin extended
    final isApostrophe =
        codeUnit == 0x27 || codeUnit == 0x2019; // ' '
    return isAlnum || isApostrophe;
  }

  List<InlineSpan> _buildWordSpans({
    required String response,
    required int activeIndex,
    required TextStyle base,
    required TextStyle active,
  }) {
    final spans = <InlineSpan>[];
    var wordIndex = -1;
    var buffer = StringBuffer();
    var inWord = false;

    void flushBuffer({required bool trailingWord}) {
      if (buffer.isEmpty) return;
      final text = buffer.toString();
      spans.add(TextSpan(
        text: text,
        style: trailingWord && wordIndex == activeIndex ? active : base,
      ));
      buffer = StringBuffer();
    }

    for (var i = 0; i < response.length; i++) {
      final code = response.codeUnitAt(i);
      final isWord = _isWordChar(code);
      if (isWord && !inWord) {
        // Flush preceding whitespace.
        flushBuffer(trailingWord: false);
        wordIndex++;
        inWord = true;
      } else if (!isWord && inWord) {
        // End of word — flush with active/inactive style.
        flushBuffer(trailingWord: true);
        inWord = false;
      }
      buffer.write(response[i]);
    }
    if (inWord) {
      flushBuffer(trailingWord: true);
    } else {
      flushBuffer(trailingWord: false);
    }
    return spans;
  }
}

/// Tiny pulsing dot used inside the status badge.
class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool active;

  const _PulsingDot({required this.color, required this.active});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.active ? _controller.value : 0.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.5 + 0.4 * t),
                      blurRadius: 5 + 5 * t,
                      spreadRadius: 0.5 + 1.5 * t,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}