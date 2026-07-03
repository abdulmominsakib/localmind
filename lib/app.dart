import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'l10n/app_localizations.dart';

import 'core/models/enums.dart';
import 'core/providers/app_providers.dart';
import 'core/routes/app_routes.dart';
import 'core/theme/app_theme.dart';
import 'features/chat/providers/chat_providers.dart';
import 'features/conversations/providers/conversation_providers.dart'
    as conv;
import 'features/chat/views/chat_screen.dart';
import 'features/conversations/views/chat_history_screen.dart';
import 'features/mcp/views/mcp_tools_screen.dart';
import 'features/on_device/views/model_manager_screen.dart';
import 'features/onboarding/screens/onboarding_language_screen.dart';
import 'features/onboarding/screens/onboarding_model_download_screen.dart';
import 'features/onboarding/screens/onboarding_notification_permission_screen.dart';
import 'features/onboarding/screens/onboarding_server_setup_screen.dart';
import 'features/onboarding/screens/onboarding_server_type_screen.dart';
import 'features/onboarding/screens/onboarding_theme_screen.dart';
import 'features/personas/views/create_persona_screen.dart';
import 'features/personas/views/persona_list_screen.dart';
import 'features/servers/data/models/server.dart';
import 'features/servers/views/add_server_screen.dart';
import 'features/servers/views/server_list_screen.dart';
import 'features/tts/views/tts_model_manager_screen.dart';
import 'features/saved_messages/views/saved_messages_screen.dart';
import 'features/settings/views/settings_screen.dart';
import 'features/lm_studio_catalog/views/lm_studio_model_browser_screen.dart';
import 'features/sidebar/sidebar_drawer.dart';
import 'features/sidebar/sidebar_widget.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final hasCompletedOnboarding = ref
          .read(settingsProvider)
          .hasCompletedOnboarding;
      final isGoingToOnboarding = state.uri.toString().startsWith(
        '/onboarding',
      );

      if (!hasCompletedOnboarding && !isGoingToOnboarding) {
        return AppRoutes.onboarding;
      }

      if (hasCompletedOnboarding && isGoingToOnboarding) {
        return AppRoutes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingLanguageScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingServerType,
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingServerTypeScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingSetup,
        pageBuilder: (context, state) {
          final serverType = state.extra as ServerType?;
          return MaterialPage(
            child: OnboardingServerSetupScreen(
              selectedType: serverType ?? ServerType.lmStudio,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.onboardingModelDownload,
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingModelDownloadScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingTheme,
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingThemeScreen()),
      ),
      GoRoute(
        path: AppRoutes.onboardingNotifications,
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingNotificationPermissionScreen()),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return AppShell(child: child);
        },
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ChatScreen()),
          ),
          GoRoute(
            path: AppRoutes.servers,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ServerListScreen()),
          ),
          GoRoute(
            path: AppRoutes.addServer,
            pageBuilder: (context, state) {
              final server = state.extra as Server?;
              return MaterialPage(child: AddServerScreen(editServer: server));
            },
          ),
          GoRoute(
            path: AppRoutes.personas,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PersonaListScreen()),
          ),
          GoRoute(
            path: AppRoutes.createPersona,
            pageBuilder: (context, state) {
              final persona = state.extra as dynamic;
              return MaterialPage(
                child: CreatePersonaScreen(editPersona: persona),
              );
            },
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsViews()),
          ),
          GoRoute(
            path: AppRoutes.chatHistory,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ChatHistoryScreen()),
          ),
          GoRoute(
            path: AppRoutes.mcpTools,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: McpToolsScreen()),
          ),
          GoRoute(
            path: AppRoutes.onDeviceModels,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: OnDeviceModelManagerScreen()),
          ),
          GoRoute(
            path: AppRoutes.ttsModels,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: TtsModelManagerScreen()),
          ),
          GoRoute(
            path: AppRoutes.savedMessages,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SavedMessagesScreen()),
          ),
          GoRoute(
            path: AppRoutes.lmStudioModelBrowser,
            pageBuilder: (context, state) {
              final server = state.extra as Server?;
              if (server == null) {
                return const MaterialPage(child: SizedBox.shrink());
              }
              return MaterialPage(
                child: LmStudioModelBrowserScreen(server: server),
              );
            },
          ),
        ],
      ),
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final appThemeType = ref.watch(themeModeProvider);
    final localeCode = ref.watch(settingsProvider.select((s) => s.localeCode));

    ThemeData theme = AppTheme.lightTheme;
    ThemeData darkTheme = AppTheme.darkTheme;
    ThemeMode themeMode = ThemeMode.system;

    var shadTheme = AppTheme.lightShadTheme;
    var shadDarkTheme = AppTheme.darkShadTheme;

    switch (appThemeType) {
      case AppThemeType.light:
        themeMode = ThemeMode.light;
        shadTheme = AppTheme.lightShadTheme;
        break;
      case AppThemeType.dark:
        themeMode = ThemeMode.dark;
        shadTheme = AppTheme.darkShadTheme;
        // Also ensure shadDarkTheme matches so there's no mismatch
        shadDarkTheme = AppTheme.darkShadTheme;
        break;
      case AppThemeType.claude:
        themeMode = ThemeMode.light; // Force light mode for claude basically
        theme = AppTheme.claudeTheme;
        shadTheme = AppTheme.claudeShadTheme;
        break;
      case AppThemeType.system:
        themeMode = ThemeMode.system;
        shadTheme = AppTheme.lightShadTheme;
        shadDarkTheme = AppTheme.darkShadTheme;
        break;
    }

    return ShadApp.custom(
      themeMode: themeMode,
      theme: shadTheme,
      darkTheme: shadDarkTheme,
      appBuilder: (context) {
        return MaterialApp.router(
          title: 'LocalMind',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          routerConfig: router,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('ar'),
            Locale('bn'),
            Locale('zh'),
            Locale('es'),
            Locale('hi'),
            Locale('it'),
            Locale('ja'),
            Locale('ru'),
          ],
          locale: localeCode != null ? Locale(localeCode) : null,
          localeResolutionCallback: (locale, supportedLocales) {
            if (localeCode != null) {
              final langLocale = Locale(localeCode);
              if (supportedLocales.contains(langLocale)) return langLocale;
            }
            for (final l in supportedLocales) {
              if (l.languageCode == locale?.languageCode) return l;
            }
            return const Locale('en');
          },
          builder: (context, child) {
            return ShadAppBuilder(child: child!);
          },
        );
      },
    );
  }
}

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static void openDrawer(BuildContext context) {
    Scaffold.of(context).openDrawer();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final location = GoRouterState.of(context).uri.path;
    final isHome = location == AppRoutes.home;
    final hasActiveChat = ref.watch(conv.activeConversationProvider) != null;

    return PopScope(
      canPop: isHome && !hasActiveChat,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isHome && hasActiveChat) {
          final origin = ref.read(chatOriginProvider);
          ref.read(chatOriginProvider.notifier).clear();
          switch (origin) {
            case ChatOrigin.history:
              context.go(AppRoutes.chatHistory);
            case ChatOrigin.savedMessages:
              context.go(AppRoutes.savedMessages);
            case ChatOrigin.none:
              ref.read(chatProvider.notifier).startNewConversation();
          }
          return;
        }
        if (!isHome) {
          context.go(AppRoutes.home);
        }
      },
      child: ShadResponsiveBuilder(
        builder: (context, breakpoint) {
          final isDesktop = breakpoint >= ShadTheme.of(context).breakpoints.md;

          if (isDesktop) {
            return Scaffold(
              body: Row(
                children: [
                  const SidebarWidget(),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: isDark
                        ? const Color(0xFF1A1A1A)
                        : const Color(0xFFE5E5E5),
                  ),
                  Expanded(
                    child: child,
                  ),
                ],
              ),
            );
          }

          return Scaffold(
            body: child,
            drawer: const ConversationDrawer(),
          );
        },
      ),
    );
  }
}
