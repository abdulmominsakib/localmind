import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/routes/app_routes.dart';
import '../conversations/providers/conversation_providers.dart';
import 'components/active_server_indicator.dart';
import 'components/conversation_drawer_header.dart';
import '../conversations/views/components/conversation_empty_state.dart';
import '../conversations/views/components/conversation_list.dart';
import '../conversations/views/components/conversation_search_bar.dart';
import 'components/drawer_nav_item.dart';
import '../conversations/views/components/new_chat_button.dart';

class SidebarWidget extends ConsumerWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final groupedConversations = ref.watch(groupedConversationsProvider);
    final activeConversation = ref.watch(activeConversationProvider);
    final searchQuery = ref.watch(conversationSearchProvider);

    final location = GoRouterState.of(context).uri.toString();
    final isHome = location == AppRoutes.home || location.isEmpty;
    final isServers = location.startsWith(AppRoutes.servers);
    final isPersonas = location.startsWith(AppRoutes.personas);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
        border: Border(
          right: BorderSide(
            color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFE5E5E5),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const ConversationDrawerHeader(),
            const NewChatButton(),
            const SizedBox(height: 8),
            const ConversationSearchBar(),
            const Divider(height: 1),
            Expanded(
              child: groupedConversations.isEmpty
                  ? ConversationEmptyState(isSearching: searchQuery.isNotEmpty)
                  : ConversationList(
                      groupedConversations: groupedConversations,
                      activeConversation: activeConversation,
                    ),
            ),
            const Divider(height: 1),
            const ActiveServerIndicator(),
            const SizedBox(height: 8),
            DrawerNavItem(
              iconData: HugeIcons.strokeRoundedMessageMultiple01,
              label: 'Chat',
              isSelected: isHome,
              onTap: () {
                context.go(AppRoutes.home);
                if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                  Navigator.pop(context);
                }
              },
            ),
            DrawerNavItem(
              iconData: HugeIcons.strokeRoundedServerStack01,
              label: 'Servers',
              isSelected: isServers,
              onTap: () {
                context.go(AppRoutes.servers);
                if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                  Navigator.pop(context);
                }
              },
            ),
            DrawerNavItem(
              iconData: HugeIcons.strokeRoundedCompass01,
              label: 'Personas',
              isSelected: isPersonas,
              onTap: () {
                context.go(AppRoutes.personas);
                if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                  Navigator.pop(context);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
