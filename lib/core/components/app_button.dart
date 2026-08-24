import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'app_sizes.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.isFullWidth = false,
    this.size = AppButtonSize.medium,
  });

  final String label;
  final VoidCallback? onPressed;
  final List<List<dynamic>>? icon;
  final AppButtonVariant variant;
  final bool isLoading;
  final bool isFullWidth;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkAccent : AppColors.lightAccent;
    final height = switch (size) {
      AppButtonSize.small => 32.0,
      AppButtonSize.medium => 44.0,
      AppButtonSize.large => 52.0,
    };

    final child = isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: variant == AppButtonVariant.primary
                  ? (isDark ? AppColors.darkBackground : Colors.white)
                  : accent,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                HugeIcon(icon: icon!, size: 18),
                const SizedBox(width: AppSizes.sm),
              ],
              Text(label),
            ],
          );

    return switch (variant) {
      AppButtonVariant.primary => SizedBox(
        height: height,
        width: isFullWidth ? double.infinity : null,
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      ),
      AppButtonVariant.outline => SizedBox(
        height: height,
        width: isFullWidth ? double.infinity : null,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      ),
      AppButtonVariant.ghost => SizedBox(
        height: height,
        width: isFullWidth ? double.infinity : null,
        child: TextButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
      ),
      AppButtonVariant.destructive => SizedBox(
        height: height,
        width: isFullWidth ? double.infinity : null,
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.red),
            foregroundColor: Colors.red,
          ),
          child: child,
        ),
      ),
    };
  }
}

enum AppButtonVariant { primary, outline, ghost, destructive }

enum AppButtonSize { small, medium, large }

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? AppSizes.radiusLg;

    final container = Container(
      padding: padding ?? const EdgeInsets.all(AppSizes.lg),
      margin: margin ?? const EdgeInsets.only(bottom: AppSizes.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: container);
    }

    return container;
  }
}

class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.size = 24, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkAccent
            : AppColors.lightAccent,
      ),
    );
  }
}
