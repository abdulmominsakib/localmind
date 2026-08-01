import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../../core/models/enums.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/utils/system_insets.dart';
import '../providers/server_providers.dart';
import 'components/server_card.dart';

class ServerListScreen extends ConsumerStatefulWidget {
  const ServerListScreen({super.key});

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAllConnections();
    });
  }

  Future<void> _checkAllConnections() async {
    final apiService = ref.read(serverApiServiceProvider);
    await ref.read(serversProvider.notifier).testAllConnections(apiService);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final servers = ref.watch(serversProvider);
    final activeServer = ref.watch(activeServerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final systemBottomInset = bottomSystemInset(context);
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: topPadding + 8,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0A0A0A)
                    : const Color(0xFFFAFAFA),
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFE5E5E5),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenu01),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.servers_title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: servers.when(
                data: (serverList) => serverList.isEmpty
                    ? _buildEmptyState(context, l10n, theme)
                    : RefreshIndicator(
                        onRefresh: _checkAllConnections,
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            16,
                            16,
                            16 + systemBottomInset + 80,
                          ),
                          itemCount: serverList.length,
                          itemBuilder: (context, index) {
                            final server = serverList[index];
                            final isOnDevice =
                                server.type == ServerType.onDevice;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: ServerCard(
                                server: server,
                                isActive: activeServer?.id == server.id,
                                onTap: () {
                                  ref
                                      .read(activeServerProvider.notifier)
                                      .setActiveServer(server);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l10n.switched_to_server(server.name),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                onEdit: isOnDevice
                                    ? null
                                    : () =>
                                          _showEditDialog(context, ref, server),
                                onDelete: isOnDevice
                                    ? null
                                    : () => _showDeleteConfirmation(
                                        context,
                                        ref,
                                        l10n,
                                        server,
                                      ),
                                onSetDefault: () {
                                  ref
                                      .read(serversProvider.notifier)
                                      .setDefault(server.id);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const HugeIcon(icon: 
                        HugeIcons.strokeRoundedInformationCircle,
                        color: Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(l10n.error_with_message(err.toString())),
                      TextButton(
                        onPressed: () => ref.invalidate(serversProvider),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          bottom: 24,
          end: 24,
          child: FloatingActionButton(
            onPressed: () => context.push(AppRoutes.addServer),
            child: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(icon: HugeIcons.strokeRoundedComputer, size: 80, color: theme.colorScheme.outline),
            const SizedBox(height: 24),
            Text(l10n.no_servers_yet, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              l10n.no_servers_desc,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push(AppRoutes.addServer),
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
              label: Text(l10n.add_server),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, dynamic server) {
    context.push(AppRoutes.addServer, extra: server);
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    dynamic server,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final dlgL10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(dlgL10n.delete_server_title),
          content: Text(dlgL10n.delete_server_body(server.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(dlgL10n.cancel),
            ),
            TextButton(
              onPressed: () {
                ref.read(serversProvider.notifier).deleteServer(server.id);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(dlgL10n.delete),
            ),
          ],
        );
      },
    );
  }
}