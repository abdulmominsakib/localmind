import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:localmind/l10n/app_localizations.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/system_insets.dart';
import '../../chat/utils/image_upload_utils.dart';
import '../../conversations/providers/conversation_providers.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../personas/providers/personas_providers.dart';
import '../../servers/providers/server_providers.dart';
import '../data/models/app_settings.dart';
import 'data_backup_actions.dart';

class SettingsViews extends ConsumerWidget {
  const SettingsViews({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final currentTheme = ref.watch(themeModeProvider);
    final systemBottomInset = bottomSystemInset(context);
    final packageInfo = ref.watch(packageInfoProvider);
    final servers = (ref.watch(serversProvider).value ?? [])
        .map((server) => (server.id, server.name))
        .toList();
    final personas = (ref.watch(personasNotifierProvider).value ?? [])
        .map((persona) => (persona.id, '${persona.emoji} ${persona.name}'))
        .toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: topPadding + 8,
            bottom: 16,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
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
                l10n.settings_title,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 1080;
              final contentMaxWidth = useTwoColumns ? 1120.0 : 720.0;
              final horizontalPadding = constraints.maxWidth >= 720
                  ? 20.0
                  : 12.0;

              final appearanceCard = _SettingsSectionCard(
                title: l10n.settings_appearance,
                icon: Icons.palette_outlined,
                accent: const Color(0xFF8B5CF6),
                children: [
                  _ThemeToggle(ref: ref),
                  _LanguageSetting(
                    current: settings.localeCode,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setLocaleCode(value),
                  ),
                  _SliderSetting(
                    label: l10n.font_size,
                    value: settings.fontSize,
                    min: 12.0,
                    max: 24.0,
                    divisions: 12,
                    description: l10n.font_size_desc,
                    onChanged: (value) =>
                        ref.read(settingsProvider.notifier).setFontSize(value),
                    valueFormat: (value) => value.toStringAsFixed(0),
                    previewText: l10n.font_preview,
                  ),
                  _CodeThemeDropdown(
                    label: l10n.code_theme_dark,
                    current: settings.codeThemeDark,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setCodeThemeDark(value),
                  ),
                  _CodeThemeDropdown(
                    label: l10n.code_theme_light,
                    current: settings.codeThemeLight,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setCodeThemeLight(value),
                  ),
                ],
              );

              final ttsCard = _SettingsSectionCard(
                title: l10n.settings_tts,
                icon: Icons.graphic_eq_rounded,
                accent: const Color(0xFF0EA5E9),
                children: [
                  _EngineDropdown(
                    current: settings.ttsEngine,
                    onChanged: (value) =>
                        ref.read(settingsProvider.notifier).setTtsEngine(value),
                  ),
                  _SectionActionButton(
                    icon: Icons.record_voice_over_outlined,
                    label: l10n.manage_tts_models,
                    onPressed: () => context.push(AppRoutes.ttsModels),
                  ),
                  if (settings.ttsEngine != EngineId.system) ...[
                    _VoiceSelector(
                      engine: settings.ttsEngine,
                      currentVoiceId: settings.ttsVoiceId,
                      onChanged: (voice) => ref
                          .read(settingsProvider.notifier)
                          .setTtsVoiceId(voice?.id),
                    ),
                    _SliderSetting(
                      label: l10n.tts_speed,
                      value: settings.ttsSpeed,
                      min: 0.5,
                      max: 2.0,
                      divisions: 15,
                      description: l10n.tts_speed_desc,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setTtsSpeed(value),
                      valueFormat: (value) => '${value.toStringAsFixed(2)}x',
                    ),
                  ],
                  _ToggleSetting(
                    label: l10n.tts_process_markdown,
                    description: l10n.tts_process_markdown_desc,
                    value: settings.ttsProcessMarkdown,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setTtsProcessMarkdown(value),
                  ),
                  _TtsSkipSecondsSetting(
                    value: settings.ttsSkipSeconds,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setTtsSkipSeconds(value),
                  ),
                ],
              );

              final behaviorCard = _SettingsSectionCard(
                title: l10n.settings_behavior,
                icon: Icons.tune_rounded,
                accent: const Color(0xFF22C55E),
                children: [
                  _ToggleSetting(
                    label: l10n.streaming_responses,
                    value: settings.streamingEnabled,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setStreamingEnabled(value),
                  ),
                  _ToggleSetting(
                    label: l10n.auto_generate_titles,
                    value: settings.autoGenerateTitle,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setAutoGenerateTitle(value),
                  ),
                  _ToggleSetting(
                    label: l10n.send_on_enter,
                    value: settings.sendOnEnter,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setSendOnEnter(value),
                  ),
                  _ToggleSetting(
                    label: l10n.show_system_messages,
                    description: l10n.show_system_messages_desc,
                    value: settings.showSystemMessages,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setShowSystemMessages(value),
                  ),
                  _ToggleSetting(
                    label: l10n.show_system_messages_in_chat,
                    description: l10n.show_system_messages_in_chat_desc,
                    value: settings.showSystemMessagesInChat,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setShowSystemMessagesInChat(value),
                  ),
                  _ToggleSetting(
                    label: l10n.haptic_feedback,
                    value: settings.hapticFeedbackEnabled,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setHapticFeedback(value),
                  ),
                  _ToggleSetting(
                    label: l10n.enable_mcp,
                    value: settings.mcpEnabled,
                    badges: [_FeatureBadge(label: l10n.experimental_label)],
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setMcpEnabled(value),
                  ),
                  if (settings.mcpEnabled)
                    _ToggleSetting(
                      label: l10n.new_chat_mcp_default,
                      value: settings.newChatMcpEnabled,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setNewChatMcpEnabled(value),
                    ),
                  _ToggleSetting(
                    label: l10n.temp_chat_keyboard_incognito,
                    description: l10n.temp_chat_keyboard_incognito_desc,
                    value: settings.tempChatKeyboardIncognito,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setTempChatKeyboardIncognito(value),
                  ),
                  _ToggleSetting(
                    label: l10n.resume_last_chat,
                    description: l10n.resume_last_chat_desc,
                    value: settings.resumeLastChat,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setResumeLastChat(value),
                  ),
                  _ToggleSetting(
                    label: l10n.keep_persona_on_new_chat,
                    description: l10n.keep_persona_on_new_chat_desc,
                    value: settings.keepPersonaOnNewChat,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setKeepPersonaOnNewChat(value),
                  ),
                  _ToggleSetting(
                    label: l10n.role_swap_button_enabled,
                    description: l10n.role_swap_button_enabled_desc,
                    value: settings.roleSwapButtonEnabled,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setRoleSwapButtonEnabled(value),
                  ),
                  _ToggleSetting(
                    label: l10n.enable_image_compression,
                    description: l10n.enable_image_compression_desc,
                    value: settings.imageCompressionEnabled,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setImageCompressionEnabled(value),
                  ),
                  if (settings.imageCompressionEnabled)
                    _ImageCompressionLevelSetting(
                      value: settings.imageCompressionLevel,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setImageCompressionLevel(value),
                    ),
                ],
              );

              final onDeviceCard = _SettingsSectionCard(
                title: l10n.settings_on_device,
                icon: Icons.memory_rounded,
                accent: const Color(0xFFF97316),
                children: [
                  _ToggleSetting(
                    label: l10n.enable_smart_reply,
                    value: settings.smartReplyEnabled,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setSmartReplyEnabled(value),
                  ),
                  if (settings.smartReplyEnabled)
                    _ToggleSetting(
                      label: l10n.smart_replies_use_persona,
                      description: l10n.smart_replies_use_persona_desc,
                      value: settings.smartRepliesUsePersona,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setSmartRepliesUsePersona(value),
                    ),
                  _ToggleSetting(
                    label: l10n.ai_user_response_enabled,
                    description: l10n.ai_user_response_enabled_desc,
                    value: settings.aiUserResponseEnabled,
                    badges: [_FeatureBadge(label: l10n.experimental_label)],
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setAiUserResponseEnabled(value),
                  ),
                  _HuggingFaceTokenSetting(
                    currentToken: settings.huggingFaceToken,
                    onSave: (value) {
                      ref
                          .read(settingsProvider.notifier)
                          .setHuggingFaceToken(value);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            value == null || value.isEmpty
                                ? l10n.settings_huggingface_token_cleared
                                : l10n.settings_huggingface_token_set,
                          ),
                        ),
                      );
                    },
                  ),
                  _SectionActionButton(
                    icon: Icons.phone_android_rounded,
                    label: l10n.manage_on_device_models,
                    onPressed: () => context.push(AppRoutes.onDeviceModels),
                  ),
                  _ToggleSetting(
                    label: l10n.unload_models_before_load,
                    value: settings.unloadModelsBeforeLoad,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setUnloadModelsBeforeLoad(value),
                  ),
                  const _OnDeviceEngineStatusCard(),
                ],
              );

              final defaultsCard = _SettingsSectionCard(
                title: l10n.settings_default_server,
                icon: Icons.hub_outlined,
                accent: const Color(0xFF06B6D4),
                children: [
                  _DropdownSetting(
                    label: l10n.settings_default_server,
                    currentValue: settings.defaultServerId,
                    items: servers,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setDefaultServer(value),
                    icon: Icons.computer_rounded,
                  ),
                  _DropdownSetting(
                    label: l10n.settings_default_persona,
                    currentValue: settings.defaultPersonaId,
                    items: personas,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setDefaultPersona(value),
                    icon: Icons.smart_toy_outlined,
                  ),
                  const SizedBox(height: 8),
                  _SectionActionButton(
                    icon: Icons.restore_rounded,
                    label: l10n.restore_builtin_personas,
                    onPressed: () async {
                      await ref
                          .read(personasNotifierProvider.notifier)
                          .restoreBuiltInPersonas();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text(l10n.restore_builtin_personas_success),
                          ),
                        );
                      }
                    },
                  ),
                ],
              );

              final privacyCard = _SettingsSectionCard(
                title: l10n.settings_privacy,
                icon: Icons.lock_outline_rounded,
                accent: const Color(0xFF14B8A6),
                children: [
                  _ToggleSetting(
                    label: l10n.show_data_indicator,
                    value: settings.showDataIndicator,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setShowDataIndicator(value),
                  ),
                  _MutedCallout(message: l10n.privacy_info),
                ],
              );

              final dataCard = _SettingsSectionCard(
                title: l10n.settings_data_management,
                icon: Icons.restore_page_outlined,
                accent: const Color(0xFFEF4444),
                children: [
                  const DataBackupActions(),
                  const SizedBox(height: 8),
                  _DangerousAction(
                    label: l10n.delete_all_conversations,
                    icon: Icons.delete_outline_rounded,
                    onConfirm: () =>
                        ref.read(conversationsProvider.notifier).deleteAll(),
                  ),
                  _DangerousAction(
                    label: l10n.reset_settings_defaults,
                    icon: Icons.restore_rounded,
                    onConfirm: () =>
                        ref.read(settingsProvider.notifier).resetToDefaults(),
                  ),
                ],
              );

              final aboutCard = _SettingsSectionCard(
                title: l10n.settings_about,
                icon: Icons.info_outline_rounded,
                accent: const Color(0xFFF59E0B),
                children: [
                  _AboutPanel(
                    title:
                        '${l10n.app_name} v${packageInfo.value?.version ?? l10n.app_version} (${packageInfo.value?.buildNumber ?? ''})',
                    subtitle: l10n.onboarding_connect_desc.replaceAll(
                      '\n',
                      ' ',
                    ),
                    providers: [
                      l10n.server_type_lm_studio,
                      l10n.server_type_ollama,
                      l10n.server_type_openrouter,
                    ],
                    highlights: [
                      l10n.settings_on_device,
                      l10n.streaming_responses,
                      l10n.nav_personas,
                    ],
                    stack: const ['Flutter', 'Riverpod', 'shadcn_ui'],
                    openSource: l10n.open_source_desc,
                  ),
                ],
              );

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  24 + systemBottomInset,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SettingsHero(
                            settings: settings,
                            themeType: currentTheme,
                          ),
                          const SizedBox(height: 16),
                          if (useTwoColumns)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _SettingsSectionColumn(
                                    children: [
                                      appearanceCard,
                                      behaviorCard,
                                      defaultsCard,
                                      privacyCard,
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: _SettingsSectionColumn(
                                    children: [
                                      ttsCard,
                                      onDeviceCard,
                                      dataCard,
                                      aboutCard,
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            _SettingsSectionColumn(
                              children: [
                                appearanceCard,
                                ttsCard,
                                behaviorCard,
                                onDeviceCard,
                                defaultsCard,
                                privacyCard,
                                dataCard,
                                aboutCard,
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionColumn extends StatelessWidget {
  const _SettingsSectionColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _withVerticalSpacing(children, gap: 16),
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({required this.settings, required this.themeType});

  final AppSettings settings;
  final AppThemeType themeType;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final primary = _primaryColor(context);

    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _outlineColor(context, alpha: 0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.settings_title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.app_tagline,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _mutedColor(context),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeroStat(
                  label: l10n.theme,
                  value: _themeLabel(themeType, l10n),
                  icon: Icons.auto_awesome_rounded,
                ),
                _HeroStat(
                  label: l10n.settings_language,
                  value: _languageLabel(settings.localeCode, l10n),
                  icon: Icons.language_rounded,
                ),
                _HeroStat(
                  label: l10n.tts_engine,
                  value: _engineLabel(settings.ttsEngine, l10n),
                  icon: Icons.record_voice_over_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = _primaryColor(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _panelColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineColor(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: theme.textTheme.labelMedium?.copyWith(
              color: _mutedColor(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _outlineColor(context, alpha: 0.9)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._withVerticalSpacing(children, gap: 10),
          ],
        ),
      ),
    );
  }
}

class _SettingPanel extends StatelessWidget {
  const _SettingPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _panelColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _outlineColor(context)),
      ),
      child: child,
    );
  }
}

class _MutedCallout extends StatelessWidget {
  const _MutedCallout({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _SettingPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_moon_outlined,
            size: 18,
            color: _mutedColor(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _mutedColor(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel({
    required this.title,
    required this.subtitle,
    required this.providers,
    required this.highlights,
    required this.stack,
    required this.openSource,
  });

  final String title;
  final String subtitle;
  final List<String> providers;
  final List<String> highlights;
  final List<String> stack;
  final String openSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: _mutedColor(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _AboutLabel(label: l10n.app_tagline),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: providers
                .map(
                  (provider) =>
                      _AboutChip(label: provider, icon: Icons.hub_outlined),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          _AboutLabel(label: l10n.highlights_label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: highlights
                .map(
                  (highlight) => _AboutChip(
                    label: highlight,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          _AboutLabel(label: l10n.built_with_label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: stack
                .map(
                  (item) => _AboutChip(label: item, icon: Icons.code_rounded),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceColor(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _outlineColor(context, alpha: 0.8)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.open_in_new_rounded,
                  size: 15,
                  color: _mutedColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    openSource,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _mutedColor(context),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutLabel extends StatelessWidget {
  const _AboutLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: _mutedColor(context),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _AboutChip extends StatelessWidget {
  const _AboutChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _surfaceColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _outlineColor(context, alpha: 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _mutedColor(context)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _LanguageSetting extends StatelessWidget {
  const _LanguageSetting({required this.current, required this.onChanged});

  static const localeItems = <(String, String, String, String)>[
    ('en', 'English', 'assets/images/flag_us.png', '🇺🇸'),
    ('ja', '日本語', 'assets/images/flag_jp.png', '🇯🇵'),
    ('it', 'Italiano', 'assets/images/flag_it.png', '🇮🇹'),
    ('es', 'Español', 'assets/images/flag_es.png', '🇪🇸'),
    ('zh', '简体中文', 'assets/images/flag_cn.png', '🇨🇳'),
    ('zh_TW', '繁體中文', 'assets/images/flag_tw.png', '🇹🇼'),
    ('ar', 'العربية', 'assets/images/flag_sa.png', '🇸🇦'),
    ('bn', 'বাংলা', 'assets/images/flag_bd.png', '🇧🇩'),
    ('hi', 'हिन्दी', 'assets/images/flag_in.png', '🇮🇳'),
    ('ru', 'Русский', 'assets/images/flag_ru.png', '🇷🇺'),
  ];

  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: l10n.settings_language),
          const SizedBox(height: 10),
          _InputShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: current,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                borderRadius: BorderRadius.circular(16),
                dropdownColor: theme.colorScheme.surface,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings_suggest_outlined,
                          size: 18,
                          color: _mutedColor(context),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            l10n.language_system_default,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...localeItems.map(
                    (item) => DropdownMenuItem<String?>(
                      value: item.$1,
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 16,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _outlineColor(context, alpha: 0.8),
                                width: 0.6,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.asset(
                                item.$3,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Center(
                                    child: Text(
                                      item.$4,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              item.$2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.description,
    required this.onChanged,
    this.valueFormat,
    this.previewText,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String description;
  final ValueChanged<double> onChanged;
  final String Function(double)? valueFormat;
  final String? previewText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final displayValue = valueFormat != null
        ? valueFormat!(value)
        : value.toStringAsFixed(2);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  displayValue,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: primary,
              thumbColor: primary,
              overlayColor: primary.withValues(alpha: 0.12),
              inactiveTrackColor: _outlineColor(context, alpha: 0.6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _mutedColor(context),
              height: 1.4,
            ),
          ),
          if (previewText != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _outlineColor(context, alpha: 0.75)),
              ),
              child: Text(
                previewText!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: value.clamp(12.0, 24.0),
                  color: _mutedColor(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ToggleSetting extends StatelessWidget {
  const _ToggleSetting({
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.badges = const [],
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _SettingPanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ...badges,
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _ImageCompressionLevelSetting extends StatelessWidget {
  const _ImageCompressionLevelSetting({
    required this.value,
    required this.onChanged,
  });

  final ImageCompressionLevel value;
  final ValueChanged<ImageCompressionLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    String labelFor(ImageCompressionLevel level) {
      switch (level) {
        case ImageCompressionLevel.low:
          return l10n.image_compression_level_low;
        case ImageCompressionLevel.medium:
          return l10n.image_compression_level_medium;
        case ImageCompressionLevel.high:
          return l10n.image_compression_level_high;
      }
    }

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.image_compression_level,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.image_compression_level_desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ImageCompressionLevel.values.map((level) {
              final selected = value == level;
              return FilterChip(
                label: Text(labelFor(level)),
                selected: selected,
                onSelected: (_) => onChanged(level),
                showCheckmark: false,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TtsSkipSecondsSetting extends StatelessWidget {
  const _TtsSkipSecondsSetting({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  static const _options = [5, 10, 15, 30];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tts_skip_seconds,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.tts_skip_seconds_desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _options.map((seconds) {
              final selected = value == seconds;
              return FilterChip(
                label: Text(l10n.tts_skip_seconds_value(seconds)),
                selected: selected,
                onSelected: (_) => onChanged(seconds),
                showCheckmark: false,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  const _FeatureBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.22)),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: const Color(0xFFB45309),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.45,
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentTheme = ref.watch(themeModeProvider);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: l10n.theme),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final spacing = 8.0;
              final columns = constraints.maxWidth >= 700
                  ? 4
                  : constraints.maxWidth >= 420
                  ? 2
                  : 1;
              final itemWidth =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _ThemeOption(
                      label: l10n.theme_system,
                      icon: Icons.brightness_auto_rounded,
                      isSelected: currentTheme == AppThemeType.system,
                      onTap: () => ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(AppThemeType.system),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _ThemeOption(
                      label: l10n.theme_light,
                      icon: Icons.light_mode_rounded,
                      isSelected: currentTheme == AppThemeType.light,
                      onTap: () => ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(AppThemeType.light),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _ThemeOption(
                      label: l10n.theme_dark,
                      icon: Icons.dark_mode_rounded,
                      isSelected: currentTheme == AppThemeType.dark,
                      onTap: () => ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(AppThemeType.dark),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _ThemeOption(
                      label: l10n.theme_claude,
                      icon: Icons.auto_awesome_rounded,
                      isSelected: currentTheme == AppThemeType.claude,
                      onTap: () => ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(AppThemeType.claude),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withValues(alpha: 0.10)
                : theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? primary : _outlineColor(context, alpha: 0.8),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isSelected
                      ? primary.withValues(alpha: 0.14)
                      : _panelColor(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: isSelected ? primary : _mutedColor(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    color: isSelected ? primary : null,
                  ),
                ),
              ),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: isSelected ? primary : _mutedColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownSetting extends StatelessWidget {
  const _DropdownSetting({
    required this.label,
    required this.currentValue,
    required this.items,
    required this.onChanged,
    required this.icon,
  });

  final String label;
  final String? currentValue;
  final List<(String id, String name)> items;
  final ValueChanged<String?> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: label),
          const SizedBox(height: 10),
          _InputShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: currentValue,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                borderRadius: BorderRadius.circular(16),
                dropdownColor: theme.colorScheme.surface,
                hint: Text(
                  l10n.none_selected,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _mutedColor(context),
                  ),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.none),
                  ),
                  ...items.map(
                    (item) => DropdownMenuItem<String?>(
                      value: item.$1,
                      child: Row(
                        children: [
                          Icon(icon, size: 16, color: _mutedColor(context)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              item.$2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeThemeDropdown extends StatelessWidget {
  const _CodeThemeDropdown({
    required this.label,
    required this.current,
    required this.onChanged,
  });

  final String label;
  final SyntaxThemeName current;
  final ValueChanged<SyntaxThemeName> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: label),
          const SizedBox(height: 10),
          _InputShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SyntaxThemeName>(
                value: current,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                borderRadius: BorderRadius.circular(16),
                dropdownColor: theme.colorScheme.surface,
                items: SyntaxThemeName.values.map((codeTheme) {
                  final displayName = switch (codeTheme) {
                    SyntaxThemeName.light => l10n.theme_light,
                    SyntaxThemeName.dark => l10n.theme_dark,
                  };

                  return DropdownMenuItem<SyntaxThemeName>(
                    value: codeTheme,
                    child: Text(displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    onChanged(value);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.code_theme_desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _mutedColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _DangerousAction extends StatelessWidget {
  const _DangerousAction({
    required this.label,
    required this.icon,
    required this.onConfirm,
  });

  final String label;
  final IconData icon;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return OutlinedButton.icon(
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (dialogContext) {
            final dialogL10n = AppLocalizations.of(dialogContext)!;
            return AlertDialog(
              title: Text(label),
              content: Text(dialogL10n.cannot_undo),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(dialogL10n.cancel),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    onConfirm();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.label_completed(label))),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: Text(dialogL10n.confirm),
                ),
              ],
            );
          },
        );
      },
      icon: Icon(icon, color: Colors.red, size: 16),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(label, style: const TextStyle(color: Colors.red)),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: BorderSide(color: Colors.red.withValues(alpha: 0.55)),
        minimumSize: const Size(double.infinity, 44),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _SectionActionButton extends StatelessWidget {
  const _SectionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ShadButton.outline(
      onPressed: onPressed,
      width: double.infinity,
      leading: Icon(icon, size: 16),
      child: Align(alignment: Alignment.centerLeft, child: Text(label)),
    );
  }
}

class _EngineDropdown extends StatelessWidget {
  const _EngineDropdown({required this.current, required this.onChanged});

  final EngineId current;
  final ValueChanged<EngineId> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: l10n.tts_engine),
          const SizedBox(height: 10),
          _InputShell(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<EngineId>(
                value: current,
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                borderRadius: BorderRadius.circular(16),
                dropdownColor: theme.colorScheme.surface,
                items: [
                  _engineItem(
                    context,
                    EngineId.system,
                    l10n.tts_engine_system,
                    Icons.record_voice_over_rounded,
                  ),
                  _engineItem(
                    context,
                    EngineId.kitten,
                    l10n.tts_engine_kitten,
                    Icons.auto_awesome_rounded,
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onChanged(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<EngineId> _engineItem(
    BuildContext context,
    EngineId id,
    String label,
    IconData icon,
  ) {
    final meta = EngineMeta.forEngine(id);
    return DropdownMenuItem<EngineId>(
      value: id,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Color(meta.accentColor)),
          const SizedBox(width: 10),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _VoiceSelector extends StatelessWidget {
  const _VoiceSelector({
    required this.engine,
    required this.currentVoiceId,
    required this.onChanged,
  });

  final EngineId engine;
  final String? currentVoiceId;
  final ValueChanged<Voice?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final voices = voicesForEngine(engine);
    final resolvedCurrentVoiceId = voiceFromSettings(
      currentVoiceId,
      engine,
    )?.id;

    if (voices.isEmpty) {
      return const SizedBox.shrink();
    }

    final femaleVoices = voices.where((voice) => voice.gender == 'f').toList();
    final maleVoices = voices.where((voice) => voice.gender == 'm').toList();
    final otherVoices = voices
        .where((voice) => voice.gender != 'f' && voice.gender != 'm')
        .toList();

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: l10n.voice),
          if (femaleVoices.isNotEmpty) ...[
            const SizedBox(height: 8),
            _VoiceGroup(
              title: l10n.voice_female,
              voices: femaleVoices,
              selectedVoiceId: resolvedCurrentVoiceId,
              onChanged: onChanged,
            ),
          ],
          if (maleVoices.isNotEmpty) ...[
            const SizedBox(height: 12),
            _VoiceGroup(
              title: l10n.voice_male,
              voices: maleVoices,
              selectedVoiceId: resolvedCurrentVoiceId,
              onChanged: onChanged,
            ),
          ],
          if (otherVoices.isNotEmpty) ...[
            const SizedBox(height: 12),
            _VoiceGroup(
              title: l10n.voice_other,
              voices: otherVoices,
              selectedVoiceId: resolvedCurrentVoiceId,
              onChanged: onChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _VoiceGroup extends StatelessWidget {
  const _VoiceGroup({
    required this.title,
    required this.voices,
    required this.selectedVoiceId,
    required this.onChanged,
  });

  final String title;
  final List<Voice> voices;
  final String? selectedVoiceId;
  final ValueChanged<Voice?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _mutedColor(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: voices
              .map(
                (voice) => _VoiceChip(
                  voice: voice,
                  selected: voice.id == selectedVoiceId,
                  onTap: () => onChanged(voice),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _VoiceChip extends StatelessWidget {
  const _VoiceChip({
    required this.voice,
    required this.selected,
    required this.onTap,
  });

  final Voice voice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.10)
                : theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? primary : _outlineColor(context, alpha: 0.8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 16,
                color: selected ? primary : _mutedColor(context),
              ),
              const SizedBox(width: 8),
              Text(
                voice.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? primary : null,
                ),
              ),
              if (voice.language != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _panelColor(context),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    voice.language!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _mutedColor(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OnDeviceEngineStatusCard extends ConsumerWidget {
  const _OnDeviceEngineStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final engineState = ref.watch(onDeviceEngineProvider);

    final (
      Color accent,
      IconData icon,
      String message,
    ) = switch (engineState.status) {
      OnDeviceEngineStatus.loaded => (
        Colors.green,
        Icons.check_circle_rounded,
        l10n.model_loaded(
          engineState.loadedModelId ?? 'unknown',
          engineState.backend?.name ?? 'CPU',
        ),
      ),
      OnDeviceEngineStatus.loading => (
        Colors.blue,
        Icons.hourglass_top_rounded,
        l10n.loading,
      ),
      OnDeviceEngineStatus.error => (
        Colors.red,
        Icons.error_rounded,
        l10n.error_with_message(engineState.error ?? l10n.unknown_error),
      ),
      OnDeviceEngineStatus.notLoaded => (
        Colors.grey,
        Icons.info_outline_rounded,
        l10n.no_model_loaded,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingHeader extends StatelessWidget {
  const _SettingHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _InputShell extends StatelessWidget {
  const _InputShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _outlineColor(context, alpha: 0.8)),
      ),
      child: child,
    );
  }
}

class _HuggingFaceTokenSetting extends StatelessWidget {
  const _HuggingFaceTokenSetting({
    required this.currentToken,
    required this.onSave,
  });

  final String? currentToken;
  final ValueChanged<String?> onSave;

  bool get _hasToken => currentToken != null && currentToken!.isNotEmpty;

  String _maskedToken(String token) {
    if (token.length <= 6) return '••••••';
    return '${token.substring(0, 4)}••••••${token.substring(token.length - 4)}';
  }

  Future<void> _editToken(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentToken ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.edit_huggingface_token_dialog_title),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.huggingface_token_dialog_hint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: Text(l10n.clear_huggingface_token),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (result == null) return;
    onSave(result.isEmpty ? null : result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: l10n.settings_huggingface_token),
          const SizedBox(height: 6),
          Text(
            l10n.settings_huggingface_token_desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _mutedColor(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _InputShell(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Text(
                      _hasToken ? _maskedToken(currentToken!) : '—',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        color: _hasToken
                            ? theme.colorScheme.onSurface
                            : _mutedColor(context),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ShadButton.outline(
                onPressed: () => _editToken(context),
                child: Text(_hasToken ? l10n.edit : l10n.set_huggingface_token),
              ),
              if (_hasToken) ...[
                const SizedBox(width: 6),
                ShadButton.outline(
                  onPressed: () => onSave(null),
                  child: Text(l10n.clear_huggingface_token),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

List<Widget> _withVerticalSpacing(List<Widget> children, {double gap = 12}) {
  if (children.isEmpty) {
    return const [];
  }

  return [
    for (var index = 0; index < children.length; index++) ...[
      children[index],
      if (index != children.length - 1) SizedBox(height: gap),
    ],
  ];
}

Color _panelColor(BuildContext context) {
  final scheme = ShadTheme.of(context).colorScheme;
  return scheme.secondary;
}

Color _surfaceColor(BuildContext context) {
  return ShadTheme.of(context).colorScheme.card;
}

Color _primaryColor(BuildContext context) {
  return ShadTheme.of(context).colorScheme.primary;
}

Color _outlineColor(BuildContext context, {double alpha = 0.6}) {
  return ShadTheme.of(context).colorScheme.border.withValues(alpha: alpha);
}

Color _mutedColor(BuildContext context) {
  return ShadTheme.of(context).colorScheme.mutedForeground;
}

String _themeLabel(AppThemeType themeType, AppLocalizations l10n) {
  return switch (themeType) {
    AppThemeType.system => l10n.theme_system,
    AppThemeType.light => l10n.theme_light,
    AppThemeType.dark => l10n.theme_dark,
    AppThemeType.claude => l10n.theme_claude,
  };
}

String _engineLabel(EngineId engine, AppLocalizations l10n) {
  return switch (engine) {
    EngineId.system => l10n.tts_engine_system,
    EngineId.kitten => l10n.tts_engine_kitten,
    EngineId.piper => EngineMeta.piper.name,
  };
}

String _languageLabel(String? localeCode, AppLocalizations l10n) {
  if (localeCode == null) {
    return l10n.language_system_default;
  }

  for (final item in _LanguageSetting.localeItems) {
    if (item.$1 == localeCode) {
      return item.$2;
    }
  }

  return localeCode.toUpperCase();
}
