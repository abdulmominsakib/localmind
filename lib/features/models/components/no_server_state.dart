import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/l10n/app_localizations.dart';

class NoServerState extends StatelessWidget {
  const NoServerState({super.key, required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedComputer,
            size: 48,
            color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.no_server_connected,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.add_server_first,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.darkMutedText
                  : AppColors.lightMutedText,
            ),
          ),
        ],
      ),
    );
  }
}
