import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      return ref
          .read(selectedPersonasProvider)
          .map((p) => p.id)
          .toList();
    }
    final activeConv = ref.read(conv.activeConversationProvider);
    return PersonaPromptUtils.parsePersonaIds(activeConv?.personaId);
  }

  void _toggle(Persona persona) {
    setState(() {
      if (_selectedIds.contains(persona.id)) {
        _selectedIds.remove(persona.id);
      } else {
        _selectedIds.add(persona.id);
      }
    });
  }

  void _clear() {
    setState(() => _selectedIds.clear());
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
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final personasAsync = ref.watch(personasNotifierProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.select_persona,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(AppRoutes.personas),
                  child: Text(l10n.manage_personas),
                ),
              ],
            ),
            if (_selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _selectedIds.map((id) {
                    final persona = personasAsync.value
                        ?.where((p) => p.id == id)
                        .firstOrNull;
                    if (persona == null) return const SizedBox.shrink();
                    return InputChip(
                      avatar: Text(persona.emoji, style: const TextStyle(fontSize: 14)),
                      label: Text(persona.name),
                      onDeleted: () => _toggle(persona),
                    );
                  }).toList(),
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
                data: (personas) {
                  if (personas.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.no_personas_found,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark
                              ? AppColors.darkMutedText
                              : AppColors.lightMutedText,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: personas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final persona = personas[index];
                      final selected = _selectedIds.contains(persona.id);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: selected
                              ? theme.colorScheme.primary.withValues(alpha: 0.15)
                              : (isDark
                                  ? AppColors.darkSurface
                                  : AppColors.lightSurface),
                          child: Text(persona.emoji, style: const TextStyle(fontSize: 20)),
                        ),
                        title: Text(
                          persona.name,
                          style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: persona.description != null
                            ? Text(
                                persona.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: Checkbox(
                          value: selected,
                          onChanged: (_) => _toggle(persona),
                        ),
                        onTap: () => _toggle(persona),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_selectedIds.isNotEmpty)
                  TextButton(
                    onPressed: _clear,
                    child: Text(l10n.remove_persona),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: personasAsync.maybeWhen(
                    data: (personas) => () => _apply(personas),
                    orElse: () => null,
                  ),
                  child: Text(l10n.done),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
