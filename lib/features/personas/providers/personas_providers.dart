import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/features/personas/data/models/persona.dart';

final personaSearchQueryProvider =
    NotifierProvider<_PersonaSearchNotifier, String>(
      _PersonaSearchNotifier.new,
    );

class _PersonaSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String q) => state = q;
  void clear() => state = '';
}

final personaCategoryFilterProvider =
    NotifierProvider<_CategoryFilterNotifier, String?>(
      _CategoryFilterNotifier.new,
    );

class _CategoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setCategory(String? cat) => state = cat;
}

final personasNotifierProvider =
    NotifierProvider<PersonasNotifier, List<Persona>>(PersonasNotifier.new);

class PersonasNotifier extends Notifier<List<Persona>> {
  Box<Persona> get _box => ref.read(personasBoxProvider);

  @override
  List<Persona> build() {
    _seedIfEmpty();
    return _box.values.toList()..sort((a, b) {
      if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
      return a.name.compareTo(b.name);
    });
  }

  void _seedIfEmpty() {
    if (_box.isEmpty) {
      for (final preset in _builtInPersonas) {
        _box.put(preset.id, preset);
      }
      state = _box.values.toList()
        ..sort((a, b) {
          if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
          return a.name.compareTo(b.name);
        });
    }
  }

  Future<Persona> createPersona({
    required String name,
    required String emoji,
    required String systemPrompt,
    String? description,
    String? category,
    Map<String, dynamic>? preferredParams,
  }) async {
    final now = DateTime.now();
    final persona = Persona(
      id: now.millisecondsSinceEpoch.toString(),
      name: name,
      emoji: emoji,
      systemPrompt: systemPrompt,
      description: description,
      isBuiltIn: false,
      createdAt: now,
      updatedAt: now,
      category: category,
      preferredParams: preferredParams,
    );
    await _box.put(persona.id, persona);
    state = _box.values.toList()
      ..sort((a, b) {
        if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return persona;
  }

  Future<void> updatePersona(Persona updated) async {
    final persona = updated.copyWith(updatedAt: DateTime.now());
    await _box.put(persona.id, persona);
    state = _box.values.toList()
      ..sort((a, b) {
        if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
        return a.name.compareTo(b.name);
      });
  }

  Future<void> deletePersona(String id) async {
    final persona = _box.get(id);
    if (persona != null && persona.isBuiltIn) return;
    await _box.delete(id);
    state = _box.values.toList()
      ..sort((a, b) {
        if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
        return a.name.compareTo(b.name);
      });
  }

  Future<Persona> clonePersona(String id) async {
    final original = _box.get(id);
    if (original == null) throw Exception('Persona not found');

    final now = DateTime.now();
    final clone = Persona(
      id: now.millisecondsSinceEpoch.toString(),
      name: '${original.name} (Copy)',
      emoji: original.emoji,
      systemPrompt: original.systemPrompt,
      description: original.description,
      isBuiltIn: false,
      createdAt: now,
      updatedAt: now,
      category: original.category,
      preferredParams: original.preferredParams != null
          ? Map<String, dynamic>.from(original.preferredParams!)
          : null,
    );
    await _box.put(clone.id, clone);
    state = _box.values.toList()
      ..sort((a, b) {
        if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    return clone;
  }

  static final List<Persona> _builtInPersonas = [
    Persona(
      id: 'builtin-general',
      name: 'General Assistant',
      emoji: '🤖',
      systemPrompt:
          'You are a helpful, knowledgeable AI assistant. Provide clear, accurate, and concise responses. When you\'re not sure about something, say so. Use markdown formatting for structured responses.',
      description: 'Helpful, knowledgeable assistant',
      isBuiltIn: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      category: 'General',
    ),
    Persona(
      id: 'builtin-code',
      name: 'Code Assistant',
      emoji: '🧑‍💻',
      systemPrompt:
          'You are an expert software engineer. Help with coding questions, debugging, code reviews, and architecture decisions. Always provide code examples with proper syntax highlighting. Explain your reasoning. Follow best practices and mention potential pitfalls. When writing code, include comments for complex logic.',
      description: 'Expert software engineer',
      isBuiltIn: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      category: 'Coding',
    ),
    Persona(
      id: 'builtin-math',
      name: 'Math Tutor',
      emoji: '📐',
      systemPrompt:
          'You are a patient and thorough math tutor. Explain concepts step by step, starting from fundamentals. Use examples to illustrate abstract concepts. When solving problems, show your work clearly. Encourage the student and offer practice problems.',
      description: 'Patient, step-by-step math tutor',
      isBuiltIn: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      category: 'Education',
    ),
    Persona(
      id: 'builtin-story',
      name: 'Story Writer',
      emoji: '✍️',
      systemPrompt:
          'You are a creative fiction writer. Help craft engaging stories, develop characters, build worlds, and write dialogue. Match the tone and style the user requests. Offer constructive suggestions to improve narratives. Be creative and take risks with your writing while staying true to the user\'s vision.',
      description: 'Creative fiction writer',
      isBuiltIn: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      category: 'Creative',
    ),
    Persona(
      id: 'builtin-tutor',
      name: 'General Tutor',
      emoji: '📚',
      systemPrompt:
          'You are an educational tutor skilled in all subjects. Explain complex topics in simple terms. Use analogies, examples, and visual descriptions. Break down topics into digestible pieces. Check understanding by posing questions. Adapt your explanation style to the student\'s level.',
      description: 'Skilled tutor for all subjects',
      isBuiltIn: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      category: 'Education',
    ),
    Persona(
      id: 'builtin-editor',
      name: 'Writing Editor',
      emoji: '✏️',
      systemPrompt:
          'You are a professional writing editor. Help improve text clarity, grammar, style, and structure. Provide specific suggestions with explanations. Maintain the author\'s voice while improving readability. Offer alternatives rather than dictating changes. Format feedback clearly with before/after examples.',
      description: 'Professional writing editor',
      isBuiltIn: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      category: 'Creative',
    ),
    Persona(
      id: 'builtin-summarizer',
      name: 'Summarizer',
      emoji: '📋',
      systemPrompt:
          'You are a concise summarizer. When given text, provide clear, accurate summaries that capture the key points. Use bullet points for multiple items. Maintain the original meaning without adding interpretation. Adjust summary length based on the input — shorter inputs get shorter summaries.',
      description: 'Concise, accurate summarizer',
      isBuiltIn: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      category: 'General',
    ),
  ];
}

final filteredPersonasProvider = Provider<List<Persona>>((ref) {
  final personas = ref.watch(personasNotifierProvider);
  final category = ref.watch(personaCategoryFilterProvider);
  final query = ref.watch(personaSearchQueryProvider).toLowerCase();

  var filtered = personas;
  if (category != null && category.isNotEmpty) {
    filtered = filtered.where((p) => p.category == category).toList();
  }
  if (query.isNotEmpty) {
    filtered = filtered
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) ||
              (p.description?.toLowerCase().contains(query) ?? false) ||
              p.systemPrompt.toLowerCase().contains(query),
        )
        .toList();
  }
  return filtered;
});

final builtInPersonasProvider = Provider<List<Persona>>((ref) {
  return ref.watch(personasNotifierProvider).where((p) => p.isBuiltIn).toList();
});

final userPersonasProvider = Provider<List<Persona>>((ref) {
  return ref
      .watch(personasNotifierProvider)
      .where((p) => !p.isBuiltIn)
      .toList();
});

final personaByIdProvider = Provider.family<Persona?, String>((ref, id) {
  try {
    return ref.watch(personasNotifierProvider).firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
});
