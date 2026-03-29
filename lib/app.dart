import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/app_providers.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/conversations/screens/conversation_drawer.dart';
import 'features/servers/screens/server_list_screen.dart';
import 'features/servers/screens/add_server_screen.dart';
import 'features/personas/screens/persona_list_screen.dart';
import 'features/personas/screens/create_persona_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/onboarding/screens/onboarding_server_type_screen.dart';
import 'features/onboarding/screens/onboarding_server_setup_screen.dart';
import 'features/onboarding/screens/onboarding_theme_screen.dart';
import 'core/routes/app_routes.dart';
import 'core/models/enums.dart';

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
            const NoTransitionPage(child: OnboardingServerTypeScreen()),
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
        path: AppRoutes.onboardingTheme,
        pageBuilder: (context, state) =>
            const MaterialPage(child: OnboardingThemeScreen()),
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
            path: AppRoutes.conversations,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ConversationDrawer()),
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
            pageBuilder: (context, state) =>
                const MaterialPage(child: CreatePersonaScreen()),
          ),
          GoRoute(
            path: AppRoutes.settings,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
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
          builder: (context, child) {
            return ShadAppBuilder(child: child!);
          },
        );
      },
    );
  }
}

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _getCurrentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location == '/' || location.isEmpty) return 0;
    if (location.startsWith('/conversations')) return 1;
    if (location.startsWith('/servers')) return 2;
    if (location.startsWith('/personas')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _onDestinationSelected(int index, BuildContext context) {
    Haptics.vibrate(HapticsType.light);
    switch (index) {
      case 0:
        context.go(AppRoutes.home);
        break;
      case 1:
        context.go(AppRoutes.conversations);
        break;
      case 2:
        context.go(AppRoutes.servers);
        break;
      case 3:
        context.go(AppRoutes.personas);
        break;
      case 4:
        context.go(AppRoutes.settings);
        break;
    }
  }

  static void openDrawer(BuildContext context) {
    Scaffold.of(context).openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _getCurrentIndex(context);

    return Scaffold(
      body: child,
      drawer: _NavigationDrawer(
        currentIndex: currentIndex,
        onDestinationSelected: (index) {
          Navigator.of(context).pop();
          _onDestinationSelected(index, context);
        },
      ),
    );
  }
}

class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer({
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  final int currentIndex;
  final void Function(int) onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDark
          ? const Color(0xFF0A0A0A)
          : const Color(0xFFFAFAFA),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.psychology,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'LocalMind',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _DrawerItem(
              iconData: HugeIcons.strokeRoundedMessageMultiple01,
              label: 'Chat',
              isSelected: currentIndex == 0,
              onTap: () => onDestinationSelected(0),
            ),
            _DrawerItem(
              iconData: HugeIcons.strokeRoundedTimer02,
              label: 'History',
              isSelected: currentIndex == 1,
              onTap: () => onDestinationSelected(1),
            ),
            _DrawerItem(
              iconData: HugeIcons.strokeRoundedServerStack01,
              label: 'Servers',
              isSelected: currentIndex == 2,
              onTap: () => onDestinationSelected(2),
            ),
            _DrawerItem(
              iconData: HugeIcons.strokeRoundedCompass01,
              label: 'Personas',
              isSelected: currentIndex == 3,
              onTap: () => onDestinationSelected(3),
            ),
            const Spacer(),
            const Divider(height: 1),
            _DrawerItem(
              iconData: HugeIcons.strokeRoundedSettings01,
              label: 'Settings',
              isSelected: currentIndex == 4,
              onTap: () => onDestinationSelected(4),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.iconData,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final List<List<dynamic>> iconData;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: HugeIcon(
          icon: iconData,
          size: 22,
          color: isSelected
              ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB))
              : (isDark ? const Color(0xFF888888) : const Color(0xFF666666)),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? const Color(0xFFA0A0A0) : const Color(0xFF666666)),
          ),
        ),
        selected: isSelected,
        selectedTileColor: isDark
            ? const Color(0xFF3B82F6).withAlpha(25)
            : const Color(0xFF2563EB).withAlpha(25),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
      ),
    );
  }
}
