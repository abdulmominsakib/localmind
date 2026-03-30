import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/features/personas/data/models/persona.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';

class PersonaListScreen extends ConsumerWidget {
  const PersonaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredPersonas = ref.watch(filteredPersonasProvider);
    final builtIn = filteredPersonas.where((p) => p.isBuiltIn).toList();
    final userCreated = filteredPersonas.where((p) => !p.isBuiltIn).toList();
    final selectedCategory = ref.watch(personaCategoryFilterProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
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
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children:
                      [
                        'All',
                        'General',
                        'Coding',
                        'Education',
                        'Creative',
                      ].map((cat) {
                        final isActive =
                            selectedCategory == (cat == 'All' ? null : cat);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: FilterChip(
                            label: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isActive
                                    ? (isDark ? Colors.white : Colors.white)
                                    : (isDark
                                          ? const Color(0xFFAAAAAA)
                                          : const Color(0xFF666666)),
                              ),
                            ),
                            selected: isActive,
                            onSelected: (_) {
                              ref
                                  .read(personaCategoryFilterProvider.notifier)
                                  .setCategory(cat == 'All' ? null : cat);
                            },
                            selectedColor: isDark
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF2563EB),
                            backgroundColor: isDark
                                ? const Color(0xFF1F1F1F)
                                : const Color(0xFFF5F5F5),
                            side: BorderSide(
                              color: isActive
                                  ? (isDark
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF2563EB))
                                  : (isDark
                                        ? const Color(0xFF3A3A3A)
                                        : const Color(0xFFE5E5E5)),
                            ),
                            showCheckmark: false,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        );
                      }).toList(),
                ),
              ),
              Expanded(
                child: filteredPersonas.isEmpty
                    ? _EmptyState(isDark: isDark)
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        children: [
                          if (builtIn.isNotEmpty) ...[
                            _SectionLabel(label: 'BUILT-IN', isDark: isDark),
                            ...builtIn.map(
                              (p) => _PersonaCard(
                                persona: p,
                                isDark: isDark,
                                onLongPress: () => _showActions(
                                  context,
                                  ref,
                                  p,
                                  isBuiltIn: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (userCreated.isNotEmpty) ...[
                            _SectionLabel(label: 'MY PERSONAS', isDark: isDark),
                            ...userCreated.map(
                              (p) => _PersonaCard(
                                persona: p,
                                isDark: isDark,
                                onTap: () => context.push(
                                  AppRoutes.createPersona,
                                  extra: p,
                                ),
                                onLongPress: () => _showActions(
                                  context,
                                  ref,
                                  p,
                                  isBuiltIn: false,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 80),
                        ],
                      ),
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            right: 24,
            child: FloatingActionButton(
              onPressed: () => context.push(AppRoutes.createPersona),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  void _showActions(
    BuildContext context,
    WidgetRef ref,
    Persona persona, {
    required bool isBuiltIn,
  }) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isBuiltIn) ...[
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(AppRoutes.createPersona, extra: persona);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    showDialog(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        title: Text('Delete "${persona.name}"?'),
                        content: const Text('This cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              ref
                                  .read(personasNotifierProvider.notifier)
                                  .deletePersona(persona.id);
                              Navigator.pop(dCtx);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Clone & Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  final clone = ref
                      .read(personasNotifierProvider.notifier)
                      .clonePersona(persona.id);
                  clone.then(
                    (c) => context.push(AppRoutes.createPersona, extra: c),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isDark});
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: isDark ? const Color(0xFF888888) : const Color(0xFF999999),
        ),
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.isDark,
    this.onTap,
    this.onLongPress,
  });

  final Persona persona;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E5E5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFEDEDED),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  persona.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          persona.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (persona.isBuiltIn)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(
                                    0xFF3B82F6,
                                  ).withValues(alpha: 0.15)
                                : const Color(
                                    0xFF2563EB,
                                  ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Built-in',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFF60A5FA)
                                  : const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    persona.description ??
                        persona.systemPrompt.substring(
                          0,
                          persona.systemPrompt.length.clamp(0, 60),
                        ),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFF999999),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (persona.category != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFE8E8E8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        persona.category!,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? const Color(0xFFAAAAAA)
                              : const Color(0xFF777777),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark ? const Color(0xFF555555) : const Color(0xFFCCCCCC),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 64,
              color: isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 16),
            Text(
              'No personas found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first persona to customize AI behavior.',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? const Color(0xFF888888)
                    : const Color(0xFF999999),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
