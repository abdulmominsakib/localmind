import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/folder_filter_bar.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/core/theme/colors.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/personas/data/models/persona.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/personas/utils/persona_prompt_utils.dart';
import 'package:localmind/l10n/app_localizations.dart';

enum PersonaPickerMode { conversation, preselection }

void showPersonaPickerSheet(
  BuildContext context, {
  PersonaPickerMode mode = PersonaPickerMode.conversation,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => PersonaPickerSheet(mode: mode),
  );
}

class PersonaPickerSheet extends ConsumerStatefulWidget {
  const PersonaPickerSheet({super.key, required this.mode});

  final PersonaPickerMode mode;

  @override
  ConsumerState<PersonaPickerSheet> createState() => _PersonaPickerSheetState();
}

class _PersonaPickerSheetState extends ConsumerState<PersonaPickerSheet> {
  late Set<String> _selectedIds;
  var _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _selectedIds = _initialSelectedIds().toSet();
      _initialized = true;
    }
  }

  List<String> _initialSelectedIds() {
    if (widget.mode == PersonaPickerMode.preselection) {
      return ref.read(selectedPersonasProvider).map((p) => p.id).toList();
    }
    final activeConv = ref.read(conv.activeConversationProvider);
    return PersonaPromptUtils.parsePersonaIds(activeConv?.personaId);
  }

  void _toggle(Persona persona, List<Persona> allPersonas) {
    setState(() {
      if (_selectedIds.contains(persona.id)) {
        _selectedIds.remove(persona.id);
      } else {
        _selectedIds.add(persona.id);
      }
    });
    _apply(allPersonas);
  }

  void _clear(List<Persona> allPersonas) {
    setState(() => _selectedIds.clear());
    _apply(allPersonas);
  }

  void _apply(List<Persona> allPersonas) {
    final selected = allPersonas
        .where((p) => _selectedIds.contains(p.id))
        .toList(growable: false);

    if (widget.mode == PersonaPickerMode.preselection) {
      ref.read(selectedPersonasProvider.notifier).setPersonas(selected);
    } else {
      final conversationId = ref.read(conv.activeConversationProvider)?.id;
      if (conversationId != null) {
        ref
            .read(conv.conversationsProvider.notifier)
            .updatePersonas(conversationId, selected);
      } else {
        ref.read(selectedPersonasProvider.notifier).setPersonas(selected);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final personasAsync = ref.watch(personasNotifierProvider);
    final selectedCategory = ref.watch(personaCategoryFilterProvider);
    final categories = [
      l10n.all,
      l10n.persona_category_general,
      l10n.persona_category_coding,
      l10n.persona_category_education,
      l10n.persona_category_creative,
    ];

    final allPersonas = personasAsync.value ?? const <Persona>[];
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.select_persona,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkPrimaryText
                            : AppColors.lightPrimaryText,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('persona_manage'),
                    onPressed: () => context.push(AppRoutes.personas),
                    style: TextButton.styleFrom(foregroundColor: muted),
                    child: Text(l10n.manage_personas),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                spacing: 8,
                children: [
                  for (final category in categories)
                    FolderPill(
                      key: ValueKey('persona_category_$category'),
                      label: category,
                      selected:
                          selectedCategory ==
                          (category == l10n.all ? null : category),
                      onTap: () => ref
                          .read(personaCategoryFilterProvider.notifier)
                          .setCategory(category == l10n.all ? null : category),
                    ),
                ],
              ),
            ),
            Flexible(
              child: personasAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error.toString(), textAlign: TextAlign.center),
                ),
                data: (allPersonas) {
                  final personas = selectedCategory == null
                      ? allPersonas
                      : allPersonas
                            .where((p) => p.category == selectedCategory)
                            .toList();
                  if (personas.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.no_personas_found,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: personas.length,
                    itemBuilder: (context, index) {
                      final persona = personas[index];
                      return PersonaPickerRow(
                        persona: persona,
                        selected: _selectedIds.contains(persona.id),
                        onTap: () => _toggle(persona, allPersonas),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                spacing: 10,
                children: [
                  if (_selectedIds.isNotEmpty)
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('persona_clear'),
                        onPressed: () => _clear(allPersonas),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(l10n.clear_personas),
                      ),
                    ),
                  Expanded(
                    flex: _selectedIds.isNotEmpty ? 1 : 2,
                    child: FilledButton(
                      key: const ValueKey('persona_done'),
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        shape: const StadiumBorder(),
                      ),
                      child: Text(
                        _selectedIds.isEmpty
                            ? l10n.done
                            : '${l10n.done} (${_selectedIds.length})',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One persona: emoji tile, name and description, and a round check.
class PersonaPickerRow extends StatelessWidget {
  const PersonaPickerRow({
    super.key,
    required this.persona,
    required this.selected,
    required this.onTap,
  });

  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final strong = isDark
        ? AppColors.darkPrimaryText
        : AppColors.lightPrimaryText;
    final muted = isDark ? AppColors.darkMutedText : AppColors.lightMutedText;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? (isDark ? AppColors.darkSurfaceCard : const Color(0xFFF4F4F5))
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? border : Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('persona_${persona.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurfaceInput
                        : const Color(0xFFEDEDEF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    persona.emoji,
                    style: const TextStyle(fontSize: 21),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        persona.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: strong,
                        ),
                      ),
                      if (persona.description?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 2),
                        Text(
                          persona.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: HugeIcon(
                    key: ValueKey(selected),
                    icon: selected
                        ? HugeIcons.strokeRoundedCheckmarkCircle02
                        : HugeIcons.strokeRoundedCircle,
                    size: 22,
                    color: selected ? strong : border,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
