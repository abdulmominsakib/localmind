import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../models/enums.dart';

class ServerLogo extends StatelessWidget {
  final ServerType type;
  final double size;
  final double? borderRadius;
  final Color? iconColor;
  final List<List<dynamic>>? customIcon;

  const ServerLogo({
    super.key,
    required this.type,
    this.size = 24,
    this.borderRadius,
    this.iconColor,
    this.customIcon,
  });

  static List<List<dynamic>> defaultHugeIconForType(ServerType type) {
    switch (type) {
      case ServerType.lmStudio:
        return HugeIcons.strokeRoundedComputerTerminal01;
      case ServerType.openAICompatible:
        return HugeIcons.strokeRoundedApi;
      case ServerType.ollama:
        return HugeIcons.strokeRoundedRobot01;
      case ServerType.ollamaCloud:
        return HugeIcons.strokeRoundedAiCloud;
      case ServerType.openRouter:
        return HugeIcons.strokeRoundedCloud;
      case ServerType.requesty:
        return HugeIcons.strokeRoundedAiNetwork;
      case ServerType.onDevice:
        return HugeIcons.strokeRoundedSmartPhone01;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallbackColor = iconColor ?? theme.colorScheme.onSurface;

    if (customIcon != null) {
      return HugeIcon(icon: customIcon!, size: size, color: fallbackColor);
    }

    final asset = type.logoAsset;
    if (asset != null) {
      final radius = borderRadius ?? (size * 0.22);
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => HugeIcon(
            icon: defaultHugeIconForType(type),
            size: size,
            color: fallbackColor,
          ),
        ),
      );
    }

    return HugeIcon(
      icon: defaultHugeIconForType(type),
      size: size,
      color: fallbackColor,
    );
  }
}
