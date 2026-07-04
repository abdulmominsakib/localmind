import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/core/utils/system_insets.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/services/data_backup_service.dart';
import 'package:localmind/core/services/export_choice_dialog.dart';
import 'package:localmind/core/services/share_service.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/conversations/views/components/conversation_list.dart';
import 'package:localmind/features/conversations/views/components/rename_conversation_dialog.dart';
import 'package:localmind/features/models/screens/model_picker_sheet.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/saved_messages/views/components/save_message_sheet.dart';
import 'package:localmind/features/tts/views/components/tts_player_bar.dart';
import '../data/export_service.dart';
import '../data/models/message.dart';
import '../providers/chat_mcp_providers.dart';
import '../providers/chat_providers.dart';
import 'components/chat_auto_scroll_controller.dart';
import 'components/model_info_sheet.dart';
import 'components/chat_input_bar.dart';
import 'components/chat_settings_sheet.dart';
import 'components/edit_message_dialog.dart';
import 'components/notification_permission_banner.dart';
import 'components/message_list/message_list.dart';
import 'components/message_list/empty_state.dart';
import 'components/message_list/corrupted_state.dart';
import 'components/top_bar/model_top_bar.dart';
import 'components/top_bar/connection_banner.dart';
import 'components/top_bar/persona_indicator.dart';
import 'components/top_bar/smart_reply_chips.dart';
import 'package:localmind/features/personas/views/components/persona_picker_sheet.dart';

/// Height the always-on token usage row adds below the input box (its own
/// content height plus the padding around it) — added to the message list's
/// bottom padding so streamed content never ends up hidden behind it.
const double _tokenIndicatorRowHeight = 22;

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isApprovalDialogOpen = false;
  late final ChatAutoScrollController _autoScroll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputFocusNode.addListener(() => setState(() {}));
    _scrollController.addListener(
      () => _autoScroll.onScrollChanged(_scrollController),
    );
    _autoScroll = ChatAutoScrollController();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      ref.read(chatProvider.notifier).checkpointStreamingMessage(flush: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoSelectFirstLoadedModelProvider);

    ref.listen<PendingToolApproval?>(
      chatProvider.select((s) => s.pendingToolApproval),
      (previous, next) {
        if (next != null && !_isApprovalDialogOpen) {
          _showToolApprovalDialog(context, next);
        }
      },
    );

    return _ChatBody(
      scrollController: _scrollController,
      inputFocusNode: _inputFocusNode,
      autoScroll: _autoScroll,
      onModelPicker: () => _showModelPicker(context),
      onMenuAction: (action) => _handleMenuAction(action, context),
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
      case 'share_chat':
        _shareConversation(context);
      case 'persona':
        showPersonaPickerSheet(context);
      case 'rename':
        final activeConv = ref.read(conv.activeConversationProvider);
        if (activeConv != null) {
          _showRenameDialog(context, activeConv);
        }
      case 'move_to_folder':
        final activeConv = ref.read(conv.activeConversationProvider);
        if (activeConv != null) {
          showMoveToFolderSheet(
            context,
            ref,
            AppLocalizations.of(context)!,
            activeConv,
          );
        }
      case 'export_chat':
        _exportConversation(context);
      case 'clear':
        showDialog(
          context: context,
          builder: (context) {
            final dlgL10n = AppLocalizations.of(context)!;
            return AlertDialog(
              title: Text(dlgL10n.clear_conversation_title),
              content: Text(dlgL10n.clear_conversation_body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(dlgL10n.cancel),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ref.read(chatProvider.notifier).clearConversation();
                  },
                  child: Text(dlgL10n.clear),
                ),
              ],
            );
          },
        );
    }
  }

  Future<void> _shareConversation(BuildContext context) async {
    final messages = ref.read(chatProvider).messages;
    if (messages.isEmpty) return;
    final activeConv = ref.read(conv.activeConversationProvider);
    final isTemporary = ref.read(chatProvider.select((s) => s.isTemporary));
    final title = isTemporary
        ? AppLocalizations.of(context)!.temporary_chat
        : activeConv?.title;
    final text = ExportService.exportAsText(messages, title: title);
    await ShareService.shareText(text, subject: title);
  }

  Future<void> _exportConversation(BuildContext context) async {
    final messages = ref.read(chatProvider).messages;
    if (messages.isEmpty) return;

    final activeConv = ref.read(conv.activeConversationProvider);
    final isTemporary = ref.read(chatProvider.select((s) => s.isTemporary));
    final title = isTemporary
        ? AppLocalizations.of(context)!.temporary_chat
        : activeConv?.title;

    final content = activeConv != null && !isTemporary
        ? DataBackupService().exportConversationAsJson(
            ref.read(databaseProvider).store,
            activeConv.id,
          )
        : await ExportService.exportAsMarkdown(messages, title: title);

    if (!context.mounted) return;
    await showExportChoiceDialog(context, content: content, subject: title);
  }

  void _showRenameDialog(BuildContext context, Conversation conversation) {
    showRenameConversationDialog(context, ref, conversation: conversation);
  }

  void _showToolApprovalDialog(
    BuildContext context,
    PendingToolApproval approval,
  ) {
    setState(() => _isApprovalDialogOpen = true);
    final l10n = AppLocalizations.of(context)!;

    showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShadDialog.alert(
        title: Text('${l10n.execute_tool_title}: ${approval.toolCall.name}?'),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.execute_tool_request_desc),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  const JsonEncoder.withIndent(
                    '  ',
                  ).convert(approval.toolCall.arguments),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          ShadButton.outline(
            child: Text(l10n.reject),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          ShadButton(
            child: Text(l10n.approve),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ).then((value) {
      if (mounted) setState(() => _isApprovalDialogOpen = false);
      ref.read(chatProvider.notifier).approveTool(value ?? false);
    });
  }
}

class _ChatBody extends ConsumerWidget {
  const _ChatBody({
    required this.scrollController,
    required this.inputFocusNode,
    required this.autoScroll,
    required this.onModelPicker,
    required this.onMenuAction,
  });

  final ScrollController scrollController;
  final FocusNode inputFocusNode;
  final ChatAutoScrollController autoScroll;
  final VoidCallback onModelPicker;
  final void Function(String) onMenuAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLoading = ref.watch(chatProvider.select((s) => s.isLoading));
    final messages = ref.watch(chatProvider.select((s) => s.messages));
    final isStreaming = ref.watch(chatProvider.select((s) => s.isStreaming));
    final streamingLength = ref.watch(
      chatProvider.select((s) => s.streamingMessage?.content.length ?? 0),
    );
    final errorMessage = ref.watch(chatProvider.select((s) => s.errorMessage));
    final selectedModel = ref.watch(selectedModelProvider);
    final connectionStatus = ref.watch(connectionStatusProvider);
    final activeConversation = ref.watch(conv.activeConversationProvider);
    final isTemporary = ref.watch(chatProvider.select((s) => s.isTemporary));
    final personas = ref.watch(
      personasForConversationProvider(activeConversation?.personaId),
    );
    final hasPersonas = personas.isNotEmpty;
    final keyboardBottomInset = bottomKeyboardInset(context);
    final systemBottomInset = bottomSystemInset(context);
    // The token usage row (below the input box) is hidden while the
    // keyboard is open, same as the smart-reply chips, so only reserve
    // extra scroll space for it when it's actually visible.
    final effectiveBottomInset = keyboardBottomInset > 0
        ? 0.0
        : systemBottomInset + _tokenIndicatorRowHeight;

    final needsScroll = autoScroll.checkAndUpdate(
      messageCount: messages.length,
      streamingLength: streamingLength,
      isStreaming: isStreaming,
    );
    if (needsScroll) {
      autoScroll.scheduleAutoScroll(
        controller: scrollController,
        streaming: isStreaming,
      );
    }

    return Column(
      children: [
        ModelTopBar(selectedModel: selectedModel, onModelTap: onModelPicker),
        _ScreenAppBar(
          activeConversation: activeConversation,
          isDark: isDark,
          hasPersonas: hasPersonas,
          isTemporary: isTemporary,
          hasMessages: messages.isNotEmpty,
          onMenuAction: onMenuAction,
          onPersonaPicker: () => showPersonaPickerSheet(context),
          onChatModeAction: () => _handleChatModeAction(
            context,
            ref,
            hasMessages: messages.isNotEmpty,
            isTemporary: isTemporary,
          ),
        ),
        PersonaIndicator(
          personas: personas,
          onTap: () => showPersonaPickerSheet(context),
          onClear: () => _clearPersonas(ref),
        ),
        const NotificationPermissionBanner(),
        if (connectionStatus == ConnectionStatus.disconnected ||
            connectionStatus == ConnectionStatus.error)
          ConnectionBanner(status: connectionStatus),
        const TtsPlayerBar(),
        Expanded(
          child: DecoratedBox(
            decoration: isTemporary
                ? BoxDecoration(
                    color: isDark
                        ? const Color(0xFF15120C)
                        : const Color(0xFFFFFBF0),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF6B5A2E)
                          : const Color(0xFFE6C35C),
                      width: 2,
                    ),
                  )
                : const BoxDecoration(),
            child: Stack(
              children: [
                _MessageArea(
                isLoading: isLoading,
                messages: messages,
                activeConversation: activeConversation,
                errorMessage: errorMessage,
                selectedModel: selectedModel,
                isStreaming: isStreaming,
                scrollController: scrollController,
                effectiveBottomInset: effectiveBottomInset,
                keyboardBottomInset: keyboardBottomInset,
                onModelPicker: onModelPicker,
              ),
              _ChatBottomBar(
                isStreaming: isStreaming,
                keyboardBottomInset: keyboardBottomInset,
                inputFocusNode: inputFocusNode,
              ),
            ],
          ),
        ),
        ),
      ],
    );
  }
}

class _MessageArea extends ConsumerWidget {
  const _MessageArea({
    required this.isLoading,
    required this.messages,
    required this.activeConversation,
    this.errorMessage,
    required this.selectedModel,
    required this.isStreaming,
    required this.scrollController,
    required this.effectiveBottomInset,
    required this.keyboardBottomInset,
    required this.onModelPicker,
  });

  final bool isLoading;
  final List<Message> messages;
  final dynamic activeConversation;
  final String? errorMessage;
  final dynamic selectedModel;
  final bool isStreaming;
  final ScrollController scrollController;
  final double effectiveBottomInset;
  final double keyboardBottomInset;
  final VoidCallback onModelPicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (messages.isEmpty && activeConversation != null) {
      return CorruptedChatState(
        conversation: activeConversation,
        errorMessage: errorMessage,
        onStartNewChat: () =>
            ref.read(chatProvider.notifier).startNewConversation(),
      );
    }

    if (messages.isEmpty) {
      return EmptyState(
        onQuickPrompt: (prompt) =>
            ref.read(chatProvider.notifier).sendMessage(prompt),
        quickPrompts: [
          l10n.quick_write,
          l10n.quick_explain,
          l10n.quick_debug,
          l10n.quick_async,
        ],
        recentConversations: ref.watch(conv.recentConversationsProvider),
        onSeeAll: () => context.push(AppRoutes.chatHistory),
        selectedModel: selectedModel,
        onModelTap: onModelPicker,
        selectedPersonas: ref.watch(selectedPersonasProvider),
        onPersonaTap: () => showPersonaPickerSheet(
          context,
          mode: PersonaPickerMode.preselection,
        ),
      );
    }

    return MessageList(
      scrollController: scrollController,
      messages: messages,
      allMessages: ref.watch(chatProvider.select((s) => s.allMessages)),
      isStreaming: isStreaming,
      onRetry: (messageId) =>
          ref.read(chatProvider.notifier).retryMessage(messageId),
      onDelete: (messageId) =>
          ref.read(chatProvider.notifier).deleteMessage(messageId),
      onEdit: (messageId, currentContent) async {
        final result = await EditMessageDialog.showUserEdit(
          context,
          initialContent: currentContent,
        );
        if (result == null || result.content == currentContent) return;
        if (result.regenerate) {
          await ref
              .read(chatProvider.notifier)
              .editMessage(messageId, result.content);
        } else {
          await ref
              .read(chatProvider.notifier)
              .editMessageSaveOnly(messageId, result.content);
        }
      },
      onEditAssistant: (messageId, currentContent) async {
        final editL10n = AppLocalizations.of(context)!;
        final newContent = await EditMessageDialog.show(
          context,
          initialContent: currentContent,
          description: editL10n.edit_assistant_message_desc,
          saveLabel: editL10n.save,
        );
        if (newContent != null && newContent != currentContent) {
          await ref
              .read(chatProvider.notifier)
              .editAssistantMessage(messageId, newContent);
        }
      },
      onBranch: (messageId) =>
          ref.read(chatProvider.notifier).branchFromMessage(messageId),
      onContinue: (messageId) =>
          ref.read(chatProvider.notifier).continueFromMessage(messageId),
      onCycleVariant: (messageId, direction) => ref
          .read(chatProvider.notifier)
          .cycleMessageVariant(messageId, direction),
      onSave: (message) => showSaveMessageSheet(
        context,
        ref,
        message,
        isTemporaryChat: ref.read(chatProvider.select((s) => s.isTemporary)),
      ),
      onShare: (message) => ShareService.shareText(message.content),
      onGenerateResponse: () =>
          ref.read(chatProvider.notifier).generateResponseForLastUser(),
      onModelPicker: onModelPicker,
      onModelLongPress: (modelId) => showModelInfoSheet(context, ref, modelId),
      hasSmartReplies:
          !isStreaming &&
          keyboardBottomInset == 0 &&
          (ref.watch(smartRepliesProvider).asData?.value.isNotEmpty ?? false),
      bottomInset: effectiveBottomInset,
    );
  }
}

void _clearPersonas(WidgetRef ref) {
  final activeConv = ref.read(conv.activeConversationProvider);
  if (activeConv != null) {
    ref.read(conv.conversationsProvider.notifier).updatePersonas(
          activeConv.id,
          const [],
        );
  } else {
    ref.read(selectedPersonasProvider.notifier).clear();
  }
}

void _handleChatModeAction(
  BuildContext context,
  WidgetRef ref, {
  required bool hasMessages,
  required bool isTemporary,
}) {
  final l10n = AppLocalizations.of(context)!;

  if (!hasMessages) {
    ref.read(chatProvider.notifier).setTemporaryMode(!isTemporary);
    return;
  }

  if (isTemporary) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.exit_temporary_chat_title),
        content: Text(l10n.exit_temporary_chat_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              FocusManager.instance.primaryFocus?.unfocus();
              ref.read(chatProvider.notifier).startNewConversation();
            },
            child: Text(l10n.nav_new_chat),
          ),
        ],
      ),
    );
    return;
  }

  FocusManager.instance.primaryFocus?.unfocus();
  ref.read(chatProvider.notifier).startNewConversation();
}

class _ScreenAppBar extends ConsumerWidget {
  const _ScreenAppBar({
    required this.activeConversation,
    required this.isDark,
    required this.hasPersonas,
    required this.isTemporary,
    required this.hasMessages,
    required this.onMenuAction,
    required this.onPersonaPicker,
    required this.onChatModeAction,
  });

  final Conversation? activeConversation;
  final bool isDark;
  final bool hasPersonas;
  final bool isTemporary;
  final bool hasMessages;
  final void Function(String) onMenuAction;
  final VoidCallback onPersonaPicker;
  final VoidCallback onChatModeAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final mcpConfig = ref.watch(chatMcpConfigProvider);
    final isMcpEnabled = settings.mcpEnabled && mcpConfig.enabled;
    final messageSelectionMode = ref.watch(messageSelectionModeProvider);
    final selectedMessageIds = ref.watch(selectedMessageIdsProvider);

    if (messageSelectionMode) {
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () =>
                  ref.read(messageSelectionModeProvider.notifier).disable(),
            ),
            Expanded(
              child: Text(
                l10n.selected_count(selectedMessageIds.length),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.export_conversation,
              onPressed: selectedMessageIds.isEmpty
                  ? null
                  : () => _shareSelectedMessages(context, ref, selectedMessageIds),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: l10n.delete,
              onPressed: selectedMessageIds.isEmpty
                  ? null
                  : () => _deleteSelectedMessages(context, ref, selectedMessageIds),
            ),
          ],
        ),
      );
    }

    return Container(
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
            child: Text(
              _appBarTitle(l10n),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Stack(
            children: [
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedFilterHorizontal,
                  size: 24,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                onPressed: () =>
                    showChatSettingsSheet(context, initialTab: 'parameters'),
                tooltip: l10n.chat_parameters_tooltip,
              ),
              PositionedDirectional(
                top: 4,
                end: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isMcpEnabled ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                  child: const HugeIcon(
                    icon: HugeIcons.strokeRoundedTools,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          _ChatModeIconButton(
            hasMessages: hasMessages,
            isTemporary: isTemporary,
            isDark: isDark,
            onPressed: onChatModeAction,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: onMenuAction,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'new_chat',
                child: ListTile(
                  leading: const Icon(Icons.add),
                  title: Text(l10n.nav_new_chat),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (activeConversation != null && !isTemporary) ...[
                PopupMenuItem(
                  value: 'rename',
                  child: ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: Text(l10n.rename_conversation),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'move_to_folder',
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(l10n.move_to_folder),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              if (hasMessages) ...[
                PopupMenuItem(
                  value: 'export_chat',
                  child: ListTile(
                    leading: const Icon(Icons.upload_outlined),
                    title: Text(l10n.export_conversation),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: 'share_chat',
                  child: ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: Text(l10n.share_conversation),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              PopupMenuItem(
                value: 'persona',
                child: ListTile(
                  leading: Icon(
                    hasPersonas ? Icons.swap_horiz : Icons.smart_toy_outlined,
                  ),
                  title: Text(
                    hasPersonas ? l10n.change_persona : l10n.set_persona,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n.clear_conversation),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _appBarTitle(AppLocalizations l10n) {
    if (isTemporary) return l10n.temporary_chat;
    if (activeConversation?.title.isNotEmpty == true) {
      return activeConversation!.title;
    }
    return l10n.nav_new_chat;
  }

  Future<void> _shareSelectedMessages(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedIds,
  ) async {
    final messages = ref
        .read(chatProvider)
        .messages
        .where((m) => selectedIds.contains(m.id))
        .toList();
    if (messages.isEmpty) return;
    final text = ExportService.exportAsText(messages);
    ref.read(messageSelectionModeProvider.notifier).disable();
    if (!context.mounted) return;
    await showExportChoiceDialog(context, content: text);
  }

  void _deleteSelectedMessages(
    BuildContext context,
    WidgetRef ref,
    Set<String> selectedIds,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.delete_message_title),
          content: Text(l10n.selected_count(selectedIds.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                for (final id in selectedIds) {
                  await ref.read(chatProvider.notifier).deleteMessage(id);
                }
                ref.read(messageSelectionModeProvider.notifier).disable();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
  }
}

class _ChatModeIconButton extends StatelessWidget {
  const _ChatModeIconButton({
    required this.hasMessages,
    required this.isTemporary,
    required this.isDark,
    required this.onPressed,
  });

  final bool hasMessages;
  final bool isTemporary;
  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showGhost = !hasMessages || isTemporary;
    final ghostActive = isTemporary;

    if (showGhost) {
      final activeColor =
          isDark ? const Color(0xFFE6C35C) : const Color(0xFF9A7B1A);
      final inactiveColor =
          isDark ? Colors.white54 : Colors.black45;

      return IconButton(
        onPressed: onPressed,
        tooltip: ghostActive
            ? l10n.exit_temporary_chat_title
            : l10n.temporary_chat,
        icon: ghostActive
            ? Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: activeColor.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.ghost,
                  size: 20,
                  color: activeColor,
                ),
              )
            : Icon(
                LucideIcons.ghost,
                size: 22,
                color: inactiveColor,
              ),
      );
    }

    return IconButton(
      onPressed: onPressed,
      tooltip: l10n.nav_new_chat,
      icon: Icon(
        Icons.add_comment_outlined,
        size: 22,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }
}

class _ChatBottomBar extends ConsumerWidget {
  const _ChatBottomBar({
    required this.isStreaming,
    required this.keyboardBottomInset,
    required this.inputFocusNode,
  });

  final bool isStreaming;
  final double keyboardBottomInset;
  final FocusNode inputFocusNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTemporary = ref.watch(chatProvider.select((s) => s.isTemporary));
    final keyboardIncognito = isTemporary &&
        ref.watch(settingsProvider.select((s) => s.tempChatKeyboardIncognito));
    final totalTokenCount = ref.watch(
      conv.activeConversationProvider.select((c) => c?.totalTokenCount),
    );

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.1),
              Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
              Theme.of(context).scaffoldBackgroundColor,
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isStreaming && keyboardBottomInset == 0) ...[
              const SizedBox(height: 4),
              _SmartReplyChipsWrapper(),
            ],
            ChatInputBar(
              focusNode: inputFocusNode,
              isStreaming: isStreaming,
              keyboardIncognito: keyboardIncognito,
              onSend: (message, {attachments}) {
                ref
                    .read(chatProvider.notifier)
                    .sendMessage(message, attachments: attachments);
              },
              onStop: () => ref.read(chatProvider.notifier).cancelStream(),
            ),
            if (keyboardBottomInset == 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 6, end: 16),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _TokenUsageIndicator(
                    totalTokenCount: totalTokenCount ?? 0,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TokenUsageIndicator extends ConsumerWidget {
  const _TokenUsageIndicator({required this.totalTokenCount});

  final int totalTokenCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final liveContextLength =
        ref.watch(activeModelContextLengthProvider).value;
    final fallbackContextLength =
        ref.watch(settingsProvider.select((s) => s.contextLength));
    final int contextLength = liveContextLength ?? fallbackContextLength;

    // totalTokenCount only updates once a response finishes (it's the real
    // server-reported count), so while one is streaming in, grow the ring
    // with a rough chars-per-token estimate of the in-progress reply —
    // corrected back to the exact figure the moment the stream ends.
    final isStreaming = ref.watch(chatProvider.select((s) => s.isStreaming));
    final streamingLength = ref.watch(
      chatProvider.select((s) => s.streamingMessage?.content.length ?? 0),
    );
    final estimatedTokenCount = isStreaming
        ? totalTokenCount + (streamingLength / 4).round()
        : totalTokenCount;

    final ratio = contextLength > 0
        ? (estimatedTokenCount / contextLength).clamp(0.0, 1.0)
        : 0.0;
    final ringColor = ratio >= 0.9 ? Colors.red : theme.colorScheme.primary;

    return GestureDetector(
      onTap: () => _showTokenUsageSheet(context, contextLength, ratio),
      child: SizedBox(
        height: 16,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                value: ratio,
                strokeWidth: 2,
                backgroundColor: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(ringColor),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${(ratio * 100).round()}%',
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTokenUsageSheet(
    BuildContext context,
    int contextLength,
    double ratio,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final sheetTheme = Theme.of(ctx);
        final isDark = sheetTheme.brightness == Brightness.dark;
        final muted =
            isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.token_usage_title,
                  style: sheetTheme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _usageRow(l10n.total_tokens_label, '$totalTokenCount', muted),
                _usageRow(l10n.context_length, '$contextLength', muted),
                _usageRow(
                  l10n.usage_percent_label,
                  '${(ratio * 100).toStringAsFixed(1)}%',
                  muted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _usageRow(String label, String value, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: muted)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SmartReplyChipsWrapper extends ConsumerWidget {
  const _SmartReplyChipsWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SmartReplyChips(
      onSend: (message) {
        ref.read(chatProvider.notifier).sendMessage(message);
      },
    );
  }
}
