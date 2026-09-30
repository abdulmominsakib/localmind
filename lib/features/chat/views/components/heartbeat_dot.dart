import 'package:flutter/material.dart';

/// A subtle, organic animated dot with a dual-pulse "heartbeat" rhythm.
///
/// Designed as a compact, non-intrusive activity indicator inside chat list items
/// when background generations are in progress.
class HeartbeatDot extends StatefulWidget {
  const HeartbeatDot({super.key, this.size = 7.0, this.color});

  /// Diameter of the resting dot in pixels.
  final double size;

  /// Dot color. Defaults to [ColorScheme.primary].
  final Color? color;

  @override
  State<HeartbeatDot> createState() => _HeartbeatDotState();
}

class _HeartbeatDotState extends State<HeartbeatDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    // Subtle rhythmic heartbeat pattern:
    // 0.00 - 0.16: First beat / Systole pulse (lub)
    // 0.16 - 0.30: Slight recoil
    // 0.30 - 0.44: Second beat (dub)
    // 0.44 - 0.62: Return to baseline
    // 0.62 - 1.00: Diastole resting pause
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.9,
          end: 1.25,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 16,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.25,
          end: 1.02,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.02,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.18,
          end: 0.9,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0.9), weight: 38),
    ]).animate(_controller);

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.45, end: 1.0),
        weight: 16,
      ),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.7), weight: 14),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.7, end: 0.95),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.95, end: 0.45),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0.45), weight: 38),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.color ?? Theme.of(context).colorScheme.primary;
    final containerDim = widget.size * 1.8;

    return SizedBox(
      width: containerDim,
      height: containerDim,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final scale = _scaleAnimation.value;
            final opacity = _opacityAnimation.value;

            return Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.35 * opacity),
                        blurRadius: 3,
                        spreadRadius: 0.5,
                      ),
                    ],
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
