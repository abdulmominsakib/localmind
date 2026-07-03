import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';
import '../data/catalog_models.dart';
import '../providers/lm_studio_catalog_providers.dart';
import '../utils/memory_compatibility.dart';

class LmDownloadIndicatorButton extends ConsumerWidget {
  const LmDownloadIndicatorButton({
    super.key,
    this.compact = false,
    this.onTap,
  });

  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final jobs = ref.watch(lmDownloadManagerProvider).jobs;
    final activeCount = ref.watch(lmActiveDownloadCountProvider);
    final progress = ref.watch(lmOverallDownloadProgressProvider);

    if (jobs.isEmpty) return const SizedBox.shrink();

    final size = compact ? 28.0 : 36.0;

    return InkWell(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap ?? () => showLmDownloadsSheet(context),
      child: Padding(
        padding: EdgeInsets.all(compact ? 2 : 4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: activeCount > 0 ? progress : null,
                strokeWidth: compact ? 2 : 2.5,
                color: theme.colorScheme.primary,
                backgroundColor:
                    isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            Text(
              activeCount > 0 ? '$activeCount' : '${jobs.length}',
              style: TextStyle(
                fontSize: compact ? 9 : 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showLmDownloadsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => const _LmDownloadsSheet(),
  );
}

class _LmDownloadsSheet extends ConsumerWidget {
  const _LmDownloadsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final jobs = ref.watch(lmDownloadManagerProvider).jobs;
    final hasFinished = jobs.any((j) => !j.status.isActive);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.lm_studio_downloads_title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (hasFinished)
                  TextButton(
                    onPressed: () => ref
                        .read(lmDownloadManagerProvider.notifier)
                        .dismissFinishedJobs(),
                    child: Text(l10n.lm_studio_clear_downloads),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.lm_studio_downloads_disclaimer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkMutedText
                    : AppColors.lightMutedText,
              ),
            ),
            const SizedBox(height: 8),
            if (jobs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    l10n.lm_studio_no_downloads,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.darkMutedText
                          : AppColors.lightMutedText,
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: jobs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final job = jobs[index];
                    return _DownloadJobTile(job: job);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadJobTile extends ConsumerWidget {
  const _DownloadJobTile({required this.job});

  final LmDownloadJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    late final String statusLabel;
    late final Color statusColor;
    switch (job.status) {
      case LmDownloadStatus.downloading:
        statusLabel = l10n.lm_studio_downloading_percent(
          ((job.progressFraction ?? 0) * 100).round(),
        );
        statusColor = theme.colorScheme.primary;
      case LmDownloadStatus.paused:
        statusLabel = l10n.pause;
        statusColor = Colors.orange;
      case LmDownloadStatus.completed:
      case LmDownloadStatus.alreadyDownloaded:
        statusLabel = l10n.downloaded;
        statusColor = Colors.green;
      case LmDownloadStatus.failed:
        statusLabel = l10n.download_failed;
        statusColor = Colors.red;
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        job.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12)),
          if (job.errorMessage != null && job.status == LmDownloadStatus.failed)
            Text(
              job.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (job.status.isActive && job.totalSizeBytes != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.progressFraction,
                minHeight: 6,
                color: theme.colorScheme.primary,
                backgroundColor:
                    isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              [
                '${formatBytes(job.downloadedBytes ?? 0)} / ${formatBytes(job.totalSizeBytes!)}',
                if (formatSpeed(job.bytesPerSecond).isNotEmpty)
                  formatSpeed(job.bytesPerSecond),
              ].join(' · '),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
      trailing: job.status.isActive
          ? null
          : IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => ref
                  .read(lmDownloadManagerProvider.notifier)
                  .removeJob(job.jobId),
            ),
    );
  }
}
