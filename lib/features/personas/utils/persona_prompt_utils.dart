import '../data/models/persona.dart';

class PersonaPromptUtils {
  PersonaPromptUtils._();

  static List<String> parsePersonaIds(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static String joinPersonaIds(List<String> ids) => ids.join(',');

  static String combineSystemPrompts(List<Persona> personas) {
    if (personas.isEmpty) return '';
    if (personas.length == 1) return personas.first.systemPrompt;
    return personas
        .map((p) => '## ${p.name}\n\n${p.systemPrompt.trim()}')
        .join('\n\n---\n\n');
  }

  static List<Persona> resolvePersonas(
    String? rawIds,
    List<Persona> allPersonas,
  ) {
    final ids = parsePersonaIds(rawIds);
    if (ids.isEmpty) return const [];
    final byId = {for (final p in allPersonas) p.id: p};
    return ids.map((id) => byId[id]).whereType<Persona>().toList();
  }
}
