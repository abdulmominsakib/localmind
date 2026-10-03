import 'package:flutter/material.dart';

/// Debug-only stand-in for a widget that threw while building: a small
/// marked box in place of the widget, instead of the full crash screen.
class InlineBuildError extends StatelessWidget {
  const InlineBuildError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0x1FEF4444),
        border: Border.all(color: const Color(0xFFEF4444)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C)),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
