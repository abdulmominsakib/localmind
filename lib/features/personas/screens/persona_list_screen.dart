import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/providers/subscription_provider.dart';

class PersonaListScreen extends ConsumerWidget {
  const PersonaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasProvider);
    final userCreatedCount = personas.where((p) => !p.isBuiltIn).length;
    final isPremium = ref.watch(isPremiumUserProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0A0A0A)
                    : const Color(0xFFFAFAFA),
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
                    'Personas',
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
              child: Center(
                child: Text(
                  'Persona List - Placeholder\nCustom Personas: $userCreatedCount\nIs Premium: $isPremium',
                ),
              ),
            ),
          ],
        ),
        Positioned(
          bottom: 24,
          right: 24,
          child: FloatingActionButton(
            onPressed: () {
              if (!isPremium && userCreatedCount >= 3) {
                showShadDialog(
                  context: context,
                  builder: (context) => ShadDialog.alert(
                    title: const Text('Upgrade to Premium'),
                    description: const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'You have reached the limit of 3 custom personas for Basic users. Upgrade to Premium to create unlimited personas!',
                      ),
                    ),
                    actions: [
                      ShadButton.outline(
                        child: const Text('Cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      ShadButton(
                        child: const Text('Upgrade'),
                        onPressed: () {
                          ref
                              .read(isPremiumUserProvider.notifier)
                              .togglePremium();
                          Navigator.of(context).pop();
                          ShadToaster.of(context).show(
                            const ShadToast(
                              title: Text('Upgraded!'),
                              description: Text('You are now a premium user.'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              } else {
                context.push(AppRoutes.createPersona);
              }
            },
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
