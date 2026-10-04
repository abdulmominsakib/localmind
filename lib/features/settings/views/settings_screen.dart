import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:localmind/l10n/app_localizations.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/services/android_assistant_service.dart';
import '../../../core/services/app_haptics.dart';
import '../../../core/services/crash_report_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/system_insets.dart';
import '../../chat/providers/chat_providers.dart';
import '../../chat/utils/image_upload_utils.dart';
import '../../conversations/providers/conversation_providers.dart';
import '../../models/data/models/model_info.dart';
import '../../on_device/providers/on_device_providers.dart';
import '../../personas/providers/personas_providers.dart';
import '../../servers/providers/server_providers.dart';
import '../data/models/app_settings.dart';
import 'data_backup_actions.dart';

/// Settings on one page: search and section chips up top, then compact
/// grouped lists. The chat options people change least live one level down
/// in [_MoreChatOptionsPage], and search still finds them.
class SettingsViews extends ConsumerStatefulWidget {
  const SettingsViews({super.key});

  @override
  ConsumerState<SettingsViews> createState() => _SettingsViewsState();
}

enum _SettingsSection { general, chat, voice, models, data, about }

class _SettingsViewsState extends ConsumerState<SettingsViews> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _sectionKeys = {
    for (final section in _SettingsSection.values) section: GlobalKey(),
  };

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(_SettingsSection section) {
    if (_search.text.isNotEmpty) {
      _search.clear();
      setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _sectionKeys[section]?.currentContext?.findRenderObject();
      if (target == null || !_scroll.hasClients) return;
      // Land the section's heading just below the status bar, not under it.
      final reveal = RenderAbstractViewport.of(
        target,
      ).getOffsetToReveal(target, 0).offset;
      final inset = MediaQuery.paddingOf(context).top + 8;
      _scroll.animateTo(
        (reveal - inset).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final systemBottomInset = bottomSystemInset(context);
    final packageInfo = ref.watch(packageInfoProvider);
    final assistantService = ref.watch(androidAssistantServiceProvider);
    final servers = (ref.watch(serversProvider).value ?? [])
        .map((server) => (server.id, server.name))
        .toList();
    final personas = (ref.watch(personasNotifierProvider).value ?? [])
        .map((persona) => (persona.id, '${persona.emoji} ${persona.name}'))
        .toList();

    // The default model dropdown lists models from the server used as the
    // default (the configured default server, falling back to the first one).
    final defaultServerId =
        settings.defaultServerId ??
        (servers.isNotEmpty ? servers.first.$1 : null);
    final availableModels = defaultServerId != null
        ? (ref.watch(availableModelsProvider(defaultServerId)).value ??
                  const <dynamic>[])
              .cast<ModelInfo>()
        : <ModelInfo>[];
    final models = availableModels.map((m) => (m.id, m.displayName)).toList();
    final isDefaultModelForServer =
        settings.defaultModelServerId != null &&
        settings.defaultModelServerId == defaultServerId;

    final sectionLabels = {
      _SettingsSection.general: l10n.settings_section_general,
      _SettingsSection.chat: l10n.settings_section_chat,
      _SettingsSection.voice: l10n.settings_section_voice,
      _SettingsSection.models: l10n.settings_section_models,
      _SettingsSection.data: l10n.settings_section_data,
      _SettingsSection.about: l10n.settings_about,
    };

    final general = _SettingsSectionCard(
      key: _sectionKeys[_SettingsSection.general],
      title: l10n.settings_section_general,
      children: [
        _ThemeToggle(ref: ref),
        _LanguageSetting(
          current: settings.localeCode,
          onChanged: notifier.setLocaleCode,
        ),
        _SliderSetting(
          label: l10n.font_size,
          value: settings.fontSize,
          min: 12.0,
          max: 24.0,
          divisions: 12,
          description: l10n.font_size_desc,
          onChanged: notifier.setFontSize,
          valueFormat: (value) => value.toStringAsFixed(0),
          previewText: l10n.font_preview,
        ),
        _ToggleSetting(
          label: l10n.haptic_feedback,
          value: settings.hapticFeedbackEnabled,
          onChanged: (value) {
            notifier.setHapticFeedback(value);
            if (value) ref.read(appHapticsProvider).medium();
          },
        ),
        _CodeThemeDropdown(
          label: l10n.code_theme_dark,
          current: settings.codeThemeDark,
          onChanged: notifier.setCodeThemeDark,
        ),
        _CodeThemeDropdown(
          label: l10n.code_theme_light,
          current: settings.codeThemeLight,
          onChanged: notifier.setCodeThemeLight,
        ),
      ],
    );

    final chat = _SettingsSectionCard(
      key: _sectionKeys[_SettingsSection.chat],
      title: l10n.settings_section_chat,
      children: [
        _ToggleSetting(
          label: l10n.streaming_responses,
          value: settings.streamingEnabled,
          onChanged: notifier.setStreamingEnabled,
        ),
        _ToggleSetting(
          label: l10n.send_on_enter,
          value: settings.sendOnEnter,
          onChanged: notifier.setSendOnEnter,
        ),
        _ToggleSetting(
          label: l10n.auto_generate_titles,
          value: settings.autoGenerateTitle,
          onChanged: notifier.setAutoGenerateTitle,
        ),
        _ToggleSetting(
          label: l10n.resume_last_chat,
          description: l10n.resume_last_chat_desc,
          value: settings.resumeLastChat,
          onChanged: notifier.setResumeLastChat,
        ),
        _ToggleSetting(
          label: l10n.keep_persona_on_new_chat,
          description: l10n.keep_persona_on_new_chat_desc,
          value: settings.keepPersonaOnNewChat,
          onChanged: notifier.setKeepPersonaOnNewChat,
        ),
        _SectionActionButton(
          icon: HugeIcons.strokeRoundedSlidersHorizontal,
          label: l10n.settings_more_chat_options,
          // Search reaches the options one level down through this row.
          keywords: _MoreChatOptionsPage.searchTerms(l10n),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const _MoreChatOptionsPage(),
            ),
          ),
        ),
      ],
    );

    final voice = _SettingsSectionCard(
      key: _sectionKeys[_SettingsSection.voice],
      title: l10n.settings_section_voice,
      children: [
        _EngineDropdown(
          current: settings.ttsEngine,
          onChanged: notifier.setTtsEngine,
        ),
        if (settings.ttsEngine != EngineId.system) ...[
          _VoiceSelector(
            engine: settings.ttsEngine,
            currentVoiceId: settings.ttsVoiceId,
            onChanged: (voice) => notifier.setTtsVoiceId(voice?.id),
          ),
          _SliderSetting(
            label: l10n.tts_speed,
            value: settings.ttsSpeed,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            description: l10n.tts_speed_desc,
            onChanged: notifier.setTtsSpeed,
            valueFormat: (value) => '${value.toStringAsFixed(2)}x',
          ),
        ],
        _ToggleSetting(
          label: l10n.settings_concise_voice_responses,
          description: l10n.settings_concise_voice_responses_desc,
          value: settings.conciseVoiceResponsesEnabled,
          onChanged: notifier.setConciseVoiceResponsesEnabled,
        ),
        _ToggleSetting(
          label: l10n.tts_process_markdown,
          description: l10n.tts_process_markdown_desc,
          value: settings.ttsProcessMarkdown,
          onChanged: notifier.setTtsProcessMarkdown,
        ),
        _TtsSkipSecondsSetting(
          value: settings.ttsSkipSeconds,
          onChanged: notifier.setTtsSkipSeconds,
        ),
        _SectionActionButton(
          icon: HugeIcons.strokeRoundedVoice,
          label: l10n.manage_tts_models,
          onPressed: () => context.push(AppRoutes.ttsModels),
        ),
      ],
    );

    final assistant = assistantService.isSupportedPlatform
        ? _SettingsSectionCard(
            title: l10n.settings_android_assistant,
            badges: [_FeatureBadge(label: l10n.beta_label)],
            children: const [_SettingPanel(child: _AndroidAssistantSetting())],
          )
        : null;

    final defaults = _SettingsSectionCard(
      key: _sectionKeys[_SettingsSection.models],
      title: l10n.settings_section_models,
      children: [
        _DropdownSetting(
          label: l10n.settings_default_server,
          currentValue: settings.defaultServerId,
          items: servers,
          onChanged: notifier.setDefaultServer,
          icon: HugeIcons.strokeRoundedComputer,
        ),
        _DropdownSetting(
          label: l10n.settings_default_model,
          description: l10n.settings_default_model_desc,
          currentValue: isDefaultModelForServer
              ? settings.defaultModelId
              : null,
          items: models,
          onChanged: (value) => notifier.setDefaultModel(
            serverId: defaultServerId,
            modelId: value,
          ),
          icon: HugeIcons.strokeRoundedSmartPhone01,
        ),
        _DropdownSetting(
          label: l10n.settings_default_persona,
          currentValue: settings.defaultPersonaId,
          items: personas,
          onChanged: notifier.setDefaultPersona,
          icon: HugeIcons.strokeRoundedRobot01,
        ),
        _SectionActionButton(
          icon: HugeIcons.strokeRoundedRefresh,
          label: l10n.restore_builtin_personas,
          onPressed: () async {
            await ref
                .read(personasNotifierProvider.notifier)
                .restoreBuiltInPersonas();
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(l10n.restore_builtin_personas_success)),
              );
            }
          },
        ),
      ],
    );

    final onDevice = _SettingsSectionCard(
      title: l10n.settings_on_device,
      children: [
        _SectionActionButton(
          icon: HugeIcons.strokeRoundedSmartPhone01,
          label: l10n.manage_on_device_models,
          onPressed: () => context.push(AppRoutes.onDeviceModels),
        ),
        _ToggleSetting(
          label: l10n.enable_smart_reply,
          value: settings.smartReplyEnabled,
          onChanged: notifier.setSmartReplyEnabled,
        ),
        if (settings.smartReplyEnabled)
          _ToggleSetting(
            label: l10n.smart_replies_use_persona,
            description: l10n.smart_replies_use_persona_desc,
            value: settings.smartRepliesUsePersona,
            onChanged: notifier.setSmartRepliesUsePersona,
          ),
        _ToggleSetting(
          label: l10n.ai_user_response_enabled,
          description: l10n.ai_user_response_enabled_desc,
          value: settings.aiUserResponseEnabled,
          badges: [_FeatureBadge(label: l10n.experimental_label)],
          onChanged: notifier.setAiUserResponseEnabled,
        ),
        _ToggleSetting(
          label: l10n.unload_models_before_load,
          value: settings.unloadModelsBeforeLoad,
          onChanged: notifier.setUnloadModelsBeforeLoad,
        ),
        _HuggingFaceTokenSetting(
          currentToken: settings.huggingFaceToken,
          onSave: (value) {
            notifier.setHuggingFaceToken(value);
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
        const _SettingPanel(child: _OnDeviceEngineStatusCard()),
      ],
    );

    final data = _SettingsSectionCard(
      key: _sectionKeys[_SettingsSection.data],
      title: l10n.settings_section_data,
      footer: l10n.privacy_info,
      children: [
        _ToggleSetting(
          label: l10n.show_data_indicator,
          value: settings.showDataIndicator,
          onChanged: notifier.setShowDataIndicator,
        ),
        _SectionActionButton(
          icon: HugeIcons.strokeRoundedCloud,
          label: l10n.cloud_sync,
          onPressed: () => context.push(AppRoutes.cloudSync),
        ),
        const _SettingPanel(child: DataBackupActions()),
        _DangerousAction(
          label: l10n.delete_all_conversations,
          icon: HugeIcons.strokeRoundedDelete01,
          onConfirm: () async {
            await ref.read(chatProvider.notifier).cancelAllGenerations();
            await ref.read(conversationsProvider.notifier).deleteAll();
          },
        ),
        _DangerousAction(
          label: l10n.reset_settings_defaults,
          icon: HugeIcons.strokeRoundedRefresh,
          onConfirm: notifier.resetToDefaults,
        ),
      ],
    );

    final about = _SettingsSectionCard(
      key: _sectionKeys[_SettingsSection.about],
      title: l10n.settings_about,
      children: [
        _AboutPanel(
          title:
              '${l10n.app_name} ${packageInfo.value?.version ?? l10n.app_version} (${packageInfo.value?.buildNumber ?? ''})',
          subtitle: l10n.open_source_desc,
        ),
        _SectionActionButton(
          icon: HugeIcons.strokeRoundedGithub,
          label: l10n.star_on_github,
          external: true,
          onPressed: () => _openRepository(context),
        ),
        _SectionActionButton(
          icon: HugeIcons.strokeRoundedAlertCircle,
          label: l10n.report_a_problem,
          external: true,
          onPressed: () => _openFeedbackIssue(context),
        ),
      ],
    );

    return _SettingsQuery(
      query: _search.text,
      child: CustomScrollView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverToBoxAdapter(
            child: _SettingsHeader(
              controller: _search,
              onQueryChanged: (_) => setState(() {}),
              sections: [
                for (final section in _SettingsSection.values)
                  (sectionLabels[section]!, () => _jumpTo(section)),
              ],
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + systemBottomInset),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      general,
                      chat,
                      voice,
                      ?assistant,
                      defaults,
                      onDevice,
                      data,
                      about,
                      if (_search.text.isEmpty) _PrivacyPolicyLink(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _repositoryUrl = 'https://github.com/abdulmominsakib/localmind';

/// Opens the GitHub repository; a failed or refused launch shows a message
/// rather than throwing.
Future<void> _openRepository(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = AppLocalizations.of(context)!.could_not_open_github;
  var launched = false;
  try {
    launched = await launchUrl(
      Uri.parse(_repositoryUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    launched = false;
  }
  if (!launched) {
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Menu button and large title, then search and the section chips.
class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.controller,
    required this.onQueryChanged,
    required this.sections,
  });

  final TextEditingController controller;
  final ValueChanged<String> onQueryChanged;
  final List<(String label, VoidCallback onTap)> sections;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = _mutedColor(context);
    final topPadding = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Builder(
                builder: (context) => IconButton(
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).openAppDrawerTooltip,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedMenu01),
                  onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              l10n.settings_title,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey('settings_search'),
              controller: controller,
              onChanged: onQueryChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 15.5),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: _trackColor(context),
                hintText: l10n.settings_search_hint,
                hintStyle: TextStyle(color: muted),
                prefixIcon: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedSearch01,
                    size: 18,
                    color: muted,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 38),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedCancelCircle,
                          size: 18,
                          color: muted,
                        ),
                        onPressed: () {
                          controller.clear();
                          onQueryChanged('');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                // Set every state so the app's input theme can't add a
                // border to the search field.
                border: _searchBorder,
                enabledBorder: _searchBorder,
                focusedBorder: _searchBorder,
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              itemCount: sections.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) =>
                  _SectionChip(label: sections[i].$1, onTap: sections[i].$2),
            ),
          ),
        ],
      ),
    );
  }
}

const _searchBorder = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(12)),
  borderSide: BorderSide.none,
);

class _SectionChip extends StatelessWidget {
  const _SectionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(999),
      side: BorderSide(color: _outlineColor(context, alpha: 0.9)),
    );
    return Material(
      color: _surfaceColor(context),
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chat options people change least, one level below Settings › Chat.
class _MoreChatOptionsPage extends ConsumerWidget {
  const _MoreChatOptionsPage();

  /// Labels on this page, so the main search can lead here.
  static List<String> searchTerms(AppLocalizations l10n) => [
    l10n.auto_collapse_thinking,
    l10n.show_system_messages_in_chat,
    l10n.show_system_messages,
    l10n.default_system_prompt,
    l10n.send_temperature_to_api,
    l10n.send_top_p_to_api,
    l10n.temp_chat_keyboard_incognito,
    l10n.role_swap_button_enabled,
    l10n.enable_image_compression,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings_more_chat_options)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + bottomSystemInset(context),
        ),
        children: [
          _SettingsSectionCard(
            title: l10n.settings_group_replies,
            children: [
              _ToggleSetting(
                label: l10n.auto_collapse_thinking,
                description: l10n.auto_collapse_thinking_desc,
                value: settings.autoCollapseThinking,
                onChanged: notifier.setAutoCollapseThinking,
              ),
              _ToggleSetting(
                label: l10n.show_system_messages_in_chat,
                description: l10n.show_system_messages_in_chat_desc,
                value: settings.showSystemMessagesInChat,
                onChanged: notifier.setShowSystemMessagesInChat,
              ),
            ],
          ),
          _SettingsSectionCard(
            title: l10n.settings_group_prompt,
            footer: l10n.send_sampling_params_desc,
            children: [
              _ToggleSetting(
                label: l10n.show_system_messages,
                description: l10n.show_system_messages_desc,
                value: settings.showSystemMessages,
                onChanged: notifier.setShowSystemMessages,
              ),
              _DefaultSystemPromptSetting(
                currentPrompt: settings.defaultSystemPrompt,
                onSave: notifier.setDefaultSystemPrompt,
              ),
              _ToggleSetting(
                label: l10n.send_temperature_to_api,
                value: settings.sendTemperature,
                onChanged: notifier.setSendTemperature,
              ),
              _ToggleSetting(
                label: l10n.send_top_p_to_api,
                value: settings.sendTopP,
                onChanged: notifier.setSendTopP,
              ),
            ],
          ),
          _SettingsSectionCard(
            title: l10n.settings_group_composer,
            children: [
              _ToggleSetting(
                label: l10n.role_swap_button_enabled,
                description: l10n.role_swap_button_enabled_desc,
                value: settings.roleSwapButtonEnabled,
                onChanged: notifier.setRoleSwapButtonEnabled,
              ),
              _ToggleSetting(
                label: l10n.temp_chat_keyboard_incognito,
                description: l10n.temp_chat_keyboard_incognito_desc,
                value: settings.tempChatKeyboardIncognito,
                onChanged: notifier.setTempChatKeyboardIncognito,
              ),
              _ToggleSetting(
                label: l10n.enable_image_compression,
                description: l10n.enable_image_compression_desc,
                value: settings.imageCompressionEnabled,
                onChanged: notifier.setImageCompressionEnabled,
              ),
              if (settings.imageCompressionEnabled)
                _ImageCompressionLevelSetting(
                  value: settings.imageCompressionLevel,
                  onChanged: notifier.setImageCompressionLevel,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AndroidAssistantSetting extends ConsumerStatefulWidget {
  const _AndroidAssistantSetting();

  @override
  ConsumerState<_AndroidAssistantSetting> createState() =>
      _AndroidAssistantSettingState();
}

class _AndroidAssistantSettingState
    extends ConsumerState<_AndroidAssistantSetting>
    with WidgetsBindingObserver {
  AndroidAssistantStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    final status = await ref.read(androidAssistantServiceProvider).getStatus();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _handleAction() async {
    if (_busy) return;
    setState(() => _busy = true);

    final service = ref.read(androidAssistantServiceProvider);
    try {
      if (_status == AndroidAssistantStatus.available) {
        await service.requestRole();
      } else {
        await service.openSettings();
      }
      await _refreshStatus();
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.assistant_error(e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = _status ?? AndroidAssistantStatus.unknown;
    final statusLabel = switch (status) {
      AndroidAssistantStatus.active => l10n.assistant_status_active,
      AndroidAssistantStatus.available => l10n.assistant_status_available,
      AndroidAssistantStatus.manual => l10n.assistant_status_manual,
      AndroidAssistantStatus.unsupported => l10n.assistant_status_unsupported,
      AndroidAssistantStatus.unknown => l10n.assistant_status_checking,
    };
    final actionLabel = status == AndroidAssistantStatus.available
        ? l10n.assistant_set_default
        : l10n.assistant_open_settings;

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.assistant_default_title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.assistant_default_description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ShadButton.outline(
            onPressed: _busy || status == AndroidAssistantStatus.unsupported
                ? null
                : _handleAction,
            width: double.infinity,
            leading: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const HugeIcon(
                    icon: HugeIcons.strokeRoundedSmartPhone01,
                    size: 16,
                  ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

abstract interface class _Searchable {
  List<String> searchTerms(AppLocalizations l10n);
}

/// The settings search query, read by every section.
class _SettingsQuery extends InheritedWidget {
  const _SettingsQuery({required this.query, required super.child});

  final String query;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsQuery>()?.query ?? '';

  @override
  bool updateShouldNotify(_SettingsQuery oldWidget) => oldWidget.query != query;
}

bool _matches(String query, Iterable<String?> terms) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return terms.any((t) => t != null && t.toLowerCase().contains(q));
}

/// A titled group of rows: a small heading over one rounded card, rows
/// split by hairlines. While searching, it keeps only matching rows and
/// hides itself when none match.
class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    super.key,
    required this.title,
    required this.children,
    this.badges = const [],
    this.footer,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> badges;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final query = _SettingsQuery.of(context);
    final titleMatches = _matches(query, [title]);
    final visible = query.trim().isEmpty || titleMatches
        ? children
        : [
            for (final child in children)
              if (child is _Searchable &&
                  _matches(query, (child as _Searchable).searchTerms(l10n)))
                child,
          ];
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _mutedColor(context),
                    ),
                  ),
                ),
                if (badges.isNotEmpty) ...[const SizedBox(width: 8), ...badges],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _surfaceColor(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _outlineColor(context, alpha: 0.9)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      color: _outlineColor(context, alpha: 0.7),
                    ),
                  visible[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                footer!,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: _mutedColor(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The padding every row in a section shares.
class _SettingPanel extends StatelessWidget {
  const _SettingPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
    );
  }
}

/// Title and optional description for a row, in list-row type.
class _RowLabel extends StatelessWidget {
  const _RowLabel({
    required this.label,
    this.description,
    this.badges = const [],
    this.color,
  });

  final String label;
  final String? description;
  final List<Widget> badges;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: color ?? theme.colorScheme.onSurface,
              ),
            ),
            ...badges,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: _mutedColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// The app's icon, name and version, with one line on what it is.
class _AboutPanel extends StatelessWidget implements _Searchable {
  const _AboutPanel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [title];

  @override
  Widget build(BuildContext context) {
    return _SettingPanel(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _outlineColor(context, alpha: 0.9)),
            ),
            child: Image.asset('assets/images/logo.webp'),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _RowLabel(label: title, description: subtitle),
          ),
        ],
      ),
    );
  }
}

class _LanguageSetting extends StatelessWidget implements _Searchable {
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
    ('tr', 'Türkçe', 'assets/images/flag_tr.png', '🇹🇷'),
    ('fr', 'Français', 'assets/images/flag_fr.png', '🇫🇷'),
    ('de', 'Deutsch', 'assets/images/flag_de.png', '🇩🇪'),
    ('pt', 'Português', 'assets/images/flag_br.png', '🇧🇷'),
    ('ko', '한국어', 'assets/images/flag_kr.png', '🇰🇷'),
  ];

  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [l10n.settings_language];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _InlineDropdown<String?>(
      label: l10n.settings_language,
      value: current,
      onChanged: onChanged,
      items: [
        (null, l10n.language_system_default, null),
        for (final item in localeItems)
          (
            item.$1,
            item.$2,
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.asset(
                item.$3,
                width: 22,
                height: 15,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Text(item.$4, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
      ],
    );
  }
}

class _SliderSetting extends StatelessWidget implements _Searchable {
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
  List<String> searchTerms(AppLocalizations l10n) => [label, description];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final displayValue = valueFormat != null
        ? valueFormat!(value)
        : value.toStringAsFixed(2);

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _RowLabel(label: label)),
              Text(
                displayValue,
                style: TextStyle(fontSize: 15, color: _mutedColor(context)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: onSurface,
              thumbColor: onSurface,
              overlayColor: onSurface.withValues(alpha: 0.08),
              inactiveTrackColor: _outlineColor(context, alpha: 0.9),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          if (previewText != null)
            Text(
              previewText!,
              style: TextStyle(
                fontSize: value.clamp(12.0, 24.0),
                height: 1.4,
                color: _mutedColor(context),
              ),
            )
          else
            Text(
              description,
              style: TextStyle(fontSize: 13, color: _mutedColor(context)),
            ),
        ],
      ),
    );
  }
}

class _ToggleSetting extends StatelessWidget implements _Searchable {
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
  List<String> searchTerms(AppLocalizations l10n) => [label, ?description];

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        child: _SettingPanel(
          child: Row(
            children: [
              Expanded(
                child: _RowLabel(
                  label: label,
                  description: description,
                  badges: badges,
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
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
          _RowLabel(
            label: l10n.image_compression_level,
            description: l10n.image_compression_level_desc,
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
  const _TtsSkipSecondsSetting({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  static const _options = [5, 10, 15, 30];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RowLabel(
            label: l10n.tts_skip_seconds,
            description: l10n.tts_skip_seconds_desc,
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

/// Theme as one segmented control: System, Light, Dark, Claude.
class _ThemeToggle extends StatelessWidget implements _Searchable {
  const _ThemeToggle({required this.ref});

  final WidgetRef ref;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [
    l10n.theme,
    l10n.theme_light,
    l10n.theme_dark,
    l10n.theme_claude,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(themeModeProvider);
    final options = [
      (AppThemeType.system, l10n.theme_system),
      (AppThemeType.light, l10n.theme_light),
      (AppThemeType.dark, l10n.theme_dark),
      (AppThemeType.claude, l10n.theme_claude),
    ];

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RowLabel(label: l10n.theme),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _trackColor(context),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                for (final (type, label) in options)
                  Expanded(
                    child: _ThemeOption(
                      label: label,
                      isSelected: current == type,
                      onTap: () => ref
                          .read(themeModeProvider.notifier)
                          .setThemeMode(type),
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

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? _surfaceColor(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? theme.colorScheme.onSurface
                  : _mutedColor(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label on the left and a compact dropdown showing the current value on
/// the right, in place of a header over a full-width field.
class _InlineDropdown<T> extends StatelessWidget {
  const _InlineDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.description,
    this.hint,
  });

  final String label;
  final String? description;
  final T value;
  final List<(T value, String text, Widget? leading)> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = _mutedColor(context);
    return _SettingPanel(
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _RowLabel(label: label, description: description),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 4,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                alignment: AlignmentDirectional.centerEnd,
                borderRadius: BorderRadius.circular(14),
                dropdownColor: theme.colorScheme.surface,
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowDown01,
                  size: 16,
                  color: muted,
                ),
                hint: hint == null
                    ? null
                    : Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(hint!, style: TextStyle(color: muted)),
                      ),
                selectedItemBuilder: (context) => [
                  for (final item in items)
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: muted),
                      ),
                    ),
                ],
                items: [
                  for (final item in items)
                    DropdownMenuItem<T>(
                      value: item.$1,
                      child: Row(
                        children: [
                          if (item.$3 != null) ...[
                            item.$3!,
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              item.$2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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

class _DropdownSetting extends StatelessWidget implements _Searchable {
  const _DropdownSetting({
    required this.label,
    required this.currentValue,
    required this.items,
    required this.onChanged,
    required this.icon,
    this.description,
  });

  final String label;
  final String? currentValue;
  final List<(String id, String name)> items;
  final ValueChanged<String?> onChanged;
  final List<List<dynamic>> icon;
  final String? description;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [label, ?description];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // A saved id that no longer exists (a deleted server, say) reads as none
    // rather than tripping the dropdown's value check.
    final known = items.any((item) => item.$1 == currentValue);
    return _InlineDropdown<String?>(
      label: label,
      description: description,
      value: known ? currentValue : null,
      onChanged: onChanged,
      items: [
        (null, l10n.none, null),
        for (final item in items) (item.$1, item.$2, null),
      ],
    );
  }
}

class _CodeThemeDropdown extends StatelessWidget implements _Searchable {
  const _CodeThemeDropdown({
    required this.label,
    required this.current,
    required this.onChanged,
  });

  final String label;
  final SyntaxThemeName current;
  final ValueChanged<SyntaxThemeName> onChanged;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [label];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _InlineDropdown<SyntaxThemeName>(
      label: label,
      value: current,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      items: [
        for (final codeTheme in SyntaxThemeName.values)
          (
            codeTheme,
            switch (codeTheme) {
              SyntaxThemeName.light => l10n.theme_light,
              SyntaxThemeName.dark => l10n.theme_dark,
            },
            null,
          ),
      ],
    );
  }
}

class _DangerousAction extends StatelessWidget implements _Searchable {
  const _DangerousAction({
    required this.label,
    required this.icon,
    required this.onConfirm,
  });

  final String label;
  final List<List<dynamic>> icon;
  final VoidCallback onConfirm;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [label];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const red = Color(0xFFDC2626);

    return InkWell(
      onTap: () {
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
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      child: _SettingPanel(
        child: Row(
          children: [
            HugeIcon(icon: icon, color: red, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: _RowLabel(label: label, color: red),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that opens something: icon, label, optional value, chevron.
class _SectionActionButton extends StatelessWidget implements _Searchable {
  const _SectionActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.keywords = const [],
    this.external = false,
  });

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onPressed;

  /// Extra words this row answers to, such as the options it leads to.
  final List<String> keywords;

  /// Opens outside the app, so it shows an arrow out instead of a chevron.
  final bool external;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [label, ...keywords];

  @override
  Widget build(BuildContext context) {
    final muted = _mutedColor(context);
    return InkWell(
      onTap: onPressed,
      child: _SettingPanel(
        child: Row(
          children: [
            HugeIcon(
              icon: icon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 12),
            Expanded(child: _RowLabel(label: label)),
            HugeIcon(
              icon: external
                  ? HugeIcons.strokeRoundedArrowUpRight01
                  : HugeIcons.strokeRoundedArrowRight01,
              size: 16,
              color: muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineDropdown extends StatelessWidget implements _Searchable {
  const _EngineDropdown({required this.current, required this.onChanged});

  final EngineId current;
  final ValueChanged<EngineId> onChanged;

  @override
  List<String> searchTerms(AppLocalizations l10n) => [l10n.tts_engine];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Widget dot(EngineId id, List<List<dynamic>> icon) => HugeIcon(
      icon: icon,
      size: 18,
      color: Color(EngineMeta.forEngine(id).accentColor),
    );
    return _InlineDropdown<EngineId>(
      label: l10n.tts_engine,
      value: current,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      items: [
        (
          EngineId.system,
          l10n.tts_engine_system,
          dot(EngineId.system, HugeIcons.strokeRoundedVoice),
        ),
        (
          EngineId.kitten,
          l10n.tts_engine_kitten,
          dot(EngineId.kitten, HugeIcons.strokeRoundedSparkles),
        ),
        (
          EngineId.piper,
          EngineMeta.piper.name,
          dot(EngineId.piper, HugeIcons.strokeRoundedCpu),
        ),
      ],
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
              HugeIcon(
                icon: selected
                    ? HugeIcons.strokeRoundedCheckmarkCircle01
                    : HugeIcons.strokeRoundedCircle,
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
      List<List<dynamic>> icon,
      String message,
    ) = switch (engineState.status) {
      OnDeviceEngineStatus.loaded => (
        Colors.green,
        HugeIcons.strokeRoundedCheckmarkCircle01,
        l10n.model_loaded(
          engineState.loadedModelId ?? 'unknown',
          engineState.backend?.name ?? 'CPU',
        ),
      ),
      OnDeviceEngineStatus.loading => (
        Colors.blue,
        HugeIcons.strokeRoundedClock01,
        l10n.loading,
      ),
      OnDeviceEngineStatus.error => (
        Colors.red,
        HugeIcons.strokeRoundedAlertCircle,
        l10n.error_with_message(engineState.error ?? l10n.unknown_error),
      ),
      OnDeviceEngineStatus.notLoaded => (
        Colors.grey,
        HugeIcons.strokeRoundedInformationCircle,
        l10n.no_model_loaded,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HugeIcon(icon: icon, size: 18, color: accent),
        const SizedBox(width: 12),
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

class _DefaultSystemPromptSetting extends StatelessWidget {
  const _DefaultSystemPromptSetting({
    required this.currentPrompt,
    required this.onSave,
  });

  final String currentPrompt;
  final ValueChanged<String> onSave;

  Future<void> _editPrompt(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: currentPrompt);
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.default_system_prompt),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: l10n.default_system_prompt_hint,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );

    controller.dispose();
    if (result == null) return;
    onSave(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasPrompt = currentPrompt.trim().isNotEmpty;

    return _SettingPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingHeader(label: l10n.default_system_prompt),
          const SizedBox(height: 6),
          Text(
            l10n.default_system_prompt_desc,
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
                      hasPrompt ? currentPrompt : '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: hasPrompt
                            ? theme.colorScheme.onSurface
                            : _mutedColor(context),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ShadButton.outline(
                onPressed: () => _editPrompt(context),
                child: Text(l10n.edit),
              ),
              if (hasPrompt) ...[
                const SizedBox(width: 6),
                ShadButton.outline(
                  onPressed: () => onSave(''),
                  child: Text(l10n.clear),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicyLink extends StatelessWidget {
  static final Uri _privacyUrl = Uri.parse(
    'https://momin.pro/privacy-policy-localmind/',
  );

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    try {
      final ok = await launchUrl(
        _privacyUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n?.failed_to_open_url(_privacyUrl.toString()) ??
                  'Failed to open URL: $_privacyUrl',
            ),
          ),
        );
      }
    } catch (e) {
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n?.failed_to_open_url(e.toString()) ??
                  'Failed to open URL: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: InkWell(
        onTap: () => _openPrivacyPolicy(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedShield01,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.privacy_policy,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
              HugeIcon(
                icon: HugeIcons.strokeRoundedShare01,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _panelColor(BuildContext context) {
  final scheme = ShadTheme.of(context).colorScheme;
  return scheme.secondary;
}

/// A soft grey that shows against both the page and the section cards.
Color _trackColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06);

Color _surfaceColor(BuildContext context) {
  return ShadTheme.of(context).colorScheme.card;
}

Color _outlineColor(BuildContext context, {double alpha = 0.6}) {
  return ShadTheme.of(context).colorScheme.border.withValues(alpha: alpha);
}

Color _mutedColor(BuildContext context) {
  return ShadTheme.of(context).colorScheme.mutedForeground;
}

Future<void> _openFeedbackIssue(BuildContext context) async {
  final uri = CrashReportService.instance.buildFeedbackIssueUrl();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n?.could_not_open_github ??
                'Could not open GitHub. Please try again later.',
          ),
        ),
      );
    }
  } catch (e) {
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n?.failed_to_open_url(e.toString()) ?? 'Failed to open URL: $e',
          ),
        ),
      );
    }
  }
}
