import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Using standard colors from theme or defaults to ensure consistent premium look
    final cardBg = isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF9FAFB);
    final borderColor = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
    final accentColor = isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ShadCard(
        padding: const EdgeInsets.all(16),
        backgroundColor: cardBg,
        border: ShadBorder.all(color: borderColor),
        radius: BorderRadius.circular(12),
        title: Row(
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedGithub,
              size: 20,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 8),
            Text(
              'Open Source',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        description: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'LocalMind is open source. Follow our progress or contribute on GitHub.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFFA0A0A0) : const Color(0xFF666666),
              height: 1.4,
            ),
          ),
        ),
        footer: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ShadButton.ghost(
            width: double.infinity,
            padding: EdgeInsets.zero,
            onPressed: _launchUrl,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Star on GitHub',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.open_in_new,
                  size: 14,
                  color: accentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
