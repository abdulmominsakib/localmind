import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/utils/ascii_logo.dart';

/// A provider's logo drawn in ASCII, animated: a scrambled reveal, then the
/// logo's own loop (see [asciiLogoFrame]) for [playDuration], after which it
/// settles on the still logo. Tapping it plays it again.
///
/// It holds still while [paused] (the keyboard is up, say) and whenever the
/// platform asks for reduced motion.
class AsciiLogoView extends StatefulWidget {
  const AsciiLogoView({
    super.key,
    required this.logo,
    required this.semanticLabel,
    this.paused = false,
  });

  final AsciiLogo logo;
  final String semanticLabel;
  final bool paused;

  /// How long one play lasts before the logo settles.
  static const playDuration = Duration(seconds: 12);

  @override
  State<AsciiLogoView> createState() => _AsciiLogoViewState();
}

class _AsciiLogoViewState extends State<AsciiLogoView>
    with SingleTickerProviderStateMixin {
  static final _playTicks =
      AsciiLogoView.playDuration.inMilliseconds ~/
      asciiLogoTickInterval.inMilliseconds;

  late final Ticker _ticker = createTicker(_onTick);
  int _tick = 0;

  /// Showing the still logo: done playing, paused, or reduced motion.
  bool _settled = true;
  bool _reduceMotion = false;
  bool _played = false;

  bool get _canPlay => !_reduceMotion && !widget.paused;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_canPlay) {
      _settle();
    } else if (!_played) {
      _play();
    }
  }

  @override
  void didUpdateWidget(AsciiLogoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canPlay) {
      _settle();
    } else if (oldWidget.logo != widget.logo) {
      _play();
    }
  }

  void _play() {
    _played = true;
    _settled = false;
    _tick = 0;
    _ticker
      ..stop()
      ..start();
  }

  void _settle() {
    _settled = true;
    _ticker.stop();
  }

  void _replay() {
    if (_canPlay) setState(_play);
  }

  void _onTick(Duration elapsed) {
    final tick = elapsed.inMilliseconds ~/ asciiLogoTickInterval.inMilliseconds;
    if (tick >= _playTicks) {
      setState(_settle);
    } else if (tick != _tick) {
      setState(() => _tick = tick);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (base, highlight) = _colors(widget.logo, isDark);
    final frame = asciiLogoFrame(widget.logo, _settled ? null : _tick);
    const style = TextStyle(
      fontFamily: 'Menlo',
      fontFamilyFallback: ['Courier', 'monospace'],
      fontSize: 6,
      height: 1,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );

    return Semantics(
      image: true,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: _replay,
          behavior: HitTestBehavior.opaque,
          // Each tick repaints only the logo, not the screen around it.
          child: RepaintBoundary(
            child: SizedBox(
              width: 252,
              height: 250,
              // Monospace advance widths differ by platform; scale the grid to
              // the box rather than letting it wrap or overflow.
              child: FittedBox(
                fit: .contain,
                child: Stack(
                  children: [
                    Text(
                      frame.base.join('\n'),
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: style.copyWith(color: base),
                    ),
                    Text(
                      frame.highlight.join('\n'),
                      softWrap: false,
                      textScaler: TextScaler.noScaling,
                      style: style.copyWith(color: highlight),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The logo's own color and its accent, readable on either theme.
  static (Color, Color) _colors(AsciiLogo logo, bool isDark) {
    final primary = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;
    return switch (logo) {
      AsciiLogo.localMind => (
        primary,
        isDark ? const Color(0xFF9BE5B5) : const Color(0xFF15803D),
      ),
      AsciiLogo.lmStudio => (
        isDark ? const Color(0xFFA99BFF) : const Color(0xFF5B4BD8),
        primary,
      ),
      AsciiLogo.ollama => (primary, primary),
      AsciiLogo.server => (
        isDark ? const Color(0xFF9A9A9A) : AppColors.lightMutedText,
        isDark ? AppColors.success : const Color(0xFF16A34A),
      ),
      AsciiLogo.openRouter => (
        isDark ? const Color(0xFFC4C4C4) : const Color(0xFF52525B),
        isDark ? Colors.white : Colors.black,
      ),
      AsciiLogo.requesty => (
        isDark ? const Color(0xFF4F8DF7) : const Color(0xFF1F6FE5),
        primary,
      ),
    };
  }
}
