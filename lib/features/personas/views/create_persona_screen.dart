import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/features/personas/data/models/persona.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';

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
    if (!_formKey.currentState!.validate()) return;

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
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Persona updated' : 'Persona created'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Persona' : 'Create Persona'),
        leading: IconButton(
          icon: const Icon(Icons.close),
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
                : Text(_isEditing ? 'Save' : 'Create'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Emoji',
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
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'My Persona',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Name is required';
                if (v.trim().length > 50) return 'Max 50 characters';
                return null;
              },
              textInputAction: TextInputAction.next,
              maxLength: 50,
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What this persona does...',
              ),
              maxLength: 200,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'System Prompt',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${_promptController.text.length}/4000',
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
                      icon: Icon(
                        _showPreview ? Icons.edit : Icons.visibility,
                        size: 18,
                      ),
                      tooltip: _showPreview ? 'Edit' : 'Preview',
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
                      ? 'No prompt yet...'
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
                decoration: const InputDecoration(
                  hintText: 'You are a helpful assistant...',
                  alignLabelWithHint: true,
                ),
                maxLines: 8,
                minLines: 4,
                maxLength: 4000,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'System prompt is required';
                  }
                  if (v.trim().length > 4000) return 'Max 4000 characters';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 16),

            GestureDetector(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Row(
                children: [
                  Icon(
                    _showAdvanced ? Icons.expand_less : Icons.expand_more,
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF999999),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Advanced Settings',
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
                      decoration: const InputDecoration(
                        labelText: 'Temperature (0.0–2.0)',
                        hintText: '0.7',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final val = double.tryParse(v.trim());
                        if (val == null || val < 0 || val > 2) return '0.0–2.0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _topPController,
                      decoration: const InputDecoration(
                        labelText: 'Top P (0.0–1.0)',
                        hintText: '0.9',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final val = double.tryParse(v.trim());
                        if (val == null || val < 0 || val > 1) return '0.0–1.0';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save Changes' : 'Create Persona'),
            ),
          ],
        ),
      ),
    );
  }
}
