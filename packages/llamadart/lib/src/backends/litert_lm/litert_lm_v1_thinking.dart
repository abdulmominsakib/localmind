part of 'litert_lm_v1_runtime.dart';

/// Per-send status/out budget transport; schema chat never applies a budget.
final class _V1ThinkingBudget {
  const _V1ThinkingBudget(this.runtime);
  final LiteRtLmV1Runtime runtime;
  static const symbols = <String>[
    'litert_lm_thinking_config_create',
    'litert_lm_thinking_config_delete',
    'litert_lm_thinking_config_set_enable_thinking',
    'litert_lm_thinking_config_set_thinking_token_budget',
    'litert_lm_conversation_optional_args_set_thinking_config',
    'litert_lm_conversation_optional_args_create',
    'litert_lm_conversation_optional_args_delete',
    ..._V1TokenizerBindings._symbols,
  ];
  bool get supported => symbols.every(runtime._library.providesSymbol);

  void admit({String? extraContext}) {
    if (!supported) {
      throw LlamaUnsupportedException(
        'C API 1.0 thinking budgets require the complete status/out thinking and tokenizer export groups.',
      );
    }
    final conversation = runtime._conversation;
    if (conversation == null) {
      throw LlamaStateException(
        'Create a conversation before applying a thinking budget.',
      );
    }
    final merged = <String, dynamic>{
      if (conversation._thinkingExtraContext != null)
        ...jsonDecode(conversation._thinkingExtraContext)
            as Map<String, dynamic>,
      if (extraContext != null)
        ...jsonDecode(extraContext) as Map<String, dynamic>,
    };
    if (merged.containsKey('enable_thinking') &&
        merged['enable_thinking'] != true) {
      throw LlamaUnsupportedException(
        'A thinking budget requires thinking enabled; the effective conversation/send context disables or cannot declare it.',
      );
    }
    final path = runtime._engineModelPath;
    final channel = path == null
        ? null
        : readLiteRtLmBundleFirstChannelDetails(path);
    const names = {'thought', 'thinking', 'think', 'reasoning'};
    if (channel == null ||
        channel.name.trim().isEmpty ||
        channel.name.contains('\u0000') ||
        !(channel.isReasoning ?? names.contains(channel.name.toLowerCase()))) {
      throw LlamaUnsupportedException(
        'C API 1.0 thinking budgets require the model first channel to be a declared reasoning channel.',
      );
    }
    final start = channel.start, end = channel.end;
    if (start == null ||
        end == null ||
        start.isEmpty ||
        end.isEmpty ||
        start.contains('\u0000') ||
        end.contains('\u0000') ||
        start == end) {
      throw LlamaUnsupportedException(
        'C API 1.0 thinking budgets require distinct nonempty first-channel start/end boundaries without NUL.',
      );
    }
    List<int> prove(String boundary) {
      final ids = runtime.tokenize(boundary, addSpecial: false);
      if (ids.isEmpty ||
          ids.any((id) => id < 0) ||
          runtime.detokenize(ids) != boundary) {
        throw LlamaUnsupportedException(
          'The loaded C API 1.0 tokenizer cannot preserve a thinking channel boundary.',
        );
      }
      return ids;
    }

    final startIds = prove(start), endIds = prove(end);
    if (startIds.length == endIds.length &&
        List.generate(
          startIds.length,
          (i) => startIds[i] == endIds[i],
        ).every((same) => same)) {
      throw LlamaUnsupportedException(
        'Thinking channel start/end boundaries must have distinct native token IDs.',
      );
    }
  }

  void apply(Pointer<Void> args, int budget) {
    final library = runtime._library;
    final create = library.lookupFunction<_CreateN, _CreateD>(symbols[0]);
    final delete = library.lookupFunction<_DeleteN, _DeleteD>(symbols[1]);
    final output = calloc<Pointer<Void>>();
    Pointer<Void> config = nullptr;
    try {
      final status = create(output);
      config = output.value;
      runtime._check(status, 'thinking_config_create');
      if (config == nullptr) {
        throw LlamaStateException(
          'Thinking configuration returned no owned handle.',
        );
      }
      runtime._check(
        library.lookupFunction<_SetBoolN, _SetBoolD>(symbols[2])(config, true),
        'thinking_config_set_enable_thinking',
      );
      runtime._check(
        library.lookupFunction<_SetIntN, _SetIntD>(symbols[3])(config, budget),
        'thinking_config_set_thinking_token_budget',
      );
      runtime._check(
        library.lookupFunction<_SetPointerN, _SetPointerD>(symbols[4])(
          args,
          config,
        ),
        'optional_args_set_thinking_config',
      );
    } finally {
      if (config != nullptr) delete(config);
      calloc.free(output);
    }
  }
}
