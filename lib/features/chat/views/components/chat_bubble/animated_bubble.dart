import 'package:cue/cue.dart';
import 'package:flutter/material.dart';

class AnimatedBubble extends StatelessWidget {
  const AnimatedBubble({super.key, required this.child, required this.alignment});

  final Widget child;
  final AlignmentDirectional alignment;

  @override
  Widget build(BuildContext context) {
    final resolvedAlignment = alignment.resolve(Directionality.of(context));
    final isUserRight = resolvedAlignment == Alignment.centerRight;
    final isAssistantLeft = resolvedAlignment == Alignment.centerLeft;

    final Offset translateOffset = isUserRight
        ? const Offset(12, 0)
        : isAssistantLeft
            ? const Offset(-12, 0)
            : const Offset(0, 8);

    return Cue.onMount(
      motion: .smooth(),
      acts: [
        .fadeIn(),
        .translate(from: translateOffset),
        .scale(from: 0.98),
      ],
      child: child,
    );
  }
}