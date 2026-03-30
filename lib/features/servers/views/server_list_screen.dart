import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/providers/service_providers.dart';
import '../providers/server_providers.dart';
import 'components/server_card.dart';

class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    final activeServer = ref.watch(activeServerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
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
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Servers',
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
                child: servers.isEmpty
                    ? _buildEmptyState(context, isDark, theme)
                    : RefreshIndicator(
                        onRefresh: () async {
                          for (final server in servers) {
                            await ref
                                .read(serversProvider.notifier)
                                .testConnection(
                                  server.id,
                                  ref.read(serverApiServiceProvider),
                                );
                          }
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: servers.length,
                          itemBuilder: (context, index) {
                            final server = servers[index];
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
                                        'Switched to ${server.name}',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                onEdit: () =>
                                    _showEditDialog(context, ref, server),
                                onDelete: () => _showDeleteConfirmation(
                                  context,
                                  ref,
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
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              onPressed: () => context.push(AppRoutes.addServer),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.computer, size: 80, color: theme.colorScheme.outline),
            const SizedBox(height: 24),
            Text('No Servers Yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Add your first server to start chatting with AI models.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push(AppRoutes.addServer),
              icon: const Icon(Icons.add),
              label: const Text('Add Server'),
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
    dynamic server,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Server'),
        content: Text(
          'Are you sure you want to delete "${server.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              ref.read(serversProvider.notifier).deleteServer(server.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
