import '../../core/models/inference/generation_params.dart';

/// Converts [triggers] into the trigger patterns and tokens that llama.cpp's
/// lazy grammar sampler takes.
///
/// Throws `LlamaUnsupportedException` for a trigger whose raw type is not a
/// [GrammarTriggerType] wire value.
({List<String> patterns, List<int> tokens}) lazyGrammarTriggerInputs(
  Iterable<GenerationGrammarTrigger> triggers,
) {
  final patterns = <String>[];
  final tokens = <int>[];
  for (final trigger in triggers) {
    switch (trigger.triggerType) {
      case GrammarTriggerType.word:
        patterns.add(_regexEscape(trigger.value));
      case GrammarTriggerType.token:
        final token = trigger.token ?? int.tryParse(trigger.value);
        if (token != null) tokens.add(token);
      case GrammarTriggerType.pattern:
        patterns.add(trigger.value);
      case GrammarTriggerType.patternFull:
        final pattern = trigger.value;
        patterns.add(
          pattern.isEmpty
              ? r'^$'
              : "${pattern.startsWith('^') ? '' : '^'}$pattern"
                    "${pattern.endsWith(r'$') ? '' : r'$'}",
        );
    }
  }
  return (patterns: patterns, tokens: tokens);
}

String _regexEscape(String input) {
  final escaped = StringBuffer();
  const regexMeta = r'\^$.*+?()[]{}|';
  for (var i = 0; i < input.length; i++) {
    final char = input[i];
    if (regexMeta.contains(char)) {
      escaped.write('\\');
    }
    escaped.write(char);
  }
  return escaped.toString();
}
