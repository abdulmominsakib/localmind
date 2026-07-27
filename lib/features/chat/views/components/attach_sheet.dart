import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// Shows the modern, grid-style attachment picker bottom sheet.
///
/// Returns a result the caller can act on, or `null` if the user dismissed
/// the sheet. Designed to mirror the clean action-sheet pattern used in
/// iOS / Android system pickers — large rounded card, three short tile
/// actions, drag handle, and tappable outside-to-dismiss.
enum AttachAction { documents, images, savedMessage }

Future<AttachAction?> showAttachSheet(BuildContext context) {
  return showModalBottomSheet<AttachAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    isScrollControlled: true,
    showDragHandle: false,
    useSafeArea: true,
    builder: (_) => const _AttachSheet(),
  );
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final tileBg = isDark
        ? AppColors.darkSurfaceInput
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final fg = isDark ? AppColors.darkPrimaryText : AppColors.lightPrimaryText;
    final mutedFg =
        isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: mutedFg.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.add_to_chat,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: fg,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.choose_attachment_subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: mutedFg,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        color: mutedFg,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _AttachTile(
                        icon: HugeIcons.strokeRoundedImage01,
                        label: l10n.attach_shortcut_images,
                        tileColor: tileBg,
                        foreground: fg,
                        accent: const Color(0xFF7C5CFF),
                        onTap: () =>
                            Navigator.of(context).pop(AttachAction.images),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AttachTile(
                        icon: HugeIcons.strokeRoundedFile01,
                        label: l10n.attach_shortcut_documents,
                        tileColor: tileBg,
                        foreground: fg,
                        accent: const Color(0xFFFF8A4C),
                        onTap: () =>
                            Navigator.of(context).pop(AttachAction.documents),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AttachTile(
                        icon: HugeIcons.strokeRoundedBookmark01,
                        label: l10n.attach_shortcut_saved,
                        tileColor: tileBg,
                        foreground: fg,
                        accent: const Color(0xFF22C55E),
                        onTap: () => Navigator.of(context)
                            .pop(AttachAction.savedMessage),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.tileColor,
    required this.foreground,
    required this.accent,
    required this.onTap,
  });

  final dynamic icon;
  final String label;
  final Color tileColor;
  final Color foreground;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: HugeIcon(
                    icon: icon,
                    color: accent,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}