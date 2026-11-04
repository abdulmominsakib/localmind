/// High-performance Dart and Flutter plugin for local LLM inference.
///
/// **llamadart** allows you to run Large Language Models (LLMs) locally with
/// GGUF models through llama.cpp and `.litertlm` bundles through LiteRT-LM
/// across native and web platforms.
///
/// ### Core Components
///
/// * [LlamaEngine]: The low-level orchestrator for model loading, tokenization,
///   and raw inference.
/// * [ChatSession]: A high-level, stateful interface for chat-based interactions.
///   It automatically manages conversation history and context window limits.
/// * [LlamaBackend]: The platform-agnostic interface for inference.
///
/// ### Simple Example
///
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('path/to/model.gguf'); // or model.litertlm
///
/// final session = ChatSession(engine);
/// final response = StringBuffer();
/// await for (final chunk in session.create([LlamaTextContent('Hello!')])) {
///   final text = chunk.choices.first.delta.content;
///   if (text != null) {
///     response.write(text);
///   }
/// }
/// print(response.toString());
///
/// await engine.dispose();
/// ```
library;

// Engine & Chat
export 'src/core/engine/engine.dart' show LlamaEngine;
export 'src/core/engine/chat_session.dart' show ChatSession;

// Template APIs
export 'src/core/template/chat_format.dart' show ChatFormat;
export 'src/core/template/chat_parse_result.dart' show ChatParseResult;
export 'src/core/template/chat_template_engine.dart' show ChatTemplateEngine;
export 'src/core/template/chat_template_handler.dart' show ChatTemplateHandler;

// Backend (interface only)
export 'src/backends/backend.dart'
    show
        LlamaBackend,
        BackendAvailability,
        BackendGrammarConstraintsSupport,
        BackendGpuEnumeration,
        BackendNativeChatGeneration,
        BackendRuntimeDiagnostics,
        BackendModelFileTypeDiagnostics,
        BackendPerfContextData,
        BackendPerformanceDiagnostics,
        BackendEmbeddings,
        BackendEmbeddingsSupport,
        BackendBatchEmbeddings,
        BackendStatePersistence,
        BackendStatePersistenceSupport,
        StateLoadResult;

// Models - Inference
export 'src/core/models/inference/model_params.dart';
export 'src/core/models/inference/generation_params.dart';
export 'src/core/models/inference/structured_output.dart';
export 'src/core/models/inference/tool_choice.dart';

// Models - Sources, resolution, and downloads
export 'src/core/models/model_source.dart';
export 'src/core/models/model_resolver.dart';
export 'src/core/models/model_load_options.dart';
export 'src/core/models/download/model_download_manager.dart';

// Models - Chat
export 'src/core/models/chat/chat_message.dart';
export 'src/core/models/chat/content_part.dart';
export 'src/core/models/chat/chat_role.dart';
export 'src/core/models/chat/chat_template_result.dart';
export 'src/core/models/chat/completion_chunk.dart';

// Tools
export 'src/core/models/tools/tool_definition.dart';
export 'src/core/models/tools/tool_param.dart';
export 'src/core/models/tools/tool_params.dart';

// Models - Config
// Logging
export 'src/core/llama_logger.dart';
export 'src/core/models/config/log_level.dart';
export 'src/core/models/config/gpu_backend.dart';
export 'src/core/models/config/gpu_device_info.dart';
export 'src/core/models/config/flash_attention.dart';
export 'src/core/models/config/kv_cache_type.dart';
export 'src/core/models/config/lora_config.dart';
export 'src/core/models/diagnostics/model_file_type.dart';

// Utils
export 'src/core/exceptions.dart';
export 'src/core/cache_policy.dart' show hasPersistentCacheSensitiveUrlParts;

// LiteRT-LM native APIs
export 'src/backends/litert_lm/litert_lm_backend_stub.dart'
    if (dart.library.js_interop) 'src/backends/litert_lm/litert_lm_backend_web.dart'
    if (dart.library.io) 'src/backends/litert_lm/litert_lm_backend.dart'
    show LiteRtLmBackend;
export 'src/backends/litert_lm/litert_lm_runtime_stub.dart'
    if (dart.library.io) 'src/backends/litert_lm/litert_lm_runtime.dart'
    show LiteRtLmRuntimeClient, LiteRtLmRuntimeMetrics, LiteRtLmRuntimeResult;

// Deprecated compatibility aliases for the old benchmark API.
export 'src/experimental/litert_lm/litert_lm_benchmark_stub.dart'
    if (dart.library.io) 'src/experimental/litert_lm/litert_lm_benchmark.dart';

// Bindings - conditional export for web/native
export 'src/backends/llama_cpp/bindings_stub.dart'
    if (dart.library.io) 'src/backends/llama_cpp/bindings.dart';
