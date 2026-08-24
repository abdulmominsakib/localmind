import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/core/device/device_memory_service.dart';
import 'package:localmind/core/providers/device_info_providers.dart';
import 'package:localmind/l10n/app_localizations.dart';

class MemoryStatsPanel extends ConsumerWidget {
  const MemoryStatsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final memoryAsync = ref.watch(deviceMemoryProvider);

    return memoryAsync.when(
      data: (info) {
        if (info.totalMemoryMb == 0) return const SizedBox.shrink();
        return _MemoryPanelContent(info: info, l10n: l10n, ref: ref);
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _MemoryPanelContent extends StatelessWidget {
  const _MemoryPanelContent({
    required this.info,
    required this.l10n,
    required this.ref,
  });

  final DeviceMemoryInfo info;
  final AppLocalizations l10n;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usedMb = info.totalMemoryMb - info.availableMemoryMb;
    final usagePercent = usedMb / info.totalMemoryMb;

    Color statusColor = Colors.green;
    String statusText = l10n.memory_healthy;
    if (info.availableMemoryMb < 1024) {
      statusColor = Colors.red;
      statusText = l10n.memory_critical;
    } else if (info.availableMemoryMb < 2048) {
      statusColor = Colors.orange;
      statusText = l10n.memory_low;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerHighest,
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 20,
              top: 16,
              end: 12,
              bottom: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedCpu,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.device_memory,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => ref.invalidate(deviceMemoryProvider),
                  child: const HugeIcon(
                    icon: HugeIcons.strokeRoundedRefresh,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.ram_usage,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        statusText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      Container(
                        height: 10,
                        width: double.infinity,
                        color: theme.colorScheme.surfaceContainerLowest,
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        height: 10,
                        width: MediaQuery.of(context).size.width * usagePercent,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              statusColor,
                              statusColor.withValues(alpha: 0.7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.ram_used((usagePercent * 100).toStringAsFixed(0)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_formatMb(usedMb)} / ${info.totalMemoryFormatted}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _MemoryStat(
                    label: l10n.available_ram,
                    value: info.availableMemoryFormatted,
                    icon: HugeIcons.strokeRoundedDashboardSpeed01,
                    color: statusColor,
                    isPrimary: true,
                  ),
                ),
                Container(
                  height: 30,
                  width: 1,
                  color: theme.colorScheme.outline.withValues(alpha: 0.1),
                ),
                Expanded(
                  child: _MemoryStat(
                    label: l10n.total_capacity,
                    value: info.totalMemoryFormatted,
                    icon: HugeIcons.strokeRoundedDatabase,
                    alignment: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryStat extends StatelessWidget {
  final String label;
  final String value;
  final List<List<dynamic>> icon;
  final Color? color;
  final CrossAxisAlignment alignment;
  final bool isPrimary;

  const _MemoryStat({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.alignment = CrossAxisAlignment.start,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor =
        color ?? theme.colorScheme.onSurface.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alignment == CrossAxisAlignment.start) ...[
              HugeIcon(icon: icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
            if (alignment == CrossAxisAlignment.end) ...[
              const SizedBox(width: 6),
              HugeIcon(icon: icon, size: 14, color: iconColor),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style:
              (isPrimary
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: isPrimary ? -0.5 : null,
                  ),
        ),
      ],
    );
  }
}

String _formatMb(int mb) {
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
  return '$mb MB';
}
