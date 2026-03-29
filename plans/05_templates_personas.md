# Feature 05 — Templates & Personas

> **Phase:** 3 — Features  
> **Status:** Pending  
> **Depends on:** `00_project_setup`, `04_conversation_management`, `07_core_architecture`  

---

## Goal

Allow users to define reusable AI personas (system prompts + identity) that shape model behavior. Include built-in presets and let users create custom personas.

---

## Feature Folder Structure

```
features/persona/
├── data/
│   └── models/                      # (Uses core/models/persona.dart)
│
├── providers/
│   └── persona_providers.dart
│
└── views/
    ├── persona_list_page.dart       # Browse personas
    ├── create_persona_page.dart     # Create/edit persona
    └── components/
        ├── persona_card.dart
        └── persona_category_chips.dart
```

---

## Dependencies Used

| Package             | Purpose                       |
| ------------------- | ----------------------------- |
| `hive_ce`           | Persist personas locally      |
| `flutter_riverpod`  | Persona state management      |

---

## Data Model

The `Persona` model is defined in `core/models/persona.dart`.

---

## Built-in Presets

These ship with the app and cannot be deleted (but can be cloned):

### 1. General Assistant 🤖
```
You are a helpful, knowledgeable AI assistant. Provide clear, accurate, and concise responses. When you're not sure about something, say so. Use markdown formatting for structured responses.
```
Category: General

### 2. Code Assistant 🧑‍💻
```
You are an expert software engineer. Help with coding questions, debugging, code reviews, and architecture decisions. Always provide code examples with proper syntax highlighting. Explain your reasoning. Follow best practices and mention potential pitfalls. When writing code, include comments for complex logic.
```
Category: Coding

### 3. Math Tutor 📐
```
You are a patient and thorough math tutor. Explain concepts step by step, starting from fundamentals. Use examples to illustrate abstract concepts. When solving problems, show your work clearly. Use LaTeX notation for mathematical expressions when appropriate. Encourage the student and offer practice problems.
```
Category: Education

### 4. Story Writer ✍️
```
You are a creative fiction writer. Help craft engaging stories, develop characters, build worlds, and write dialogue. Match the tone and style the user requests. Offer constructive suggestions to improve narratives. Be creative and take risks with your writing while staying true to the user's vision.
```
Category: Creative

### 5. General Tutor 📚
```
You are an educational tutor skilled in all subjects. Explain complex topics in simple terms. Use analogies, examples, and visual descriptions. Break down topics into digestible pieces. Check understanding by posing questions. Adapt your explanation style to the student's level.
```
Category: Education

### 6. Writing Editor ✏️
```
You are a professional writing editor. Help improve text clarity, grammar, style, and structure. Provide specific suggestions with explanations. Maintain the author's voice while improving readability. Offer alternatives rather than dictating changes. Format feedback clearly with before/after examples.
```
Category: Creative

### 7. Summarizer 📋
```
You are a concise summarizer. When given text, provide clear, accurate summaries that capture the key points. Use bullet points for multiple items. Maintain the original meaning without adding interpretation. Adjust summary length based on the input — shorter inputs get shorter summaries.
```
Category: General

---

## Providers

Location: `features/persona/providers/persona_providers.dart`

### Provider Organization

```dart
// 1. All personas (built-in + user-created)
final personasProvider = StateNotifierProvider<PersonasNotifier, List<Persona>>((ref) {
  final box = ref.watch(hiveBoxesProvider).personas;
  return PersonasNotifier(box);
});

// 2. Currently selected persona for new chat
final selectedPersonaProvider = StateProvider<Persona?>((ref) => null);

// 3. Category filter
final personaCategoryFilterProvider = StateProvider<String?>((ref) => null);

// 4. Filtered personas based on category
final filteredPersonasProvider = Provider<List<Persona>>((ref) {
  final personas = ref.watch(personasProvider);
  final category = ref.watch(personaCategoryFilterProvider);
  if (category == null) return personas;
  return personas.where((p) => p.category == category).toList();
});
```

### `PersonasNotifier`

```dart
class PersonasNotifier extends StateNotifier<List<Persona>> {
  final Box<Persona> _box;

  PersonasNotifier(this._box) : super([]) {
    loadPersonas();
  }

  Future<void> loadPersonas();
  Future<void> seedBuiltInPersonas();
  Future<void> createPersona(Persona persona);
  Future<void> updatePersona(Persona persona);
  Future<void> deletePersona(String id);
  Future<Persona> clonePersona(String id);
}
```

---

## Views

### `persona_list_page.dart`

**Layout:**

```
┌──────────────────────────────────────┐
│  Personas                     [+ ]   │
│                                      │
│  [All] [Coding] [Education] [Creat.] │
│                                      │
│  ── BUILT-IN ──                      │
│  ┌──────────────────────────────┐    │
│  │ 🤖 General Assistant        │    │
│  │ Helpful, knowledgeable...   │    │
│  └──────────────────────────────┘    │
│  ┌──────────────────────────────┐    │
│  │ 🧑‍💻 Code Assistant           │    │
│  │ Expert software engineer... │    │
│  └──────────────────────────────┘    │
│  ...                                 │
│                                      │
│  ── MY PERSONAS ──                   │
│  ┌──────────────────────────────┐    │
│  │ 🎯 Interview Prep           │    │
│  │ Practice tech interviews... │    │
│  └──────────────────────────────┘    │
│                                      │
│  [Create Custom Persona]             │
└──────────────────────────────────────┘
```

**Features:**
- Category filter chips (All, Coding, Education, Creative, General)
- Sections: "Built-in" and "My Personas"
- Tap card → apply to current/new conversation
- Long-press built-in → "Clone & Edit"
- Long-press custom → Edit, Delete, Clone

---

### `create_persona_page.dart`

**Form fields:**

| Field          | Type      | Validation                          |
| -------------- | --------- | ----------------------------------- |
| Name           | Text      | Required, 1–50 chars                |
| Emoji          | Picker    | Required, single emoji              |
| Category       | Dropdown  | Optional (Coding, Education, etc.)  |
| Description    | Text      | Optional, 1–200 chars               |
| System Prompt  | Multiline | Required, 1–4000 chars              |

**System prompt field:**
- Large multiline text area (min 6 lines)
- Character count indicator
- Preview mode toggle

**Emoji picker:**
- Grid of common emojis
- Categories: People, Animals, Objects, Symbols

**Optional parameter overrides:**
- Expandable "Advanced Settings"
- Temperature slider (0.0 – 2.0)
- Top P slider (0.0 – 1.0)

---

## Components

### `persona_card.dart`

- Left: Large emoji avatar (40x40)
- Title: Persona name
- Subtitle: Description or first line of system prompt
- Right: "Built-in" badge
- Bottom: Category chip
- Tap → apply persona

### `persona_category_chips.dart`

Horizontal scroll:
- "All" (default)
- "Coding" 🧑‍💻
- "Education" 📚
- "Creative" ✍️
- "General" 🤖

---

## Applying a Persona

### To a New Conversation

1. Select persona from list
2. Create conversation with `personaId` set
3. Persona `systemPrompt` prepended as first system message
4. If persona has `preferredParams`, override global chat params
5. Chat app bar shows persona emoji

### To an Existing Conversation

1. Chat overflow menu → "Change Persona"
2. Opens persona picker
3. Selecting persona adds divider and uses new system prompt
4. "Remove Persona" option

---

## First Launch Seeding

On first launch (empty personas box):
1. Seed all 7 built-in personas into Hive
2. Mark with `isBuiltIn: true`
3. Set "General Assistant" as default

---

## Acceptance Criteria

- [ ] 7 built-in personas available on first launch.
- [ ] User can browse personas with category filtering.
- [ ] User can create custom persona.
- [ ] User can edit and delete custom personas.
- [ ] User can clone built-in persona for customization.
- [ ] Applying persona to new chat sets system prompt.
- [ ] Persona can be changed mid-conversation.
- [ ] Persona emoji appears in chat app bar when active.
- [ ] Parameter overrides from personas are respected.
- [ ] Built-in personas cannot be deleted.
- [ ] Persona data persists across restarts.
