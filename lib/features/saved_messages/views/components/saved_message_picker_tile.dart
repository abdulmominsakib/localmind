import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../data/models/saved_message.dart';

class SavedMessagePickerTile extends StatelessWidget {
  const SavedMessagePickerTile({
    super.key,
    required this.saved,
    required this.onTap,
  });

  final SavedMessage saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final role = MessageRole.values[saved.roleIndex];
    final isUser = role == MessageRole.user;
    final isFromTempChat = saved.conversationId.isEmpty;
    final mutedColor = isDark
        ? AppColors.darkMutedText
        : AppColors.lightMutedText;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HugeIcon(
                icon: isUser
                    ? HugeIcons.strokeRoundedUser
                    : HugeIcons.strokeRoundedSparkles,
                size: 20,
                color: mutedColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isFromTempChat)
                      Text(
                        l10n.temporary_chat,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          fontStyle: FontStyle.italic,
                          color: mutedColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (saved.conversationTitle.isNotEmpty)
                      Text(
                        saved.conversationTitle,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkPrimaryText
                              : AppColors.lightPrimaryText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (isFromTempChat || saved.conversationTitle.isNotEmpty)
                      const SizedBox(height: 2),
                    Text(
                      saved.content,
                      style: TextStyle(fontSize: 13, color: mutedColor),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
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
