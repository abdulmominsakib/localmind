import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:localmind/core/theme/colors.dart';

import '../../../l10n/app_localizations.dart';

class GitHubRepoCard extends StatelessWidget {
  const GitHubRepoCard({super.key});

  final String repoUrl = 'https://github.com/abdulmominsakib/localmind';

  Future<void> _launchUrl() async {
    final Uri url = Uri.parse(repoUrl);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: _launchUrl,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedGithub,
                  size: 20,
                  color: isDark
                      ? AppColors.darkPrimaryText
                      : AppColors.lightPrimaryText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.open_source,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkPrimaryText
                              : AppColors.lightPrimaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.star_on_github,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.darkAccent
                              : AppColors.lightAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                HugeIcon(
                  icon: HugeIcons.strokeRoundedShare01,
                  size: 14,
                  color: isDark
                      ? AppColors.darkMutedText
                      : AppColors.lightMutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
