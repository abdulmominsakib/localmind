import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/features/servers/views/components/server_icon_picker.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/chat/views/components/chat_bubble.dart';
import 'package:localmind/features/chat/views/components/chat_input_bar.dart';
import 'package:localmind/features/chat/views/components/mcp_config_sheet.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/models/screens/model_picker_sheet.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  static const List<String> _quickPrompts = [
    'Help me write a function',
    'Explain this code',
    'Debug this for me',
    'How do I use async/await?',
  ];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoSelectFirstLoadedModelProvider);

    final chatState = ref.watch(chatProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final activeServer = ref.watch(activeServerProvider);
    final activeConversation = ref.watch(conv.activeConversationProvider);
    final personaId = activeConversation?.personaId;
    final persona = personaId != null
        ? ref.watch(personaByIdProvider(personaId))
        : null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Autoscroll disabled as per user request
    // ref.listen(chatProvider, (previous, next) { ... });

    return Column(
      children: [
        _ModelTopBar(
          selectedModel: selectedModel,
          onTap: () => _showModelPicker(context),
        ),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              ShadResponsiveBuilder(
                builder: (context, breakpoint) {
                  final isDesktop =
                      breakpoint >= ShadTheme.of(context).breakpoints.md;
                  if (isDesktop) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    if (activeServer != null) ...[
                      _buildServerIcon(context, activeServer),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      activeServer?.name ?? 'LocalMind',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connectionStatus == ConnectionStatus.connected
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Consumer(
                builder: (context, ref, child) {
                  final settings = ref.watch(settingsProvider);
                  final mcpConfig = ref.watch(chatMcpConfigProvider);
                  final isEnabled = settings.mcpEnabled && mcpConfig.enabled;
                  return IconButton(
                    icon: Icon(
                      isEnabled
                          ? Icons.extension
                          : Icons.extension_off_outlined,
                      color: isEnabled
                          ? theme.colorScheme.primary
                          : (isDark
                                ? const Color(0xFF666666)
                                : const Color(0xFF999999)),
                    ),
                    tooltip: isEnabled ? 'MCP Enabled' : 'MCP Disabled',
                    onPressed: () => showMcpConfigSheet(context),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push(AppRoutes.settings),
                tooltip: 'Settings',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) => _handleMenuAction(value, context),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'new_chat',
                    child: ListTile(
                      leading: Icon(Icons.add),
                      title: Text('New Chat'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'persona',
                    child: ListTile(
                      leading: Icon(
                        persona != null
                            ? Icons.swap_horiz
                            : Icons.smart_toy_outlined,
                      ),
                      title: Text(
                        persona != null ? 'Change Persona' : 'Set Persona',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (persona != null)
                    const PopupMenuItem(
                      value: 'remove_persona',
                      child: ListTile(
                        leading: Icon(Icons.person_remove_outlined),
                        title: Text('Remove Persona'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Clear Conversation'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (connectionStatus == ConnectionStatus.disconnected ||
            connectionStatus == ConnectionStatus.error)
          _ConnectionBanner(status: connectionStatus),
        if (persona != null)
          _PersonaIndicator(
            persona: persona,
            onTap: () => _showPersonaPicker(context),
            onRemove: () {
              final activeConv = ref.read(conv.activeConversationProvider);
              if (activeConv != null) {
                ref
                    .read(conv.conversationsProvider.notifier)
                    .updatePersona(activeConv.id, null, null);
              }
            },
          ),
        Expanded(
          child: Stack(
            children: [
              chatState.messages.isEmpty
                  ? _EmptyState(
                      onQuickPrompt: (prompt) =>
                          ref.read(chatProvider.notifier).sendMessage(prompt),
                      quickPrompts: _quickPrompts,
                      recentConversations: ref.watch(
                        recentConversationsProvider,
                      ),
                      onSeeAll: () {
                        if (Scaffold.maybeOf(context)?.hasDrawer ?? false) {
                          Scaffold.of(context).openDrawer();
                        }
                      },
                      selectedModel: selectedModel,
                      onModelTap: () => _showModelPicker(context),
                      selectedPersona: ref.watch(selectedPersonaProvider),
                      onPersonaTap: () =>
                          _showPersonaPickerForPreselection(context),
                    )
                  : _MessageList(
                      scrollController: _scrollController,
                      messages: chatState.messages,
                      streamingMessage: chatState.streamingMessage,
                      isStreaming: chatState.isStreaming,
                      onRetry: (messageId) {
                        ref.read(chatProvider.notifier).retryMessage(messageId);
                      },
                      onDelete: (messageId) {
                        ref
                            .read(chatProvider.notifier)
                            .deleteMessage(messageId);
                      },
                      hasSmartReplies:
                          !chatState.isStreaming &&
                          ref.read(smartRepliesProvider).isNotEmpty,
                    ),
              if (!chatState.isStreaming)
                Positioned(
                  bottom: 90,
                  left: 0,
                  right: 0,
                  child: _SmartReplyChips(
                    onSend: (message) {
                      ref.read(chatProvider.notifier).sendMessage(message);
                    },
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ChatInputBar(
                  isStreaming: chatState.isStreaming,
                  onSend: (message, {attachments}) {
                    ref
                        .read(chatProvider.notifier)
                        .sendMessage(message, attachments: attachments);
                  },
                  onStop: () {
                    ref.read(chatProvider.notifier).cancelStream();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showModelPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const ModelPickerSheet(),
    );
  }

  void _handleMenuAction(String action, BuildContext context) {
    switch (action) {
      case 'new_chat':
        ref.read(chatProvider.notifier).startNewConversation();
        break;
      case 'persona':
        _showPersonaPicker(context);
        break;
      case 'remove_persona':
        final activeConv = ref.read(conv.activeConversationProvider);
        if (activeConv != null) {
          ref
              .read(conv.conversationsProvider.notifier)
              .updatePersona(activeConv.id, null, null);
        }
        break;
      case 'clear':
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Clear conversation?'),
            content: const Text(
              'This will delete all messages in this conversation.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(chatProvider.notifier).clearConversation();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        );
        break;
    }
  }

  void _showPersonaPicker(BuildContext context) {
    final personas = ref.read(personasNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeConv = ref.read(conv.activeConversationProvider);
    final currentPersonaId = activeConv?.personaId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[600] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Persona',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: personas.length,
                    itemBuilder: (context, index) {
                      final p = personas[index];
                      final isSelected = p.id == currentPersonaId;
                      final accent = isDark
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF2563EB);
                      return ListTile(
                        leading: Text(
                          p.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: p.description != null
                            ? Text(
                                p.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFF888888)
                                      : const Color(0xFF999999),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: accent)
                            : null,
                        onTap: () {
                          if (activeConv != null) {
                            ref
                                .read(conv.conversationsProvider.notifier)
                                .updatePersona(
                                  activeConv.id,
                                  p.id,
                                  p.systemPrompt,
                                );
                          }
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPersonaPickerForPreselection(BuildContext context) {
    final personas = ref.read(personasNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPersona = ref.watch(selectedPersonaProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[600] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Persona',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: personas.length,
                    itemBuilder: (context, index) {
                      final p = personas[index];
                      final isSelected = p.id == currentPersona?.id;
                      final accent = isDark
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF2563EB);
                      return ListTile(
                        leading: Text(
                          p.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: p.description != null
                            ? Text(
                                p.description!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFF888888)
                                      : const Color(0xFF999999),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: accent)
                            : null,
                        onTap: () {
                          ref.read(selectedPersonaProvider.notifier).select(p);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildServerIcon(BuildContext context, Server server) {
    final iconData = server.iconName != null
        ? getHugeIconByName(server.iconName)
        : getDefaultServerIcon(server.type.name);

    if (iconData == null) {
      return const Icon(Icons.dns, size: 18);
    }

    return HugeIcon(
      icon: iconData.icon,
      size: 18,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

class _ModelTopBar extends StatelessWidget {
  const _ModelTopBar({required this.selectedModel, required this.onTap});

  final dynamic selectedModel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    selectedModel?.displayName ?? 'Select Model',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more,
                  size: 14,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final isError = status == ConnectionStatus.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isError
          ? Colors.red.withValues(alpha: 0.1)
          : Colors.orange.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.wifi_off,
            size: 16,
            color: isError ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isError
                  ? 'Connection error. Check your server.'
                  : 'Disconnected from server.',
              style: TextStyle(
                fontSize: 13,
                color: isError ? Colors.red : Colors.orange[700],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              context.push(AppRoutes.servers);
            },
            child: Text(
              'Configure',
              style: TextStyle(
                fontSize: 13,
                color: isError ? Colors.red : Colors.orange[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatefulWidget {
  const _EmptyState({
    required this.onQuickPrompt,
    required this.quickPrompts,
    required this.recentConversations,
    required this.onSeeAll,
    required this.selectedModel,
    required this.onModelTap,
    this.selectedPersona,
    required this.onPersonaTap,
  });

  final void Function(String) onQuickPrompt;
  final List<String> quickPrompts;
  final List<Conversation> recentConversations;
  final VoidCallback onSeeAll;
  final dynamic selectedModel;
  final VoidCallback onModelTap;
  final dynamic selectedPersona;
  final VoidCallback onPersonaTap;

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _fadeAnimations;
  late List<Animation<Offset>> _slideAnimations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimations = List.generate(widget.quickPrompts.length, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            (index * 0.1).clamp(0.0, 0.7),
            (0.3 + index * 0.1).clamp(0.2, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      );
    });

    _slideAnimations = List.generate(widget.quickPrompts.length, (index) {
      return Tween<Offset>(
        begin: const Offset(0.0, 0.3),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            (index * 0.1).clamp(0.0, 0.7),
            (0.3 + index * 0.1).clamp(0.2, 1.0),
            curve: Curves.easeOutCubic,
          ),
        ),
      );
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 24),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  GestureDetector(
                    onTap: widget.onModelTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF333333)
                              : const Color(0xFFE5E5E5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.settings_suggest,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              widget.selectedModel?.displayName ?? 'Select Model',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.expand_more,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: widget.onPersonaTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF333333)
                              : const Color(0xFFE5E5E5),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.selectedPersona != null) ...[
                            Text(
                              widget.selectedPersona!.emoji,
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.selectedPersona!.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else ...[
                            Icon(
                              Icons.smart_toy_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Select Persona',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.expand_more,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(opacity: value, child: child);
              },
              child: Text(
                'Start a conversation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: widget.quickPrompts.asMap().entries.map((entry) {
                final index = entry.key;
                final prompt = entry.value;
                final fadeAnimation = index < _fadeAnimations.length
                    ? _fadeAnimations[index]
                    : const AlwaysStoppedAnimation(1.0);
                final slideAnimation = index < _slideAnimations.length
                    ? _slideAnimations[index]
                    : const AlwaysStoppedAnimation(Offset.zero);

                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: fadeAnimation,
                      child: SlideTransition(
                        position: slideAnimation,
                        child: child,
                      ),
                    );
                  },
                  child: ActionChip(
                    label: Text(prompt),
                    onPressed: () => widget.onQuickPrompt(prompt),
                    backgroundColor: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFF5F5F5),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFFE5E5E5),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (widget.recentConversations.isNotEmpty) ...[
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Recent chats',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFFA0A0A0)
                          : const Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onSeeAll,
                    child: Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...List.generate(widget.recentConversations.take(5).length, (
                index,
              ) {
                final conv = widget.recentConversations.take(5).toList()[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 400 + (index * 50)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 10 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _RecentConversationItem(conversation: conv),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentConversationItem extends ConsumerWidget {
  const _RecentConversationItem({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        ref.read(chatProvider.notifier).loadConversation(conversation);
      },
      child: Container(
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (conversation.lastMessagePreview != null)
                    Text(
                      conversation.lastMessagePreview!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? const Color(0xFF888888)
                            : const Color(0xFF666666),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: isDark ? const Color(0xFF666666) : const Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.scrollController,
    required this.messages,
    required this.streamingMessage,
    required this.isStreaming,
    required this.onRetry,
    required this.onDelete,
    this.hasSmartReplies = false,
  });

  final ScrollController scrollController;
  final List<Message> messages;
  final Message? streamingMessage;
  final bool isStreaming;
  final void Function(String) onRetry;
  final void Function(String) onDelete;
  final bool hasSmartReplies;

  @override
  Widget build(BuildContext context) {
    final allMessages = <Message>[];

    for (final message in messages) {
      if (streamingMessage != null &&
          message.id == streamingMessage!.id &&
          isStreaming) {
        continue;
      }
      allMessages.add(message);
    }

    return ListView.builder(
      controller: scrollController,
      cacheExtent: 1000,
      padding: EdgeInsets.only(
        top: 16,
        bottom: 120 + (hasSmartReplies ? 56 : 0),
      ),
      itemCount:
          allMessages.length +
          (streamingMessage != null && isStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (streamingMessage != null &&
            isStreaming &&
            index == allMessages.length) {
          return ChatBubble(message: streamingMessage!, isStreaming: true);
        }

        final message = allMessages[index];
        final isLast = index == allMessages.length - 1;

        return ChatBubble(
          key: ValueKey(message.id),
          message: message,
          isStreaming:
              isLast && isStreaming && message.id == streamingMessage?.id,
          onRetry: () => onRetry(message.id),
          onDelete: () => onDelete(message.id),
        );
      },
    );
  }
}

class _SmartReplyChips extends ConsumerStatefulWidget {
  const _SmartReplyChips({required this.onSend});
  final ValueChanged<String> onSend;

  @override
  ConsumerState<_SmartReplyChips> createState() => _SmartReplyChipsState();
}

class _SmartReplyChipsState extends ConsumerState<_SmartReplyChips>
    with TickerProviderStateMixin {
  List<String> _previousSuggestions = [];
  late AnimationController _controller;
  List<Animation<double>> _fadeAnimations = [];
  List<Animation<Offset>> _slideAnimations = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _updateAnimations(List<String> suggestions) {
    if (suggestions.isEmpty) {
      _previousSuggestions = [];
      return;
    }
    if (_listsEqual(suggestions, _previousSuggestions)) {
      return;
    }

    _previousSuggestions = List.from(suggestions);

    _fadeAnimations = List.generate(suggestions.length, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            (index * 0.1).clamp(0.0, 0.8),
            (0.3 + index * 0.1).clamp(0.2, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      );
    });

    _slideAnimations = List.generate(suggestions.length, (index) {
      return Tween<Offset>(
        begin: const Offset(0.0, 0.5),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            (index * 0.1).clamp(0.0, 0.8),
            (0.3 + index * 0.1).clamp(0.2, 1.0),
            curve: Curves.easeOut,
          ),
        ),
      );
    });

    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = ref.watch(smartRepliesProvider);

    if (suggestions.isEmpty) {
      _previousSuggestions = [];
      return const SizedBox.shrink();
    }

    _updateAnimations(suggestions);

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          padding: EdgeInsets.only(left: 8),
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final label = suggestions[index];
            final fadeAnimation = index < _fadeAnimations.length
                ? _fadeAnimations[index]
                : const AlwaysStoppedAnimation(1.0);
            final slideAnimation = index < _slideAnimations.length
                ? _slideAnimations[index]
                : const AlwaysStoppedAnimation(Offset.zero);

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return FadeTransition(
                  opacity: fadeAnimation,
                  child: SlideTransition(
                    position: slideAnimation,
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: () => widget.onSend(label),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFFE0E0E0),
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFFCCCCCC)
                          : const Color(0xFF444444),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PersonaIndicator extends StatelessWidget {
  const _PersonaIndicator({
    required this.persona,
    required this.onTap,
    required this.onRemove,
  });

  final dynamic persona;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF121212) : const Color(0xFFF9F9F9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(persona.emoji, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      persona.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Remove Persona',
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ],
      ),
    );
  }
}
