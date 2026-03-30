import 'package:flutter/material.dart';
import '../../../../core/models/enums.dart';

class ConnectionStatusIndicator extends StatefulWidget {
  final ConnectionStatus status;
  final double size;

  const ConnectionStatusIndicator({
    super.key,
    required this.status,
    this.size = 12,
  });

  @override
  State<ConnectionStatusIndicator> createState() =>
      _ConnectionStatusIndicatorState();
}

class _ConnectionStatusIndicatorState extends State<ConnectionStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.status == ConnectionStatus.connected) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(ConnectionStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status == ConnectionStatus.connected) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color {
    switch (widget.status) {
      case ConnectionStatus.connected:
        return const Color(0xFF22C55E);
      case ConnectionStatus.error:
        return const Color(0xFFEF4444);
      case ConnectionStatus.checking:
        return const Color(0xFFF59E0B);
      case ConnectionStatus.disconnected:
        return const Color(0xFF71717A);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == ConnectionStatus.checking) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(strokeWidth: 2, color: _color),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _color.withValues(
              alpha: widget.status == ConnectionStatus.connected
                  ? _animation.value
                  : 1.0,
            ),
          ),
        );
      },
    );
  }
}
