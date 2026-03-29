import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/features/chat/data/models/message.dart';
import 'package:localmind/features/chat/providers/chat_providers.dart';
import 'package:localmind/features/chat/views/components/chat_bubble.dart';
import 'package:localmind/features/chat/views/components/chat_input_bar.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/models/screens/model_picker_sheet.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  static const List<String> _quickPrompts = [
    'Help me write a function',
    'Explain this code',
    'Debug this for me',
    'How do I use async/await?',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final isNearBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (_showScrollToBottom != !isNearBottom) {
      setState(() => _showScrollToBottom = !isNearBottom);
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    ref.listen(chatProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollToBottom();
          }
        });
      }
    });

    return Column(
      children: [
        AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: GestureDetector(
            onTap: () => _showModelPicker(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selectedModel?.displayName ?? 'Select Model',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_more,
                  size: 16,
                  color: isDark
                      ? const Color(0xFF888888)
                      : const Color(0xFF666666),
                ),
              ],
            ),
          ),
          actions: [
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
        if (connectionStatus == ConnectionStatus.disconnected ||
            connectionStatus == ConnectionStatus.error)
          _ConnectionBanner(status: connectionStatus),
        Expanded(
          child: chatState.messages.isEmpty
              ? _EmptyState(
                  onQuickPrompt: (prompt) =>
                      ref.read(chatProvider.notifier).sendMessage(prompt),
                  quickPrompts: _quickPrompts,
                  recentConversations: ref.watch(recentConversationsProvider),
                  onSeeAll: () => context.go(AppRoutes.conversations),
                )
              : _MessageList(
                  scrollController: _scrollController,
                  messages: chatState.messages,
                  streamingMessage: chatState.streamingMessage,
                  isStreaming: chatState.isStreaming,
                  onRetry: (messageId) {
                    ref.read(chatProvider.notifier).retryLastMessage();
                  },
                  onDelete: (messageId) {
                    ref.read(chatProvider.notifier).deleteMessage(messageId);
                  },
                ),
        ),
        if (_showScrollToBottom && chatState.messages.isNotEmpty)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _scrollToBottom,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFE5E5E5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_downward,
                        size: 14,
                        color: isDark
                            ? const Color(0xFF888888)
                            : const Color(0xFF666666),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'New messages',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF888888)
                              : const Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ChatInputBar(
          onSend: (message) {
            ref.read(chatProvider.notifier).sendMessage(message);
          },
          onStop: () {
            ref.read(chatProvider.notifier).cancelStream();
          },
        ),
      ],
    );
  }

  void _showModelPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ModelPickerSheet(),
    );
  }

  void _handleMenuAction(String action, BuildContext context) {
    switch (action) {
      case 'new_chat':
        ref.read(chatProvider.notifier).startNewConversation();
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onQuickPrompt,
    required this.quickPrompts,
    required this.recentConversations,
    required this.onSeeAll,
  });

  final void Function(String) onQuickPrompt;
  final List<String> quickPrompts;
  final List<Conversation> recentConversations;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedChatBot,
              size: 64,
              color: isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
            ),
            const SizedBox(height: 24),
            Text(
              'LocalMind',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your AI. Your Device. Your Rules.',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF666666),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Start a conversation',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: quickPrompts.map((prompt) {
                return ActionChip(
                  label: Text(prompt),
                  onPressed: () => onQuickPrompt(prompt),
                  backgroundColor: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFF5F5F5),
                  side: BorderSide(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFE5E5E5),
                  ),
                );
              }).toList(),
            ),
            if (recentConversations.isNotEmpty) ...[
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
                    onTap: onSeeAll,
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
              ...recentConversations
                  .take(5)
                  .map(
                    (conv) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _RecentConversationItem(conversation: conv),
                    ),
                  ),
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
  });

  final ScrollController scrollController;
  final List<Message> messages;
  final Message? streamingMessage;
  final bool isStreaming;
  final void Function(String) onRetry;
  final void Function(String) onDelete;

  @override
  Widget build(BuildContext context) {
    final allMessages = <Message>[];

    for (final message in messages) {
      if (streamingMessage != null &&
          message.id == streamingMessage!.id &&
          message.content.isEmpty &&
          isStreaming) {
        continue;
      }
      allMessages.add(message);
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 16),
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
