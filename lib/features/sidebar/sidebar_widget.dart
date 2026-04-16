import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/routes/app_routes.dart';
import '../conversations/providers/conversation_providers.dart';
import '../conversations/views/components/conversation_empty_state.dart';
import '../conversations/views/components/conversation_list.dart';
import '../conversations/views/components/conversation_search_bar.dart';
import 'components/active_server_indicator.dart';
import 'components/conversation_drawer_header.dart';
import 'components/drawer_nav_item.dart';
import 'components/github_repo_card.dart';

class SidebarWidget extends ConsumerWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final groupedConversations = ref.watch(groupedConversationsProvider);
    final activeConversation = ref.watch(activeConversationProvider);
    final searchQuery = ref.watch(conversationSearchProvider);

    final location = GoRouterState.of(context).uri.toString();
    final isServers = location.startsWith(AppRoutes.servers);
    final isPersonas = location.startsWith(AppRoutes.personas);
    final isHistory = location.startsWith(AppRoutes.chatHistory);

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
            const ConversationSearchBar(),
            const Divider(height: 1),
            Expanded(
              child: groupedConversations.when(
                data: (grouped) => grouped.isEmpty
                    ? ConversationEmptyState(
                        isSearching: searchQuery.isNotEmpty,
                      )
                    : ConversationList(
                        groupedConversations: grouped,
                        activeConversation: activeConversation,
                      ),
                loading: () => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (err, stack) => Center(
                  child: Text(
                    'Error: $err',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ),
            const GitHubRepoCard(),
            const Divider(height: 1),
            const ActiveServerIndicator(),
            const SizedBox(height: 8),
            DrawerNavItem(
              iconData: HugeIcons.strokeRoundedClock01,
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
              isSelected: location.startsWith(AppRoutes.onDeviceModels),
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
          ],
        ),
      ),
    );
  }
}
