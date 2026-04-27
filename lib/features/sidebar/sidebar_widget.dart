import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/routes/app_routes.dart';
import '../../core/providers/app_providers.dart';
import '../../core/theme/app_theme.dart';
import '../chat/providers/chat_providers.dart';
import 'components/active_server_indicator.dart';
import 'components/conversation_drawer_header.dart';
import 'components/drawer_nav_item.dart';
import 'components/github_repo_card.dart';
import 'components/sidebar_search_button.dart';

class SidebarWidget extends ConsumerWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).uri.toString();

    final isHistory = location.startsWith(AppRoutes.chatHistory);
    final isServers = location.startsWith(AppRoutes.servers);
    final isPersonas = location.startsWith(AppRoutes.personas);
    final themeMode = ref.watch(themeModeProvider);
    final isLocalModels = location.startsWith(AppRoutes.onDeviceModels);
    final isSettings = location.startsWith(AppRoutes.settings);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(right: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const ConversationDrawerHeader(),

            // New Chat Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ShadButton(
                width: double.infinity,
                leading: const Icon(LucideIcons.plus, size: 20),
                onPressed: () {
                  ref.read(chatProvider.notifier).startNewConversation();
                  context.go(AppRoutes.home);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('New Chat'),
              ),
            ),

            const SidebarSearchButton(),
            const SizedBox(height: 8),
            const Divider(height: 1, indent: 16, endIndent: 16),
            const SizedBox(height: 12),

            // Primary Navigation
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedChatting01,
                      label: 'History',
                      isSelected: isHistory,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.chatHistory);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedServerStack01,
                      label: 'Servers',
                      isSelected: isServers,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.servers);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedSmartPhone01,
                      label: 'Local Models',
                      isSelected: isLocalModels,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.onDeviceModels);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedCompass01,
                      label: 'Personas',
                      isSelected: isPersonas,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.personas);
                      },
                    ),
                    const SizedBox(height: 8),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    const SizedBox(height: 8),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedSettings01,
                      label: 'Settings',
                      isSelected: isSettings,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.settings);
                      },
                    ),
                    DrawerNavItem(
                      iconData: _getThemeIcon(themeMode),
                      label: 'Appearance: ${_getThemeLabel(themeMode)}',
                      isSelected: false,
                      onTap: () {
                        final nextMode =
                            AppThemeType.values[(themeMode.index + 1) %
                                AppThemeType.values.length];
                        ref
                            .read(themeModeProvider.notifier)
                            .setThemeMode(nextMode);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Section
            const GitHubRepoCard(),
            const Divider(height: 1),
            const ActiveServerIndicator(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<List<dynamic>> _getThemeIcon(AppThemeType mode) {
    switch (mode) {
      case AppThemeType.system:
        return HugeIcons.strokeRoundedSettings01;
      case AppThemeType.light:
        return HugeIcons.strokeRoundedSun01;
      case AppThemeType.dark:
        return HugeIcons.strokeRoundedMoon02;
      case AppThemeType.claude:
        return HugeIcons.strokeRoundedPaintBrush02;
    }
  }

  String _getThemeLabel(AppThemeType mode) {
    switch (mode) {
      case AppThemeType.system:
        return 'System';
      case AppThemeType.light:
        return 'Light';
      case AppThemeType.dark:
        return 'Dark';
      case AppThemeType.claude:
        return 'Claude';
    }
  }
}
