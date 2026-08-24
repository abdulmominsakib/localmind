import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/core/utils/system_insets.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/services/data_backup_service.dart';
import 'package:localmind/core/services/export_choice_dialog.dart';
import 'package:localmind/core/services/share_service.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/conversations/views/components/rename_conversation_dialog.dart';
import 'package:localmind/features/models/views/model_picker_sheet.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/tts/views/components/tts_player_bar.dart';
import '../data/export_service.dart';
import '../providers/chat_providers.dart';
import 'components/chat_auto_scroll_controller.dart';
import 'components/notification_permission_banner.dart';
import 'components/top_bar/connection_banner.dart';
import 'components/top_bar/persona_indicator.dart';
import 'components/top_bar/screen_app_bar.dart';
import 'components/message_list/message_area.dart';
import 'components/chat_bottom_bar.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/conversations/views/components/conversation_list.dart';
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
        ScreenAppBar(
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
                MessageArea(
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
                ChatBottomBar(
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

void _clearPersonas(WidgetRef ref) {
  final activeConv = ref.read(conv.activeConversationProvider);
  if (activeConv != null) {
    ref
        .read(conv.conversationsProvider.notifier)
        .updatePersonas(activeConv.id, const []);
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
