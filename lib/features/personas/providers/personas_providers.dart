import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/storage/entities.dart';
import '../data/models/persona.dart';
import '../../../objectbox.g.dart';

final personaSearchQueryProvider =
    NotifierProvider<_PersonaSearchNotifier, String>(
      _PersonaSearchNotifier.new,
    );

final selectedPersonaProvider =
    NotifierProvider<SelectedPersonaNotifier, Persona?>(
      SelectedPersonaNotifier.new,
    );

class SelectedPersonaNotifier extends Notifier<Persona?> {
  @override
  Persona? build() => null;

  void select(Persona? persona) {
    state = persona;
  }

  void clear() {
    state = null;
  }
}

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
    AsyncNotifierProvider<PersonasNotifier, List<Persona>>(
      PersonasNotifier.new,
    );

class PersonasNotifier extends AsyncNotifier<List<Persona>> {
  @override
  Future<List<Persona>> build() async {
    return _loadAndSeed();
  }

  Future<List<Persona>> _loadAndSeed() async {
    final db = ref.read(databaseProvider);
    var entities = db.personaBox.getAll();

    if (entities.isEmpty) {
      for (final preset in _builtInPersonas) {
        db.personaBox.put(PersonaEntity.fromDomain(preset));
      }
      entities = db.personaBox.getAll();
    }

    final personas = entities.map((e) => e.toDomain()).toList();
    personas.sort((a, b) {
      if (a.isBuiltIn != b.isBuiltIn) return a.isBuiltIn ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return personas;
  }

  Future<Persona> createPersona({
    required String name,
    required String emoji,
    required String systemPrompt,
    String? description,
    String? category,
    Map<String, dynamic>? preferredParams,
  }) async {
    final db = ref.read(databaseProvider);
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
    db.personaBox.put(PersonaEntity.fromDomain(persona));
    state = AsyncData(await _loadAndSeed());
    return persona;
  }

  Future<void> updatePersona(Persona updated) async {
    final db = ref.read(databaseProvider);
    final persona = updated.copyWith(updatedAt: DateTime.now());

    final query = db.personaBox
        .query(PersonaEntity_.id.equals(persona.id))
        .build();
    final existing = query.findFirst();
    query.close();

    final entity = PersonaEntity.fromDomain(persona);
    if (existing != null) {
      entity.internalId = existing.internalId;
    }
    db.personaBox.put(entity);

    state = AsyncData(await _loadAndSeed());
  }

  Future<void> deletePersona(String id) async {
    final personas = state.value ?? [];
    final persona = personas.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Persona not found'),
    );
    if (persona.isBuiltIn) return;

    final db = ref.read(databaseProvider);
    final query = db.personaBox.query(PersonaEntity_.id.equals(id)).build();
    db.personaBox.removeMany(query.findIds());
    query.close();

    state = AsyncData(await _loadAndSeed());
  }

  Future<Persona> clonePersona(String id) async {
    final personas = state.value ?? [];
    final original = personas.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Persona not found'),
    );

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
    final db = ref.read(databaseProvider);
    db.personaBox.put(PersonaEntity.fromDomain(clone));
    state = AsyncData(await _loadAndSeed());
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
  final personasAsync = ref.watch(personasNotifierProvider);
  final personas = personasAsync.value ?? [];
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
  final personas = ref.watch(personasNotifierProvider).value ?? [];
  return personas.where((p) => p.isBuiltIn).toList();
});

final userPersonasProvider = Provider<List<Persona>>((ref) {
  final personas = ref.watch(personasNotifierProvider).value ?? [];
  return personas.where((p) => !p.isBuiltIn).toList();
});

final personaByIdProvider = Provider.family<Persona?, String>((ref, id) {
  try {
    final personas = ref.watch(personasNotifierProvider).value ?? [];
    return personas.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
});
