import "package:localmind/core/theme/colors.dart";
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../../core/routes/app_routes.dart';
import '../data/models/persona.dart';
import '../providers/personas_providers.dart';

class PersonaListScreen extends ConsumerWidget {
  const PersonaListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final filteredPersonas = ref.watch(filteredPersonasProvider);
    final builtIn = filteredPersonas.where((p) => p.isBuiltIn).toList();
    final userCreated = filteredPersonas.where((p) => !p.isBuiltIn).toList();
    final selectedCategory = ref.watch(personaCategoryFilterProvider);
    final previewSystemPrompts = ref.watch(personaPreviewSystemPromptsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Column(
          children: [
            Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: topPadding + 8,
                bottom: 16,
              ),
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
                      l10n.personas_title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        previewSystemPrompts
                            ? Icons.visibility
                            : Icons.visibility_outlined,
                      ),
                      tooltip: l10n.preview_system_prompts,
                      onPressed: () => ref
                          .read(personaPreviewSystemPromptsProvider.notifier)
                          .toggle(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.personas_combine_hint,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.darkMutedText
                        : AppColors.lightMutedText,
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children:
                      [
                        l10n.all,
                        l10n.persona_category_general,
                        l10n.persona_category_coding,
                        l10n.persona_category_education,
                        l10n.persona_category_creative,
                      ].map((cat) {
                        final isActive =
                            selectedCategory == (cat == l10n.all ? null : cat);
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
                                  .setCategory(cat == l10n.all ? null : cat);
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
                    ? _EmptyState(isDark: isDark, l10n: l10n)
                    : ListView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        children: [
                          if (userCreated.isNotEmpty) ...[
                            _SectionLabel(label: l10n.persona_my_section, isDark: isDark),
                            ...userCreated.map(
                              (p) => _PersonaCard(
                                persona: p,
                                isDark: isDark,
                                l10n: l10n,
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
                            const SizedBox(height: 12),
                          ],
                          if (builtIn.isNotEmpty) ...[
                            _SectionLabel(label: l10n.persona_builtin_section, isDark: isDark),
                            ...builtIn.map(
                              (p) => _PersonaCard(
                                persona: p,
                                isDark: isDark,
                                l10n: l10n,
                                showSystemPrompt: previewSystemPrompts,
                                onLongPress: () => _showActions(
                                  context,
                                  ref,
                                  p,
                                  isBuiltIn: true,
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
          PositionedDirectional(
            bottom: 24,
            end: 24,
            child: FloatingActionButton(
              onPressed: () => context.push(AppRoutes.createPersona),
              child: const Icon(Icons.add),
            ),
          ),
      ],
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
        final sheetL10n = AppLocalizations.of(ctx)!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isBuiltIn)
                ListTile(
                  leading: const Icon(Icons.edit),
                  title: Text(sheetL10n.edit),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(AppRoutes.createPersona, extra: persona);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  sheetL10n.delete,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  showDialog(
                    context: context,
                    builder: (dCtx) {
                      final dlgL10n = AppLocalizations.of(dCtx)!;
                      return AlertDialog(
                        title: Text(dlgL10n.delete_persona_title(persona.name)),
                        content: Text(
                          isBuiltIn
                              ? dlgL10n.delete_builtin_persona_body
                              : dlgL10n.delete_persona_body,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: Text(dlgL10n.cancel),
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
                            child: Text(dlgL10n.delete),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(sheetL10n.clone_edit),
                onTap: () {
                  Navigator.pop(ctx);
                  final clone = ref
                      .read(personasNotifierProvider.notifier)
                      .clonePersona(persona.id);
                  clone.then((c) {
                    if (!context.mounted) return;
                    context.push(AppRoutes.createPersona, extra: c);
                  });
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
          color: isDark ? AppColors.darkMutedText : AppColors.lightMutedText,
        ),
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.isDark,
    required this.l10n,
    this.showSystemPrompt = false,
    this.onTap,
    this.onLongPress,
  });

  final Persona persona;
  final bool isDark;
  final AppLocalizations l10n;
  final bool showSystemPrompt;
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
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppColors.darkSurfaceCard : AppColors.lightBorder,
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
                            l10n.builtin_badge,
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
                    showSystemPrompt && persona.isBuiltIn
                        ? persona.systemPrompt
                        : (persona.description ??
                            persona.systemPrompt.substring(
                              0,
                              persona.systemPrompt.length.clamp(0, 60),
                            )),
                    style: TextStyle(
                      fontSize: showSystemPrompt && persona.isBuiltIn ? 12 : 13,
                      color: isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFF999999),
                      fontFamily: showSystemPrompt && persona.isBuiltIn
                          ? 'monospace'
                          : null,
                    ),
                    maxLines: showSystemPrompt && persona.isBuiltIn ? 8 : 1,
                    overflow: showSystemPrompt && persona.isBuiltIn
                        ? TextOverflow.fade
                        : TextOverflow.ellipsis,
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
  const _EmptyState({required this.isDark, required this.l10n});
  final bool isDark;
  final AppLocalizations l10n;

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
              l10n.no_personas_found,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.no_personas_desc,
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
