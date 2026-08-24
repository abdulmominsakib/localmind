import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cue/cue.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/enums.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../l10n/app_localizations.dart';

class OnboardingServerTypeScreen extends ConsumerStatefulWidget {
  const OnboardingServerTypeScreen({super.key});

  @override
  ConsumerState<OnboardingServerTypeScreen> createState() =>
      _OnboardingServerTypeScreenState();
}

class _OnboardingServerTypeScreenState
    extends ConsumerState<OnboardingServerTypeScreen> {
  ServerType? _selectedType;
  static final Uri _repoUrl = Uri.parse(
    'https://github.com/abdulmominsakib/localmind',
  );

  @override
  void initState() {
    super.initState();
    _selectedType = ServerType.lmStudio;
  }

  Future<void> _openRepoUrl() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      final launched = await launchUrl(
        _repoUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.could_not_open_github)),
        );
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.could_not_open_github)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                'assets/images/logo.webp',
                width: 24,
                height: 24,
              ),
            ),
            Text(
              l10n.onboarding_localmind,
              style: const TextStyle(letterSpacing: 2, fontSize: 14),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: () => _skipOnboarding(),
            label: Text(l10n.skip),
            icon: HugeIcon(icon: HugeIcons.strokeRoundedNext),
          ),
        ],
      ),
      body: Cue.onMount(
        motion: .smooth(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Actor(
                      acts: [.fadeIn(), .slideY(from: 0.08)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),
                          Text(
                            l10n.onboarding_connect_server,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.onboarding_connect_desc,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Actor(
                      delay: 60.ms,
                      acts: [.fadeIn(), .slideY(from: 0.08)],
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final crossAxisCount = constraints.maxWidth >= 560
                              ? 3
                              : 2;

                          return Column(
                            children: [
                              GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(top: 24),
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent: 144,
                                children: [
                                  _buildServerCard(
                                    type: ServerType.onDevice,
                                    title: l10n.server_type_on_device,
                                    subtitle: l10n.server_type_on_device_desc,
                                    iconWidget: HugeIcon(
                                      icon: HugeIcons.strokeRoundedSmartPhone01,
                                      color:
                                          _selectedType == ServerType.onDevice
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                    theme: theme,
                                  ),
                                  _buildServerCard(
                                    type: ServerType.lmStudio,
                                    title: l10n.server_type_lm_studio,
                                    subtitle: l10n.server_type_lm_studio_desc,
                                    iconWidget: HugeIcon(
                                      icon: HugeIcons
                                          .strokeRoundedComputerTerminal01,
                                      color:
                                          _selectedType == ServerType.lmStudio
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                    theme: theme,
                                  ),
                                  _buildServerCard(
                                    type: ServerType.openAICompatible,
                                    title: l10n.server_type_openai_display,
                                    subtitle: l10n.openai_compatible_api,
                                    iconWidget: HugeIcon(
                                      icon: HugeIcons.strokeRoundedApi,
                                      color:
                                          _selectedType ==
                                              ServerType.openAICompatible
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                    theme: theme,
                                  ),
                                  _buildServerCard(
                                    type: ServerType.ollama,
                                    title: l10n.server_type_ollama,
                                    subtitle: l10n.server_type_ollama_desc,
                                    iconWidget: HugeIcon(
                                      icon: HugeIcons.strokeRoundedRobot01,
                                      color: _selectedType == ServerType.ollama
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                    theme: theme,
                                  ),
                                  _buildServerCard(
                                    type: ServerType.ollamaCloud,
                                    title: l10n.server_type_ollama_cloud,
                                    subtitle: l10n.server_type_ollama_cloud_sub,
                                    iconWidget: HugeIcon(
                                      icon: HugeIcons.strokeRoundedAiCloud,
                                      color:
                                          _selectedType ==
                                              ServerType.ollamaCloud
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                    theme: theme,
                                  ),
                                  _buildServerCard(
                                    type: ServerType.openRouter,
                                    title: l10n.server_type_openrouter,
                                    subtitle: l10n.server_type_openrouter_sub,
                                    iconWidget: HugeIcon(
                                      icon: HugeIcons.strokeRoundedCloudServer,
                                      color:
                                          _selectedType == ServerType.openRouter
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                    theme: theme,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildMoreCard(
                                theme: theme,
                                title: l10n.add_more,
                                subtitle: l10n.on_github,
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            Actor(
              delay: 120.ms,
              acts: [.fadeIn(), .slideY(from: 0.08)],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    // Status Indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _selectedType != null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedType != null
                              ? l10n.ready_continue
                              : l10n.waiting_selection,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ShadButton(
                      width: double.infinity,
                      enabled: _selectedType != null,
                      onPressed: () {
                        if (_selectedType != null) {
                          if (_selectedType == ServerType.onDevice) {
                            context.push(AppRoutes.onboardingModelDownload);
                          } else {
                            context.push(
                              AppRoutes.onboardingSetup,
                              extra: _selectedType,
                            );
                          }
                        }
                      },
                      child: Text(
                        l10n.continue_action,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom,
                    ), // Reduced bottom padding slightly for small screens
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard({
    required ServerType type,
    required String title,
    required String subtitle,
    required Widget iconWidget,
    required ThemeData theme,
    bool disabled = false,
    String? disabledReason,
  }) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: disabled
          ? () {
              if (disabledReason != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(disabledReason),
                    backgroundColor: theme.colorScheme.error,
                  ),
                );
              }
            }
          : () {
              setState(() {
                _selectedType = type;
              });
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: disabled
              ? theme.colorScheme.surface.withValues(alpha: 0.5)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected && !disabled
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected && !disabled ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: IconTheme(
                    data: IconThemeData(
                      size: 18,
                      color: disabled
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                          : theme.colorScheme.onSurface,
                    ),
                    child: iconWidget,
                  ),
                ),
                const Spacer(),
                if (disabled)
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedLock,
                    size: 18,
                    color: Colors.orange,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
                color: disabled
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.0,
                fontSize: 9.5,
                color: disabled
                    ? Colors.orange.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreCard({
    required ThemeData theme,
    required String title,
    required String subtitle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openRepoUrl,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.surface,
                      theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.68,
                      ),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedAdd01,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 1.0,
                              fontSize: 9.5,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                end: 12,
                bottom: -8,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.06,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedGithub,
                      size: 60,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(settings.copyWith(hasCompletedOnboarding: true));
    if (mounted) {
      context.go(AppRoutes.home);
    }
  }

  void _skipOnboarding() {
    _completeOnboarding();
  }
}
