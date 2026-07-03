import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/routes/app_routes.dart';
import '../../core/components/app_sizes.dart';
import '../../core/models/enums.dart';
import '../../l10n/app_localizations.dart';
import '../chat/providers/chat_providers.dart';
import '../lm_studio_catalog/views/lm_studio_download_widgets.dart';
import '../servers/providers/server_providers.dart';
import 'components/active_server_indicator.dart';
import 'components/conversation_drawer_header.dart';
import 'components/drawer_nav_item.dart';
import 'components/github_repo_card.dart';
import 'components/sidebar_search_button.dart';
import '../tts/views/components/tts_player_bar.dart';

class SidebarWidget extends ConsumerWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).uri.toString();

    final isHistory = location.startsWith(AppRoutes.chatHistory);
    final isSavedMessages = location.startsWith(AppRoutes.savedMessages);
    final isServers = location.startsWith(AppRoutes.servers);
    final isMcpTools = location.startsWith(AppRoutes.mcpTools);
    final isPersonas = location.startsWith(AppRoutes.personas);
    final isLocalModels = location.startsWith(AppRoutes.onDeviceModels);
    final isTtsModels = location.startsWith(AppRoutes.ttsModels);
    final isSettings = location.startsWith(AppRoutes.settings);
    final isHome = location == AppRoutes.home || location == '/';
    final hasActiveChat = ref.watch(hasActiveChatSessionProvider);
    final isTemporary = ref.watch(chatProvider.select((s) => s.isTemporary));
    final activeServer = ref.watch(activeServerProvider);
    final isLmStudio =
        activeServer != null && activeServer.type == ServerType.lmStudio;

    return Container(
      width: AppSizes.sidebarWidth,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Directionality.of(context) == TextDirection.rtl
            ? Border(left: BorderSide(color: theme.colorScheme.outline))
            : Border(right: BorderSide(color: theme.colorScheme.outline)),
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
                child: Text(l10n.nav_new_chat),
              ),
            ),

            if (hasActiveChat)
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, isHome ? 8 : 8),
                child: isTemporary
                    ? ShadButton.outline(
                        width: double.infinity,
                        leading: const Icon(Icons.arrow_back, size: 18),
                        onPressed: () {
                          if (!isHome) context.go(AppRoutes.home);
                          if (Scaffold.maybeOf(context)?.isDrawerOpen ??
                              false) {
                            Navigator.pop(context);
                          }
                        },
                        child: Text(l10n.return_to_temp_chat),
                      )
                    : ShadButton.secondary(
                        width: double.infinity,
                        leading: const Icon(Icons.arrow_back, size: 18),
                        onPressed: () {
                          if (!isHome) context.go(AppRoutes.home);
                          if (Scaffold.maybeOf(context)?.isDrawerOpen ??
                              false) {
                            Navigator.pop(context);
                          }
                        },
                        child: Text(l10n.return_to_chat),
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
                      label: l10n.nav_history,
                      isSelected: isHistory,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.chatHistory);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedBookmark02,
                      label: l10n.nav_saved_messages,
                      isSelected: isSavedMessages,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.savedMessages);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedServerStack01,
                      label: l10n.nav_servers,
                      isSelected: isServers,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.servers);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedMcpServer,
                      label: l10n.mcp_tools_title,
                      isSelected: isMcpTools,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.mcpTools);
                      },
                    ),
                    if (isLmStudio)
                      DrawerNavItem(
                        iconData: HugeIcons.strokeRoundedAiSearch,
                        label: l10n.lm_studio_model_search,
                        isSelected: false,
                        trailing: const LmDownloadIndicatorButton(compact: true),
                        onTap: () {
                          if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                            Navigator.pop(context);
                          }
                          context.push(
                            AppRoutes.lmStudioModelBrowser,
                            extra: activeServer,
                          );
                        },
                      ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedSmartPhone01,
                      label: l10n.nav_local_models,
                      isSelected: isLocalModels,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.onDeviceModels);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedVoice,
                      label: l10n.nav_tts,
                      isSelected: isTtsModels,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.ttsModels);
                      },
                    ),
                    DrawerNavItem(
                      iconData: HugeIcons.strokeRoundedCompass01,
                      label: l10n.nav_personas,
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
                      label: l10n.nav_settings,
                      isSelected: isSettings,
                      onTap: () {
                        if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                          Navigator.pop(context);
                        }
                        context.go(AppRoutes.settings);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Duplicate Player controls
            const TtsPlayerBar(),

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
}
