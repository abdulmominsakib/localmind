import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class ModelLoadingOverlay extends StatelessWidget {
  const ModelLoadingOverlay({
    required this.modelName,
    this.serverName,
    this.statusMessage = 'Loading model into memory...',
    this.onCancel,
    super.key,
  });

  final String modelName;
  final String? serverName;
  final String statusMessage;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: onCancel != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && onCancel != null) {
          onCancel!();
        }
      },
      child: Material(
        color: Colors.black.withValues(alpha: 0.65),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.card.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.border.withValues(alpha: 0.6),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated spinner / pulse
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: LoadingAnimationWidget.threeArchedCircle(
                        color: colorScheme.primary,
                        size: 36,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    'Preparing Model',
                    style: theme.textTheme.large.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Model badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.border.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedCpu,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            modelName,
                            style: theme.textTheme.small.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.foreground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (serverName != null && serverName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      serverName!,
                      style: theme.textTheme.muted.copyWith(fontSize: 12),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Dynamic status message
                  Text(
                    statusMessage,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.muted.copyWith(fontSize: 13),
                  ),

                  if (onCancel != null) ...[
                    const SizedBox(height: 20),
                    ShadButton.outline(
                      size: ShadButtonSize.sm,
                      onPressed: onCancel,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                            size: 14,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 6),
                          Text('Cancel'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
