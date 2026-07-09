import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:cue/cue.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/routes/app_routes.dart';
import '../../../l10n/app_localizations.dart';

class _LanguageOption {
  final String code;
  final String nativeName;
  final String englishName;
  final String flag;
  final String flagAsset;
  final String countryCode;
  final String shortText;
  final List<Color> gradient;

  const _LanguageOption({
    required this.code,
    required this.nativeName,
    required this.englishName,
    required this.flag,
    required this.flagAsset,
    required this.countryCode,
    required this.shortText,
    required this.gradient,
  });
}

const _languages = [
  _LanguageOption(
    code: 'en',
    nativeName: 'English',
    englishName: 'English',
    flag: '🇺🇸',
    flagAsset: 'assets/images/flag_us.png',
    countryCode: 'US',
    shortText: 'En',
    gradient: [Color(0xFF6366F1), Color(0xFF4F46E5)],
  ),
  _LanguageOption(
    code: 'it',
    nativeName: 'Italiano',
    englishName: 'Italian',
    flag: '🇮🇹',
    flagAsset: 'assets/images/flag_it.png',
    countryCode: 'IT',
    shortText: 'It',
    gradient: [Color(0xFF71717A), Color(0xFF52525B)],
  ),
  _LanguageOption(
    code: 'es',
    nativeName: 'Español',
    englishName: 'Spanish',
    flag: '🇪🇸',
    flagAsset: 'assets/images/flag_es.png',
    countryCode: 'ES',
    shortText: 'Es',
    gradient: [Color(0xFFF59E0B), Color(0xFFD97706)],
  ),
  _LanguageOption(
    code: 'zh',
    nativeName: '中文',
    englishName: 'Chinese',
    flag: '🇨🇳',
    flagAsset: 'assets/images/flag_cn.png',
    countryCode: 'CN',
    shortText: 'Zh',
    gradient: [Color(0xFFEF4444), Color(0xFFDC2626)],
  ),
  _LanguageOption(
    code: 'zh_TW',
    nativeName: '繁體中文',
    englishName: 'Traditional Chinese',
    flag: '🇹🇼',
    flagAsset: 'assets/images/flag_tw.png',
    countryCode: 'TW',
    shortText: 'Zh-TW',
    gradient: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
  ),
  _LanguageOption(
    code: 'ar',
    nativeName: 'العربية',
    englishName: 'Arabic',
    flag: '🇸🇦',
    flagAsset: 'assets/images/flag_sa.png',
    countryCode: 'SA',
    shortText: 'Ar',
    gradient: [Color(0xFF10B981), Color(0xFF059669)],
  ),
  _LanguageOption(
    code: 'bn',
    nativeName: 'বাংলা',
    englishName: 'Bengali',
    flag: '🇧🇩',
    flagAsset: 'assets/images/flag_bd.png',
    countryCode: 'BD',
    shortText: 'Bn',
    gradient: [Color(0xFF06B6D4), Color(0xFF0891B2)],
  ),
  _LanguageOption(
    code: 'hi',
    nativeName: 'हिन्दी',
    englishName: 'Hindi',
    flag: '🇮🇳',
    flagAsset: 'assets/images/flag_in.png',
    countryCode: 'IN',
    shortText: 'Hi',
    gradient: [Color(0xFFEC4899), Color(0xFFDB2777)],
  ),
  _LanguageOption(
    code: 'ja',
    nativeName: '日本語',
    englishName: 'Japanese',
    flag: '🇯🇵',
    flagAsset: 'assets/images/flag_jp.png',
    countryCode: 'JP',
    shortText: 'Ja',
    gradient: [Color(0xFFF43F5E), Color(0xFFBE123C)],
  ),
  _LanguageOption(
    code: 'ru',
    nativeName: 'Русский',
    englishName: 'Russian',
    flag: '🇷🇺',
    flagAsset: 'assets/images/flag_ru.png',
    countryCode: 'RU',
    shortText: 'Ru',
    gradient: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
  ),
];

class OnboardingLanguageScreen extends ConsumerStatefulWidget {
  const OnboardingLanguageScreen({super.key});

  @override
  ConsumerState<OnboardingLanguageScreen> createState() =>
      _OnboardingLanguageScreenState();
}

class _OnboardingLanguageScreenState
    extends ConsumerState<OnboardingLanguageScreen> {
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    // Read the current settings locale code
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      setState(() {
        _selectedCode = settings.localeCode ?? 'en';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
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
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedNext,
              color: theme.colorScheme.primary,
              size: 20,
            ),
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
                    const SizedBox(height: 24),
                    Actor(
                      acts: [.fadeIn(), .slideY(from: 0.08)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.onboarding_welcome,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.onboarding_choose_language,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.onboarding_choose_language_desc,
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
                    const SizedBox(height: 32),
                    Actor(
                      delay: 60.ms,
                      acts: [.fadeIn(), .slideY(from: 0.08)],
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _languages.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final lang = _languages[index];
                          final isSelected = _selectedCode == lang.code;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedCode = lang.code;
                              });
                              // Dynamically apply settings localization update
                              ref
                                  .read(settingsProvider.notifier)
                                  .setLocaleCode(lang.code);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outline.withValues(
                                          alpha: 0.15,
                                        ),
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.15),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: Image.asset(
                                        lang.flagAsset,
                                        width: 48,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return Text(
                                                lang.flag,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          lang.nativeName,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${lang.englishName} • ${lang.shortText.toUpperCase()}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.outline
                                                  .withValues(alpha: 0.3),
                                        width: 2,
                                      ),
                                    ),
                                    child: isSelected
                                        ? const HugeIcon(
                                            icon: HugeIcons.strokeRoundedTick01,
                                            color: Colors.white,
                                            size: 14,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.ready_continue,
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
                      onPressed: () {
                        context.push(AppRoutes.onboardingServerType);
                      },
                      child: Text(
                        l10n.continue_action,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: MediaQuery.of(context).padding.bottom),
                  ],
                ),
              ),
            ),
          ],
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
