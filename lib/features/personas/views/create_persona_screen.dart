import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../data/models/persona.dart';
import '../providers/personas_providers.dart';

class CreatePersonaScreen extends ConsumerStatefulWidget {
  final Persona? editPersona;

  const CreatePersonaScreen({super.key, this.editPersona});

  @override
  ConsumerState<CreatePersonaScreen> createState() =>
      _CreatePersonaScreenState();
}

class _CreatePersonaScreenState extends ConsumerState<CreatePersonaScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _promptController;
  late TextEditingController _tempController;
  late TextEditingController _topPController;

  late String _selectedEmoji;
  String? _selectedCategory;
  bool _showAdvanced = false;
  bool _isSaving = false;
  bool _showPreview = false;

  bool get _isEditing => widget.editPersona != null;

  static const _emojis = [
    '🤖',
    '🧑‍💻',
    '📐',
    '✍️',
    '📚',
    '✏️',
    '📋',
    '🎯',
    '🔍',
    '💡',
    '🎨',
    '🧪',
    '🔬',
    '📝',
    '🧠',
    '🎭',
    '🎵',
    '📊',
    '🌐',
    '💬',
    '🛠️',
    '🎓',
    '📖',
    '🧪',
    '🎮',
    '🗺️',
    '🤝',
    '⚡',
  ];

  static const _categories = ['General', 'Coding', 'Education', 'Creative'];

  @override
  void initState() {
    super.initState();
    final p = widget.editPersona;
    _nameController = TextEditingController(text: p?.name ?? '');
    _descriptionController = TextEditingController(text: p?.description ?? '');
    _promptController = TextEditingController(text: p?.systemPrompt ?? '');
    _selectedEmoji = p?.emoji ?? '🤖';
    _selectedCategory = p?.category;

    final params = p?.preferredParams;
    _tempController = TextEditingController(
      text: params != null && params['temperature'] != null
          ? params['temperature'].toString()
          : '',
    );
    _topPController = TextEditingController(
      text: params != null && params['topP'] != null
          ? params['topP'].toString()
          : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _promptController.dispose();
    _tempController.dispose();
    _topPController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isSaving = true);

    final notifier = ref.read(personasNotifierProvider.notifier);
    final name = _nameController.text.trim();
    final prompt = _promptController.text.trim();
    final desc = _descriptionController.text.trim();

    Map<String, dynamic>? params;
    final temp = double.tryParse(_tempController.text.trim());
    final topP = double.tryParse(_topPController.text.trim());
    if (temp != null || topP != null) {
      params = {};
      if (temp != null) params['temperature'] = temp;
      if (topP != null) params['topP'] = topP;
    }

    try {
      if (_isEditing) {
        await notifier.updatePersona(
          widget.editPersona!.copyWith(
            name: name,
            emoji: _selectedEmoji,
            systemPrompt: prompt,
            description: desc.isNotEmpty ? desc : null,
            category: _selectedCategory,
            preferredParams: params,
          ),
        );
      } else {
        await notifier.createPersona(
          name: name,
          emoji: _selectedEmoji,
          systemPrompt: prompt,
          description: desc.isNotEmpty ? desc : null,
          category: _selectedCategory,
          preferredParams: params,
        );
      }

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? l10n.persona_updated : l10n.persona_created,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.error_with_message(e.toString()),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? l10n.edit_persona : l10n.create_persona),
        leading: IconButton(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isEditing ? l10n.save : l10n.create_persona_button),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.emoji_label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _emojis.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final emoji = _emojis[index];
                  final isSelected = emoji == _selectedEmoji;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedEmoji = emoji),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark
                                  ? const Color(
                                      0xFF3B82F6,
                                    ).withValues(alpha: 0.2)
                                  : const Color(
                                      0xFF2563EB,
                                    ).withValues(alpha: 0.15))
                            : (isDark
                                  ? const Color(0xFF1F1F1F)
                                  : const Color(0xFFF5F5F5)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? (isDark
                                    ? const Color(0xFF3B82F6)
                                    : const Color(0xFF2563EB))
                              : (isDark
                                    ? const Color(0xFF3A3A3A)
                                    : const Color(0xFFE5E5E5)),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.name_label,
                hintText: l10n.my_persona_hint,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.name_required;
                if (v.trim().length > 50) return l10n.name_max_50;
                return null;
              },
              textInputAction: TextInputAction.next,
              maxLength: 50,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: InputDecoration(labelText: l10n.category_label),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: l10n.description_optional,
                hintText: l10n.description_hint,
              ),
              maxLength: 200,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.system_prompt,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      l10n.character_count_max(_promptController.text.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: _promptController.text.length > 4000
                            ? Colors.red
                            : (isDark
                                  ? const Color(0xFF666666)
                                  : const Color(0xFF999999)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: HugeIcon(
                        icon: _showPreview
                            ? HugeIcons.strokeRoundedPencilEdit02
                            : HugeIcons.strokeRoundedEye,
                        size: 18,
                      ),
                      tooltip: _showPreview ? l10n.edit : l10n.preview,
                      onPressed: () =>
                          setState(() => _showPreview = !_showPreview),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_showPreview)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1F1F1F)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF3A3A3A)
                        : const Color(0xFFE5E5E5),
                  ),
                ),
                child: Text(
                  _promptController.text.isEmpty
                      ? l10n.no_prompt_placeholder
                      : _promptController.text,
                  style: TextStyle(
                    fontSize: 14,
                    color: _promptController.text.isEmpty
                        ? (isDark
                              ? const Color(0xFF555555)
                              : const Color(0xFFBBBBBB))
                        : (isDark ? Colors.white : Colors.black),
                  ),
                ),
              )
            else
              TextFormField(
                controller: _promptController,
                decoration: InputDecoration(
                  hintText: l10n.prompt_hint,
                  alignLabelWithHint: true,
                ),
                maxLines: 8,
                minLines: 4,
                maxLength: 4000,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return l10n.prompt_required;
                  }
                  if (v.trim().length > 4000) return l10n.prompt_max_chars;
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 16),

            GestureDetector(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                children: [
                  HugeIcon(
                    icon: _showAdvanced
                        ? HugeIcons.strokeRoundedArrowUp01
                        : HugeIcons.strokeRoundedArrowDown01,
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF999999),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.advanced_settings,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? const Color(0xFF888888)
                          : const Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
            if (_showAdvanced) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tempController,
                      decoration: InputDecoration(
                        labelText: l10n.temperature_label,
                        hintText: l10n.temp_hint,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final val = double.tryParse(v.trim());
                        if (val == null || val < 0 || val > 2) {
                          return l10n.range_0_2;
                        } else {
                          return null;
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _topPController,
                      decoration: InputDecoration(
                        labelText: l10n.top_p_label,
                        hintText: l10n.top_p_hint,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final val = double.tryParse(v.trim());
                        if (val == null || val < 0 || val > 1) {
                          return l10n.range_0_1;
                        } else {
                          return null;
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSaving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        _isEditing
                            ? l10n.save_changes
                            : l10n.create_persona_button,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
