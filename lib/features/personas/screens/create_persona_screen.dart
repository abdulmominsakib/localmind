import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/providers/subscription_provider.dart';

class CreatePersonaScreen extends ConsumerWidget {
  const CreatePersonaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personas = ref.watch(personasProvider);
    final userCreatedCount = personas.where((p) => !p.isBuiltIn).length;
    final isPremium = ref.watch(isPremiumUserProvider);

    if (!isPremium && userCreatedCount >= 3) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Create Persona'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('You have reached your limit of 3 custom personas.'),
              const SizedBox(height: 16),
              ShadButton(
                child: const Text('Upgrade to Premium'),
                onPressed: () {
                  ref.read(isPremiumUserProvider.notifier).togglePremium();
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Persona'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: const Center(
        child: Text('Create Persona - Placeholder'),
      ),
    );
  }
}
