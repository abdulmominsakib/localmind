import 'package:cue/cue.dart';

import 'package:flutter/material.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/chat/utils/new_chat_presence.dart';
import 'package:localmind/features/chat/views/components/message_list/ascii_logo_view.dart';
import 'package:localmind/features/chat/views/components/message_list/new_chat_status_tags.dart';
import 'package:localmind/features/chat/views/components/message_list/quick_prompt_chips.dart';
import 'package:localmind/l10n/app_localizations.dart';

/// The new-chat screen: the active provider's logo in animated ASCII, what
/// happens to messages sent from here, and a row of starter prompts just
/// above the composer. The model is chosen from the app bar, personas from
/// the menu, and past chats from the drawer, so none of them are repeated
/// here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.presence,
    required this.serverName,
    required this.readiness,
    required this.onQuickPrompt,
    required this.quickPrompts,
    this.bottomInset = 0,
    this.keyboardOpen = false,
  });

  final NewChatPresence presence;

  /// The active server's name, as the user set it up.
  final String serverName;

  final NewChatReadiness readiness;

  final void Function(String) onQuickPrompt;
  final List<QuickPrompt> quickPrompts;

  /// Space the composer and system bars take below the content.
  final double bottomInset;

  /// Holds the logo still while the user is typing.
  final bool keyboardOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // 52 clears the composer and leaves a 12pt gap above it, so the
        // prompt row reads as part of the input.
        padding: .fromLTRB(0, 16, 0, 52 + bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 68 - bottomInset).clamp(
              0,
              double.infinity,
            ),
          ),
          child: Cue.onMount(
            motion: .smooth(),
            // spaceBetween with an empty first child centres the intro in
            // the room left above the prompt row.
            child: Column(
              mainAxisAlignment: .spaceBetween,
              children: [
                const SizedBox.shrink(),
                Padding(
                  padding: const .fromLTRB(28, 0, 28, 24),
                  child: NewChatIntro(
                    presence: presence,
                    serverName: serverName,
                    readiness: readiness,
                    keyboardOpen: keyboardOpen,
                  ),
                ),
                Actor(
                  delay: 180.ms,
                  acts: [.fadeIn(), .slideY(from: 0.2)],
                  child: QuickPromptChips(
                    prompts: quickPrompts,
                    onSelected: onQuickPrompt,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo, heading, the note on where messages go, and the status tags.
class NewChatIntro extends StatelessWidget {
  const NewChatIntro({
    super.key,
    required this.presence,
    required this.serverName,
    required this.readiness,
    this.keyboardOpen = false,
  });

  final NewChatPresence presence;
  final String serverName;
  final NewChatReadiness readiness;
  final bool keyboardOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    final provider = _providerLabel(l10n, presence.serverType);
    final server = serverName.trim().isEmpty ? provider ?? '' : serverName;
    final (headline, detail) = switch (presence.reach) {
      NewChatReach.none => (
        l10n.new_chat_no_server_headline,
        l10n.new_chat_no_server_detail,
      ),
      NewChatReach.onDevice => (
        l10n.new_chat_on_device_headline,
        l10n.new_chat_on_device_detail,
      ),
      NewChatReach.selfHosted => (
        l10n.new_chat_self_hosted_headline(server),
        l10n.new_chat_self_hosted_detail,
      ),
      NewChatReach.endpoint => (
        l10n.new_chat_self_hosted_headline(server),
        l10n.new_chat_endpoint_detail(server),
      ),
      NewChatReach.cloud => (
        l10n.new_chat_cloud_headline,
        presence.serverType == ServerType.ollamaCloud
            ? l10n.new_chat_ollama_cloud_detail
            : l10n.new_chat_router_detail(provider ?? server),
      ),
    };
    final status = switch (readiness) {
      NewChatReadiness.disconnected => l10n.new_chat_not_connected,
      NewChatReadiness.noModel => l10n.new_chat_no_model,
      NewChatReadiness.ready =>
        presence.reach == NewChatReach.onDevice
            ? l10n.new_chat_works_offline
            : l10n.ready,
    };

    return Column(
      mainAxisSize: .min,
      children: [
        Actor(
          acts: [.fadeIn(), .scale(from: 0.96)],
          child: AsciiLogoView(
            // A new key replays the reveal when the provider changes.
            key: ValueKey(presence.logo),
            logo: presence.logo,
            semanticLabel: provider ?? 'LocalMind',
            paused: keyboardOpen,
          ),
        ),
        const SizedBox(height: 26),
        Actor(
          delay: 60.ms,
          acts: [.fadeIn(), .slideY(from: 0.1)],
          child: Text.rich(
            TextSpan(
              text: '${l10n.new_chat_title}\n',
              children: [
                TextSpan(
                  text: headline,
                  style: TextStyle(color: muted),
                ),
              ],
            ),
            textAlign: .center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.6,
              color: primary,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Actor(
          delay: 100.ms,
          acts: [.fadeIn(), .slideY(from: 0.1)],
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              detail,
              textAlign: .center,
              style: TextStyle(fontSize: 15, height: 1.5, color: muted),
            ),
          ),
        ),
        if (presence.reach != NewChatReach.none) ...[
          const SizedBox(height: 20),
          Actor(
            delay: 140.ms,
            acts: [.fadeIn()],
            child: NewChatStatusTags(
              status: status,
              isReady: readiness == NewChatReadiness.ready,
              provider: provider,
            ),
          ),
        ],
      ],
    );
  }

  static String? _providerLabel(AppLocalizations l10n, ServerType? type) =>
      switch (type) {
        null => null,
        ServerType.onDevice => l10n.server_type_on_device_display,
        ServerType.lmStudio => l10n.server_type_lm_studio_display,
        ServerType.ollama => l10n.server_type_ollama_display,
        ServerType.ollamaCloud => l10n.server_type_ollama_cloud_display,
        ServerType.openAICompatible => l10n.server_type_openai_display,
        ServerType.openRouter => l10n.server_type_openrouter_display,
        ServerType.requesty => l10n.server_type_requesty_display,
      };
}
