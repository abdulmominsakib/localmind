import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../services/crash_report_service.dart';

/// User-facing fallback shown when a crash is captured. Used both as
/// `ErrorWidget.builder` and from `main.dart`'s `ValueListenableBuilder`
/// that wraps `BootstrapHost`.
class CrashErrorWidget extends StatelessWidget {
  const CrashErrorWidget({super.key, required this.crash});

  final CrashReport crash;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final stackLines = crash.stackTrace.toString().split('\n');
    final previewLines = stackLines.take(40).join('\n');

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        size: 36,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n?.crash_report_title ?? 'Something went wrong',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'v${crash.appVersion} (${crash.buildNumber}) · ${crash.platform} ${crash.deviceModel}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            HugeIcon(
                              icon: HugeIcons.strokeRoundedBug01,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                crash.errorType,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          crash.shortError,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Theme(
                    data: theme.copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(
                        l10n?.crash_report_stack_trace ?? 'Stack trace',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        l10n?.crash_report_tap_to_expand ?? 'Tap to expand',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: SelectableText(
                            previewLines.isEmpty
                                ? (l10n?.crash_report_empty_stack ?? '<empty>')
                                : previewLines,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openGitHub(context),
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowUpRight01,
                      size: 18,
                    ),
                    label: Text(
                      l10n?.crash_report_button ?? 'Report this crash',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _copyReport(context),
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedCopy01,
                      size: 18,
                    ),
                    label: Text(l10n?.copy ?? 'Copy report'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _tryAgain(context),
                    child: Text(l10n?.crash_try_again ?? 'Try again'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n?.crash_report_disclaimer ??
                        'Reporting opens GitHub with diagnostics prefilled. '
                            'You stay in control — nothing is submitted automatically. '
                            'Please review and remove any sensitive content before submitting.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openGitHub(BuildContext context) async {
    final uri = CrashReportService.instance.buildGitHubIssueUrl(crash);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n?.could_not_open_github ??
                  'Could not open GitHub. Please copy the URL manually.',
            ),
          ),
        );
      }
    } catch (e) {
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n?.failed_to_open_url(e.toString()) ??
                  'Failed to open URL: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _copyReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: crash.markdownBody));
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n?.crash_report_copied ?? 'Copied to clipboard'),
          ),
        );
      }
    } catch (e) {
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n?.failed_to_copy(e.toString()) ?? 'Failed to copy: $e',
            ),
          ),
        );
      }
    }
  }

  void _tryAgain(BuildContext context) {
    CrashReportService.instance.clearCrash();
  }
}
