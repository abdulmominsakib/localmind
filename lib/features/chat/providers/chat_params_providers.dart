import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/conversations/providers/conversation_providers.dart'
    as conv;
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/personas/utils/persona_prompt_utils.dart';
import '../data/models/chat_parameters.dart';
import 'chat_reasoning_providers.dart';
import 'model_selection_providers.dart';

final chatParamsProvider = Provider<ChatParameters>((ref) {
  final settings = ref.watch(settingsProvider);
  final activeConv = ref.watch(conv.activeConversationProvider);
  final selectedModel = ref.watch(selectedModelProvider);
  final reasoningConfig = ref.watch(chatReasoningConfigProvider);
  final reasoningEnabled =
      (selectedModel?.supportsReasoning ?? false) ? reasoningConfig.enabled : null;

  double temperature = settings.temperature;
  double topP = settings.topP;
  int maxTokens = settings.maxTokens;
  int contextLength = settings.contextLength;

  if (activeConv?.temperature != null) {
    temperature = activeConv!.temperature!;
  }
  if (activeConv?.topP != null) {
    topP = activeConv!.topP!;
  }
  if (activeConv?.maxTokens != null) {
    maxTokens = activeConv!.maxTokens!;
  }
  if (activeConv?.contextLength != null) {
    contextLength = activeConv!.contextLength!;
  }

  String? systemPrompt;
  if (activeConv?.systemPrompt != null &&
      activeConv!.systemPrompt!.trim().isNotEmpty) {
    systemPrompt = activeConv.systemPrompt;
  } else if (activeConv?.personaId != null) {
    final personasAsync = ref.read(personasNotifierProvider);
    final personas = personasAsync.value ?? [];
    final selected = PersonaPromptUtils.resolvePersonas(
      activeConv!.personaId,
      personas,
    );
    if (selected.isNotEmpty) {
      systemPrompt = PersonaPromptUtils.combineSystemPrompts(selected);
      final persona = selected.first;
      if (persona.preferredParams != null) {
        final params = persona.preferredParams as Map<String, dynamic>;
        if (params['temperature'] != null) {
          temperature = (params['temperature'] as num).toDouble();
        }
        if (params['topP'] != null) topP = (params['topP'] as num).toDouble();
        if (params['maxTokens'] != null) {
          maxTokens = (params['maxTokens'] as num).toInt();
        }
      }
    }
  }

  return ChatParameters(
    temperature: temperature,
    topP: topP,
    maxTokens: maxTokens,
    contextLength: contextLength,
    systemPrompt: systemPrompt,
    reasoningEnabled: reasoningEnabled,
    reasoningEffort: reasoningConfig.effort,
  );
});
