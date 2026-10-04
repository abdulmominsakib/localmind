import 'package:cue/cue.dart';
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
import '../saved_messages/providers/saved_message_providers.dart';
import '../servers/providers/server_providers.dart';
import 'components/active_server_indicator.dart';
import 'components/conversation_drawer_header.dart';
import 'components/drawer_nav_item.dart';
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
    final isCloudSync = location.startsWith(AppRoutes.cloudSync);
    final isSettings = location == AppRoutes.settings;
    final isHome = location == AppRoutes.home || location == '/';
    final hasActiveChat = ref.watch(hasActiveChatSessionProvider);
    final isTemporary = ref.watch(chatProvider.select((s) => s.isTemporary));
    final activeServer = ref.watch(activeServerProvider);
    final isLmStudio =
        activeServer != null && activeServer.type == ServerType.lmStudio;
    final savedCount = ref.watch(savedMessagesProvider).value?.length ?? 0;
    final serverCount = ref.watch(serversProvider).value?.length ?? 0;

    void closeDrawer() {
      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
        Navigator.pop(context);
      }
    }

    void open(String route) {
      closeDrawer();
      context.go(route);
    }

    return Container(
      width: AppSizes.sidebarWidth,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Directionality.of(context) == TextDirection.rtl
            ? Border(left: BorderSide(color: theme.colorScheme.outline))
            : Border(right: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: SafeArea(
        child: Cue.onMount(
          motion: .smooth(),
          child: Column(
            children: [
              Actor(
                acts: [.fadeIn(), .slideX(from: -0.05)],
                child: const ConversationDrawerHeader(),
              ),

              // New Chat Button
              Actor(
                delay: 60.ms,
                acts: [.fadeIn(), .slideX(from: -0.04)],
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: ShadButton(
                    width: double.infinity,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedAdd01,
                      size: 20,
                    ),
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
              ),

              if (hasActiveChat)
                Actor(
                  delay: 120.ms,
                  acts: [.fadeIn(), .slideX(from: -0.04)],
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: isTemporary
                        ? ShadButton.outline(
                            width: double.infinity,
                            height: 36,
                            leading: const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowLeft01,
                              size: 18,
                            ),
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
                            height: 36,
                            leading: const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowLeft01,
                              size: 18,
                            ),
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
                ),

              Actor(
                delay: 180.ms,
                acts: [.fadeIn()],
                child: const SidebarSearchButton(),
              ),
              const SizedBox(height: 4),

              // Grouped menu: chats, then models and voices, then the app.
              Expanded(
                child: Actor(
                  delay: 220.ms,
                  acts: [.fadeIn(), .slideY(from: 0.04)],
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DrawerSectionLabel(label: l10n.sidebar_section_chats),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedChatting01,
                          label: l10n.nav_history,
                          isSelected: isHistory,
                          onTap: () => open(AppRoutes.chatHistory),
                        ),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedBookmark02,
                          label: l10n.nav_saved_messages,
                          isSelected: isSavedMessages,
                          badgeText: savedCount > 0 ? '$savedCount' : null,
                          onTap: () => open(AppRoutes.savedMessages),
                        ),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedCompass01,
                          label: l10n.nav_personas,
                          isSelected: isPersonas,
                          onTap: () => open(AppRoutes.personas),
                        ),
                        DrawerSectionLabel(label: l10n.sidebar_section_models),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedServerStack01,
                          label: l10n.nav_servers,
                          isSelected: isServers,
                          badgeText: serverCount > 0 ? '$serverCount' : null,
                          onTap: () => open(AppRoutes.servers),
                        ),
                        if (isLmStudio)
                          DrawerNavItem(
                            iconData: HugeIcons.strokeRoundedAiSearch,
                            label: l10n.lm_studio_model_search,
                            isSelected: false,
                            trailing: const LmDownloadIndicatorButton(
                              compact: true,
                            ),
                            onTap: () {
                              closeDrawer();
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
                          onTap: () => open(AppRoutes.onDeviceModels),
                        ),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedVoice,
                          label: l10n.nav_tts,
                          isSelected: isTtsModels,
                          onTap: () => open(AppRoutes.ttsModels),
                        ),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedMcpServer,
                          label: l10n.mcp_tools_title,
                          isSelected: isMcpTools,
                          onTap: () => open(AppRoutes.mcpTools),
                        ),
                        DrawerSectionLabel(label: l10n.sidebar_section_app),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedCloudSavingDone02,
                          label: l10n.cloud_sync,
                          isSelected: isCloudSync,
                          onTap: () => open(AppRoutes.cloudSync),
                        ),
                        DrawerNavItem(
                          iconData: HugeIcons.strokeRoundedSettings01,
                          label: l10n.nav_settings,
                          isSelected: isSettings,
                          onTap: () => open(AppRoutes.settings),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),

              Actor(
                delay: 320.ms,
                acts: [.fadeIn(), .slideY(from: 0.06)],
                child: const TtsPlayerBar(),
              ),

              const Divider(height: 1),
              Actor(
                delay: 400.ms,
                acts: [.fadeIn()],
                child: const ActiveServerIndicator(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
