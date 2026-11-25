import '../models/inference/generation_params.dart';
import 'xml_tool_call_format.dart';

/// The grammar for which the planner can grant or deny XML opener replay.
typedef ThinkingBudgetGrammarBinding = ({
  String grammar,
  String root,
  bool lazy,
  bool replay,
});

/// Template-derived budget settings carried with the request to the backend.
final class ResolvedThinkingBudget extends ThinkingBudget {
  /// Retains the caller text so native-message routing can skip the prefix.
  ResolvedThinkingBudget({
    required super.maxTokens,
    required super.startTag,
    required super.endTag,
    required super.forcedMessage,
    required this.originalForcedMessage,
    required List<String> naturalEndTags,
    ThinkingBudgetGrammarBinding? grammarBinding,
  }) : naturalEndTags = List.unmodifiable(naturalEndTags),
       _grammarBinding = grammarBinding;

  /// Caller text before applying the template close prefix.
  final String? originalForcedMessage;

  /// Complete ordered list of natural delimiters.
  final List<String> naturalEndTags;

  final ThinkingBudgetGrammarBinding? _grammarBinding;

  /// Opener to replay into the attached grammar if that grammar is paused.
  int? replayEndIndexFor(GenerationParams params) {
    const opener = XmlToolCallFormat.qwen3CoderScopeStart;
    final index = naturalEndTags.indexOf(opener);
    final grammar = params.grammar;
    if (index < 0 || grammar == null || grammar.trim().isEmpty) return null;

    final binding = _grammarBinding;
    final matchesBinding =
        binding != null &&
        binding.grammar == grammar &&
        binding.root == params.grammarRoot &&
        binding.lazy == params.grammarLazy;
    if (!params.grammarLazy) {
      return matchesBinding && binding.replay ? index : null;
    }
    if (matchesBinding && !binding.replay) return null;

    return params.grammarTriggers.any(
          (trigger) =>
              trigger.value == opener &&
              (trigger.type == GrammarTriggerType.word.wireValue ||
                  trigger.type == GrammarTriggerType.pattern.wireValue ||
                  trigger.type == GrammarTriggerType.patternFull.wireValue),
        )
        ? index
        : null;
  }
}
