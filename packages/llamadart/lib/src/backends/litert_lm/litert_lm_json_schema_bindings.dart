import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'litert_lm_last_error.dart';

typedef _ConfigNative = Void Function(Pointer<Void>, Pointer<Int>);
typedef _ConfigDart = void Function(Pointer<Void>, Pointer<Int>);
typedef _ConstraintNative = Void Function(Pointer<Void>, Int, Pointer<Utf8>);
typedef _ConstraintDart = void Function(Pointer<Void>, int, Pointer<Utf8>);
typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _EnableNative = Void Function(Pointer<Void>, Bool);
typedef _EnableDart = void Function(Pointer<Void>, bool);
typedef _SetThinkingNative = Void Function(Pointer<Void>, Pointer<Void>);
typedef _SetThinkingDart = void Function(Pointer<Void>, Pointer<Void>);
typedef _DeleteNative = Void Function(Pointer<Void>);
typedef _DeleteDart = void Function(Pointer<Void>);

/// Complete optional C API for explicitly constrained, thinking-disabled chat.
final class LiteRtLmJsonSchemaApi {
  LiteRtLmJsonSchemaApi._(
    this._provider,
    this._constraint,
    this._thinkingCreate,
    this._thinkingEnable,
    this._thinkingDelete,
    this._configThinking,
    this._argsThinking,
  );

  /// All functions must resolve; the upstream C API has no constraint ABI getter.
  static const symbols = <String>[
    'litert_lm_conversation_config_set_constraint_provider',
    'litert_lm_conversation_optional_args_set_constraint',
    'litert_lm_thinking_config_create',
    'litert_lm_thinking_config_set_enable_thinking',
    'litert_lm_thinking_config_delete',
    'litert_lm_conversation_config_set_thinking_config',
    'litert_lm_conversation_optional_args_set_thinking_config',
  ];

  final _ConfigDart _provider;
  final _ConstraintDart _constraint;
  final _CreateDart _thinkingCreate;
  final _EnableDart _thinkingEnable;
  final _DeleteDart _thinkingDelete;
  final _SetThinkingDart _configThinking;
  final _SetThinkingDart _argsThinking;

  /// Returns null if any member of the optional group is missing.
  static LiteRtLmJsonSchemaApi? probe(LiteRtLmSymbolLookup lookup) {
    final addresses = symbols.map(lookup).toList();
    if (addresses.any((pointer) => pointer == null || pointer == nullptr)) {
      return null;
    }
    return LiteRtLmJsonSchemaApi._(
      addresses[0]!
          .cast<NativeFunction<_ConfigNative>>()
          .asFunction<_ConfigDart>(),
      addresses[1]!
          .cast<NativeFunction<_ConstraintNative>>()
          .asFunction<_ConstraintDart>(),
      addresses[2]!
          .cast<NativeFunction<_CreateNative>>()
          .asFunction<_CreateDart>(),
      addresses[3]!
          .cast<NativeFunction<_EnableNative>>()
          .asFunction<_EnableDart>(),
      addresses[4]!
          .cast<NativeFunction<_DeleteNative>>()
          .asFunction<_DeleteDart>(),
      addresses[5]!
          .cast<NativeFunction<_SetThinkingNative>>()
          .asFunction<_SetThinkingDart>(),
      addresses[6]!
          .cast<NativeFunction<_SetThinkingNative>>()
          .asFunction<_SetThinkingDart>(),
    );
  }

  /// Probes the loaded runtime, without assuming a release tag supplies support.
  static LiteRtLmJsonSchemaApi? probeLibrary(DynamicLibrary library) =>
      probe((symbol) {
        try {
          return library.lookup<Void>(symbol);
        } on ArgumentError {
          return null;
        }
      });

  void _withoutThinking(Pointer<Void> target, _SetThinkingDart set) {
    final thinking = _thinkingCreate();
    if (thinking == nullptr) {
      throw StateError('LiteRT-LM thinking config creation failed.');
    }
    try {
      _thinkingEnable(thinking, false);
      set(target, thinking);
    } finally {
      _thinkingDelete(thinking);
    }
  }

  /// Config copies the enum and thinking config; the conversation owns its provider.
  void configure(Pointer<Void> config) {
    final provider = calloc<Int>()..value = 1;
    try {
      _provider(config, provider);
    } finally {
      calloc.free(provider);
    }
    _withoutThinking(config, _configThinking);
  }

  /// Native optional args copy the schema string and disabled thinking config.
  void constrain(Pointer<Void> args, String schema) {
    final text = schema.toNativeUtf8(allocator: calloc);
    try {
      _constraint(args, 2, text);
    } finally {
      calloc.free(text);
    }
    _withoutThinking(args, _argsThinking);
  }
}
