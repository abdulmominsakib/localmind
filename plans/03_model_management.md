# Feature 03 — Model Management

> **Phase:** 2 — Chat Polish  
> **Status:** Pending  
> **Depends on:** `01_server_connection`, `07_core_architecture`  

---

## Goal

Let users browse, select, and swap LLM models from their connected servers. Display model metadata and allow mid-conversation model switching.

---

## Feature Folder Structure

```
features/model_management/
├── data/
│   └── models/                      # (Uses core/models/model_info.dart)
│
├── providers/
│   └── model_management_providers.dart
│
└── views/
    ├── model_picker_sheet.dart      # Bottom sheet for model selection
    └── components/
        ├── model_tile.dart
        └── model_metadata_chip.dart
```

---

## Dependencies Used

| Package             | Purpose                      |
| ------------------- | ---------------------------- |
| `dio`               | Fetch model lists from APIs  |
| `flutter_riverpod`  | Model state management       |

---

## Data Model

`ModelInfo` is defined in `core/models/model_info.dart`.

```dart
class ModelInfo {
  final String id;
  final String name;
  final String? description;
  final int? parameterCount;
  final int? contextLength;
  final int? fileSize;
  final String? quantization;
  final String? architecture;
  final ServerType serverType;
  final String serverId;
  final DateTime? modifiedAt;
}
```

---

## API Response Parsing

### LM Studio (`GET /v1/models`)

```json
{
  "data": [
    {
      "id": "llama-3.2-3b-instruct",
      "object": "model",
      "owned_by": "organization-owner"
    }
  ]
}
```

- LM Studio provides minimal metadata — only `id`
- Parse model name from ID (replace hyphens/underscores with spaces, capitalize)
- Try to extract parameter count from name (e.g., "3b" → 3 billion)

### Ollama (`GET /api/tags`)

```json
{
  "models": [
    {
      "name": "llama3.2:3b",
      "model": "llama3.2:3b",
      "size": 2019393189,
      "digest": "...",
      "details": {
        "parent_model": "",
        "format": "gguf",
        "family": "llama",
        "families": ["llama"],
        "parameter_size": "3.2B",
        "quantization_level": "Q4_K_M"
      },
      "modified_at": "2024-..."
    }
  ]
}
```

- Ollama provides rich metadata
- Parse `parameter_size` to extract number
- Use `details.family` for architecture
- Use `size` for file size display

### OpenRouter (`GET /v1/models`)

```json
{
  "data": [
    {
      "id": "google/gemma-2-9b-it",
      "name": "Google: Gemma 2 9B",
      "description": "...",
      "context_length": 8192,
      "pricing": { "prompt": "0.00003", "completion": "0.00006" },
      "architecture": { "modality": "text->text", "tokenizer": "Gemini" }
    }
  ]
}
```

- OpenRouter provides most metadata including pricing
- Filter to text-only models

---

## Providers

Location: `features/model_management/providers/model_management_providers.dart`

### Provider Organization

```dart
// 1. Available models for active server
final availableModelsProvider = FutureProvider<List<ModelInfo>>((ref) async {
  final server = ref.watch(activeServerProvider);
  if (server == null) return [];
  return ref.read(serverRepositoryProvider).fetchModels(server);
});

// 2. Currently selected model (stored in conversation or globally)
final selectedModelProvider = StateProvider<ModelInfo?>((ref) => null);

// 3. Search/filter query
final modelSearchQueryProvider = StateProvider<String>((ref) => '');

// 4. Filtered models based on search
final filteredModelsProvider = Provider<List<ModelInfo>>((ref) {
  final models = ref.watch(availableModelsProvider).value ?? [];
  final query = ref.watch(modelSearchQueryProvider).toLowerCase();
  if (query.isEmpty) return models;
  return models.where((m) =>
    m.name.toLowerCase().contains(query) ||
    m.id.toLowerCase().contains(query)
  ).toList();
});

// 5. Model cache (5 minute TTL per server)
final modelCacheProvider = StateNotifierProvider<ModelCacheNotifier, Map<String, CachedModels>>((ref) {
  return ModelCacheNotifier();
});

class ModelCacheNotifier extends StateNotifier<Map<String, CachedModels>> {
  // Cache management with 5-minute TTL
}
```

---

## Views

### `model_picker_sheet.dart`

**Trigger:** Tap on model name in chat app bar.

**Layout:**

```
┌──────────────────────────────────────┐
│  ═══ (drag handle)                   │
│                                      │
│  Select Model                        │
│  [🔍 Search models...            ]   │
│                                      │
│  ── Active Server: My Desktop ──     │
│                                      │
│  ┌──────────────────────────────┐    │
│  │ ✅ Llama 3.2 3B Instruct    │    │
│  │    3.2B params · Q4_K_M     │    │
│  │    1.9 GB · 4096 context    │    │
│  └──────────────────────────────┘    │
│                                      │
│  ┌──────────────────────────────┐    │
│  │    Mistral 7B Instruct       │    │
│  │    7B params · Q4_K_M        │    │
│  │    3.8 GB · 8192 context     │    │
│  └──────────────────────────────┘    │
│                                      │
│  [Refresh Models]                    │
└──────────────────────────────────────┘
```

**Features:**
- Search/filter bar at top
- Selected model has checkmark
- Each tile: name, parameter count, quantization, size, context length
- Gracefully omit unavailable metadata
- "Refresh Models" button to re-fetch
- Loading skeleton while fetching
- Error state with retry

---

## Components

### `model_tile.dart`

- Leading: Model architecture icon or first letter avatar
- Title: Model display name
- Subtitle: Metadata chips
- Trailing: Checkmark if selected
- Tap → select, dismiss sheet

### `model_metadata_chip.dart`

Small pill labels:
- `3.2B` (parameter count)
- `Q4_K_M` (quantization)
- `1.9 GB` (file size)
- `4096 ctx` (context length)

---

## Mid-Chat Model Swapping

1. Update `selectedModelProvider` with new model
2. Show system divider: "Switched to {model name}"
3. Subsequent messages use new model
4. `Message.modelId` records which model generated each message
5. No conversation reset — continue with existing history

---

## Model Caching

- Cache model list per server (in-memory)
- Cache duration: 5 minutes
- Force refresh via "Refresh Models" button
- When switching servers, clear and re-fetch

---

## Acceptance Criteria

- [ ] Model list fetched for LM Studio servers.
- [ ] Model list fetched for Ollama servers (full metadata).
- [ ] Model list fetched for OpenRouter servers.
- [ ] User can search/filter models by name.
- [ ] Selected model is visually indicated.
- [ ] Tapping a model selects and closes picker.
- [ ] Model can be swapped mid-conversation.
- [ ] Model metadata displays correctly.
- [ ] Loading and error states handled.
- [ ] Model list is cached and can be force-refreshed.
