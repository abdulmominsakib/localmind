part of 'litert_lm_v1_runtime.dart';

typedef _SchemaConstraintN = Int Function(Pointer<Void>, Int, Pointer<Utf8>);
typedef _SchemaConstraintD = int Function(Pointer<Void>, int, Pointer<Utf8>);

/// Status-checked C API 1.0 constraint group; legacy signatures are incompatible.
final class _V1JsonSchema {
  const _V1JsonSchema(this.runtime);
  final LiteRtLmV1Runtime runtime;
  static const symbols = <String>[
    'litert_lm_conversation_config_set_constraint_provider',
    'litert_lm_conversation_optional_args_set_constraint',
    'litert_lm_thinking_config_create',
    'litert_lm_thinking_config_set_enable_thinking',
    'litert_lm_thinking_config_delete',
    'litert_lm_conversation_config_set_thinking_config',
    'litert_lm_conversation_optional_args_set_thinking_config',
    'litert_lm_conversation_optional_args_create',
    'litert_lm_conversation_optional_args_delete',
  ];
  bool get supported => symbols.every(runtime._library.providesSymbol);
  void requireSupport() {
    if (!supported) {
      throw LlamaUnsupportedException(
        'Native JSON Schema chat requires the complete LiteRT-LM C API 1.0 constraint and thinking-disable exports.',
      );
    }
  }

  void _setThinking(Pointer<Void> target, String setter, bool enabled) {
    final library = runtime._library;
    final thinking = runtime._create(
      'thinking_config_create',
      library.lookupFunction<_CreateN, _CreateD>(
        'litert_lm_thinking_config_create',
      ),
    );
    try {
      runtime._check(
        library.lookupFunction<_SetBoolN, _SetBoolD>(
          'litert_lm_thinking_config_set_enable_thinking',
        )(thinking, enabled),
        'thinking_config_set_enable_thinking',
      );
      runtime._check(
        library.lookupFunction<_SetPointerN, _SetPointerD>(setter)(
          target,
          thinking,
        ),
        setter,
      );
    } finally {
      library.lookupFunction<_DeleteN, _DeleteD>(
        'litert_lm_thinking_config_delete',
      )(thinking);
    }
  }

  /// Thinking keeps an enabled reasoning channel unconstrained; the native
  /// thinking config suspends the schema until that channel closes.
  void configure(Pointer<Void> config, {required bool thinking}) {
    requireSupport();
    runtime._check(
      runtime._library.lookupFunction<_SetIntN, _SetIntD>(
        'litert_lm_conversation_config_set_constraint_provider',
      )(config, 1),
      'conversation_config_set_constraint_provider',
    );
    _setThinking(
      config,
      'litert_lm_conversation_config_set_thinking_config',
      thinking,
    );
  }

  void constrain(Pointer<Void> args, String schema, {required bool thinking}) {
    requireSupport();
    final text = schema.toNativeUtf8(allocator: calloc);
    try {
      runtime._check(
        runtime._library.lookupFunction<_SchemaConstraintN, _SchemaConstraintD>(
          'litert_lm_conversation_optional_args_set_constraint',
        )(args, 2, text),
        'conversation_optional_args_set_constraint',
      );
    } finally {
      calloc.free(text);
    }
    _setThinking(
      args,
      'litert_lm_conversation_optional_args_set_thinking_config',
      thinking,
    );
  }
}
