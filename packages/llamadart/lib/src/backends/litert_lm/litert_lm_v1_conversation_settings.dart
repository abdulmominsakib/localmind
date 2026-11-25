part of 'litert_lm_v1_runtime.dart';

/// Internal TOP_P sampler override. Null at the conversation boundary inherits
/// the native sampler; explicit NPU overrides are unsupported.
final class LiteRtLmV1SamplerSettings {
  /// Creates an explicit TOP_P sampler with a resolved signed C-int seed.
  const LiteRtLmV1SamplerSettings({
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.seed,
  });

  /// Finite nonnegative temperature representable by the native float ABI.
  final double temperature;

  /// Native top-p probability in [0,1].
  final double topP;

  /// Nonnegative top-k; zero temperature always forwards one candidate.
  final int topK;

  /// Signed int32 seed, without implicit clock-based replacement.
  final int seed;

  void _validate() {
    if (!temperature.isFinite ||
        temperature < 0 ||
        temperature > 3.4028234663852886e38 ||
        !topP.isFinite ||
        topP < 0 ||
        topP > 1 ||
        (temperature > 0 && Float32List.fromList([temperature]).single == 0) ||
        (topP > 0 && Float32List.fromList([topP]).single == 0) ||
        topK < 0 ||
        topK > 0x7fffffff ||
        seed < -0x80000000 ||
        seed > 0x7fffffff) {
      throw LlamaArgumentException(
        'C API 1.0 sampler requires finite nonnegative float temperature, topP in [0,1], nonnegative int32 topK and int32 seed.',
      );
    }
  }
}

/// Internal, eagerly snapshotted text/tool preface. This does not enable strict
/// tool choice, media or LoRA. JSON Schema decoding is an explicit opt-in. Unsupported shape/field
/// combinations are refused rather than passed to native best-effort parsing.
final class LiteRtLmV1ConversationSettings {
  /// Validates and snapshots the supported JSON preface before native allocation.
  factory LiteRtLmV1ConversationSettings({
    int maxOutputTokens = 32,
    bool jsonSchemaConstraints = false,
    LiteRtLmV1SamplerSettings? sampler,
    String? systemMessage,
    List<Map<String, Object?>>? messages,
    List<Map<String, Object?>>? tools,
    Map<String, Object?>? extraContext,
    String? promptTemplate,
  }) {
    if (maxOutputTokens <= 0 || maxOutputTokens > 0x7fffffff) {
      throw LlamaArgumentException(
        'C API 1.0 maxOutputTokens must be a positive signed C int.',
      );
    }
    sampler?._validate();
    if (promptTemplate != null &&
        (promptTemplate.isEmpty || promptTemplate.contains('\u0000'))) {
      throw LlamaArgumentException(
        'C API 1.0 promptTemplate must be nonempty without NUL.',
      );
    }
    final preface = <String, String>{};
    void snapshot(
      String suffix,
      Object? input,
      void Function(Object?)? validate,
    ) {
      if (input == null) return;
      _jsonValue(input, HashSet<Object>.identity());
      late final String encoded;
      late final Object? snapshot;
      try {
        encoded = jsonEncode(input);
        snapshot = jsonDecode(encoded);
      } on Object {
        _invalid();
      }
      validate?.call(snapshot);
      preface['litert_lm_conversation_config_set_$suffix'] = encoded;
    }

    snapshot('system_message', systemMessage, null);
    snapshot('messages', messages, _messages);
    snapshot('tools', tools, _tools);
    snapshot('extra_context', extraContext, null);
    if (promptTemplate != null) {
      preface['litert_lm_conversation_config_set_prompt_template'] =
          promptTemplate;
    }
    return LiteRtLmV1ConversationSettings._(
      maxOutputTokens,
      jsonSchemaConstraints,
      sampler,
      Map.unmodifiable(preface),
    );
  }
  const LiteRtLmV1ConversationSettings._(
    this.maxOutputTokens,
    this.jsonSchemaConstraints,
    this.sampler,
    this._preface,
  );

  /// Default session output cap, inherited by sends without an override.
  final int maxOutputTokens;

  /// Enables native JSON Schema decoding with thinking disabled.
  final bool jsonSchemaConstraints;

  /// Explicit CPU/GPU override, or null for native inheritance.
  final LiteRtLmV1SamplerSettings? sampler;
  final Map<String, String> _preface;

  void _validate(ComputeDevice backend) {
    if (sampler != null && backend == ComputeDevice.npu) {
      throw LlamaUnsupportedException(
        'C API 1.0 explicit conversation sampling requires CPU/GPU; NPU must inherit its native sampler.',
      );
    }
  }

  static Never _invalid() => throw LlamaArgumentException(
    'C API 1.0 conversation data has an invalid supported message shape.',
  );
  static Never _unsupported() => throw LlamaUnsupportedException(
    'C API 1.0 conversation does not support this role, content or field combination.',
  );
  static void _keys(Map value, Set<String> keys) {
    if (value.keys.any((key) => !keys.contains(key))) _unsupported();
  }

  static bool _name(Object? value) => value is String && value.isNotEmpty;
  static void _jsonValue(Object? value, Set<Object> active) {
    if (value == null || value is String || value is bool || value is int) {
      return;
    }
    if (value is double) {
      if (!value.isFinite) _invalid();
      return;
    }
    if (value is! Map && value is! List) _invalid();
    if (!active.add(value)) _invalid();
    try {
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key is! String) _invalid();
          _jsonValue(entry.value, active);
        }
      } else {
        for (final entry in value as List) {
          _jsonValue(entry, active);
        }
      }
    } finally {
      active.remove(value);
    }
  }

  static void _messages(Object? input) {
    for (final message in input as List) {
      if (message is! Map) _invalid();
      _keys(message, {'role', 'content', 'reasoning_content', 'tool_calls'});
      final role = message['role'];
      if (!{'system', 'user', 'assistant', 'tool'}.contains(role)) {
        _unsupported();
      }
      if (!message.containsKey('content')) _invalid();
      if (message.containsKey('reasoning_content') &&
          (role != 'assistant' || message['reasoning_content'] is! String)) {
        _invalid();
      }
      final content = message['content'];
      if (content is String) {
        if (role == 'tool') _unsupported();
      } else {
        final parts = content is Map ? [content] : content;
        if (parts is! List) _invalid();
        for (final part in parts) {
          if (part is! Map) _invalid();
          if (part['type'] == 'text') {
            _keys(part, {'type', 'text'});
            if (part['text'] is! String || role == 'tool') _invalid();
          } else if (part['type'] == 'image' || part['type'] == 'audio') {
            if (message.containsKey('reasoning_content') ||
                message.containsKey('tool_calls')) {
              _unsupported();
            }
            _validateV1MediaPart(part, role);
          } else if (part['type'] == 'tool_response') {
            _keys(part, {'type', 'name', 'response'});
            if (role != 'tool' ||
                !_name(part['name']) ||
                !part.containsKey('response')) {
              _invalid();
            }
          } else {
            _unsupported();
          }
        }
        if (role == 'tool' && parts.isEmpty) _invalid();
      }
      if (message.containsKey('tool_calls')) {
        // A one-part text list is rewritten upstream and can drop tool_calls.
        if (role != 'assistant' ||
            content is! String ||
            message['tool_calls'] is! List) {
          _invalid();
        }
        for (final call in message['tool_calls'] as List) {
          if (call is! Map) _invalid();
          _keys(call, {'type', 'function'});
          final function = call['function'];
          if (call['type'] != 'function' || function is! Map) _invalid();
          _keys(function, {'name', 'arguments'});
          if (!_name(function['name']) ||
              !(function['arguments'] is Map ||
                  function['arguments'] is String)) {
            _invalid();
          }
        }
      }
    }
  }

  static void _tools(Object? input) {
    for (final tool in input as List) {
      if (tool is! Map) _invalid();
      _keys(tool, {'type', 'function'});
      final function = tool['function'];
      if (tool['type'] != 'function' || function is! Map) _invalid();
      _keys(function, {'name', 'description', 'parameters'});
      if (!_name(function['name']) ||
          (function.containsKey('description') &&
              function['description'] is! String)) {
        _invalid();
      }
      final schema = function['parameters'];
      if (schema is! Map || schema['type'] != 'object') _invalid();
      _schema(schema);
    }
  }

  static void _schema(Map schema) {
    const types = {
      'object',
      'array',
      'string',
      'integer',
      'number',
      'boolean',
      'null',
    };
    if (schema.containsKey('type')) {
      final type = schema['type'];
      if (type is String) {
        if (!types.contains(type)) {
          _invalid();
        }
      } else if (type is! List ||
          type.isEmpty ||
          type.any((v) => !types.contains(v))) {
        _invalid();
      }
    }
    if (schema.containsKey('properties')) {
      final properties = schema['properties'];
      if (properties is! Map) {
        _invalid();
      }
      for (final property in properties.values) {
        if (property is! Map) {
          _invalid();
        }
        _schema(property);
      }
    }
    if (schema.containsKey('required') &&
        (schema['required'] is! List ||
            (schema['required'] as List).any((v) => v is! String))) {
      _invalid();
    }
    if (schema.containsKey('items')) {
      if (schema['items'] is! Map) {
        _unsupported();
      }
      _schema(schema['items'] as Map);
    }
    for (final key in ['allOf', 'anyOf', 'oneOf']) {
      if (!schema.containsKey(key)) {
        continue;
      }
      final children = schema[key];
      if (children is! List || children.isEmpty) {
        _invalid();
      }
      for (final child in children) {
        if (child is! Map) {
          _invalid();
        }
        _schema(child);
      }
    }
    if (schema.containsKey('additionalProperties')) {
      final additional = schema['additionalProperties'];
      if (additional is Map) {
        _schema(additional);
      } else if (additional is! bool) {
        _invalid();
      }
    }
    if (schema.containsKey('enum') && schema['enum'] is! List) {
      _invalid();
    }
    for (final key in ['description', 'title', 'pattern', r'$ref']) {
      if (schema.containsKey(key) && schema[key] is! String) {
        _invalid();
      }
    }
  }
}
