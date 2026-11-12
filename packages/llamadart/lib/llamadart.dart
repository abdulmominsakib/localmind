/// High-performance Dart and Flutter plugin for local LLM inference.
///
/// **llamadart** allows you to run Large Language Models (LLMs) locally with
/// GGUF models through llama.cpp and `.litertlm` bundles through LiteRT-LM
/// across native and web platforms.
///
/// ### Core Components
///
/// * [LlamaEngine]: The stateless engine for model loading, tokenization,
///   and generation.
/// * [ChatSession]: A high-level, stateful interface for chat-based interactions.
///   It automatically manages conversation history and context window limits.
/// * [LlamaBackend]: The platform-agnostic interface for inference.
///
/// Custom backends and their test fakes also import
/// `package:llamadart/backend.dart`. The raw llama.cpp FFI is in
/// `package:llamadart/llama_cpp_bindings.dart`, outside semantic versioning.
///
/// ### Simple Example
///
/// ```dart
/// final engine = LlamaEngine(LlamaBackend());
/// await engine.loadModel('path/to/model.gguf'); // or model.litertlm
///
/// final session = ChatSession(engine);
/// await for (final chunk in session.create([LlamaTextContent('Hello!')])) {
///   stdout.write(chunk.text);
/// }
///
/// final reply = await session.send('Say that again, shorter.');
/// print(reply.text);
///
/// await engine.dispose();
/// ```
library;

export 'src/core/diagnostics/runtime_setup_report.dart'
    show
        LlamaRuntimeSetupReport,
        LlamaRuntimeSetupRuntime,
        collectLlamaRuntimeSetupReport;

// Engine & Chat
export 'src/core/engine/engine.dart'
    show LlamaEngine, LlamaEngineCompletionExtension;
export 'src/core/engine/engine_capabilities.dart';
export 'src/core/engine/llamadart_engine.dart';
export 'src/core/engine/engine_observer.dart';
export 'src/core/engine/load_check_report.dart'
    show LlamaLoadCheckReport, LlamaLoadCheckStatus;
export 'src/core/engine/chat_session.dart'
    show ChatSession, ChatSessionCompletionExtension, TemplateTimeChatSession;
export 'src/core/engine/chat_session_tool_loop.dart';

// Speech
export 'src/core/speech/speech_to_text.dart';
export 'src/core/speech/speech_to_text_model.dart';
export 'src/core/speech/text_to_speech.dart';
export 'src/core/speech/text_to_speech_model.dart';

// Image generation (experimental)
export 'src/core/image/generated_image.dart';
export 'src/core/image/image_generation_engine.dart'
    show
        ImageGenerationCapabilities,
        ImageGenerationEngine,
        ImageGenerationTask;
export 'src/core/image/image_generation_events.dart';
export 'src/core/image/image_generation_model.dart';
export 'src/core/image/image_model_params.dart';
export 'src/core/image/image_model_placement.dart';
export 'src/core/image/image_editing_request.dart'
    show ImageEditingPixels, ImageEditingRequest;
export 'src/core/image/image_control_net_request.dart'
    show ControlNetImageGenerationRequest, ImageControlNetCondition;
export 'src/core/image/image_hires_fix_request.dart'
    show HiresFixImageGenerationRequest, ImageHiresFix, ImageHiresUpscaler;
export 'src/core/image/image_reference_editing_request.dart'
    show ImageReferenceEditingRecipe, ReferenceImageEditingRequest;
export 'src/core/image/image_generation_request.dart'
    show
        ImageGenerationRequest,
        SeamlessImageGenerationRequest,
        TiledImageGenerationRequest,
        ImageVaeTiling;

// Decision models
export 'src/core/decision/decision_engine.dart'
    show
        DecisionCapabilities,
        DecisionEngine,
        DecisionModelInfo,
        DecisionTask,
        DecisionCompletion,
        DecisionCompletionState;
export 'src/core/decision/decision_model.dart';
export 'src/core/decision/decision_model_params.dart';
export 'src/core/decision/decision_key.dart';
export 'src/core/decision/decision_question.dart';
export 'src/core/decision/decision_result.dart';

// Template APIs
export 'src/backends/litert_lm/litert_lm_templates.dart';
export 'src/core/template/chat_format.dart' show ChatFormat;
export 'src/core/template/chat_parse_result.dart' show ChatParseResult;
export 'src/core/template/chat_template_engine.dart' show ChatTemplateEngine;
export 'src/core/template/chat_template_handler.dart' show ChatTemplateHandler;
export 'src/core/template/template_render_context.dart'
    show TemplateToolCallSerialization;

// Backend: the app-facing part. The custom-backend SPI is in
// package:llamadart/backend.dart.
export 'src/backends/backend.dart'
    show
        LlamaBackend,
        BackendPerfContextData,
        BackendTextToSpeechModel,
        StateLoadResult;

// Models - Inference
export 'src/core/models/inference/embedding.dart';
export 'src/core/engine/text_embedder.dart';
export 'src/core/engine/reranker.dart';
export 'src/core/models/inference/reranking.dart';
export 'src/core/models/inference/model_params.dart';
export 'src/core/models/inference/next_token_scores.dart';
export 'src/core/models/inference/state_identity.dart';
export 'src/core/models/inference/generation_params.dart';
export 'src/core/models/inference/generation_usage.dart';
export 'src/core/models/inference/structured_output.dart';
export 'src/core/models/inference/tool_choice.dart';

// Models - Sources, resolution, and downloads
export 'src/core/models/model_format.dart';
export 'src/core/models/model_source.dart';
export 'src/core/models/model_resolver.dart';
export 'src/core/models/model_file_store.dart';
export 'src/core/models/model_load_options.dart';
export 'src/core/models/download/model_download_manager.dart';

// Models - Chat
export 'src/core/models/chat/chat_message.dart';
export 'src/core/models/chat/content_part.dart';
export 'src/core/models/chat/chat_role.dart';
export 'src/core/models/chat/chat_template_result.dart';
export 'src/core/models/chat/completion.dart'
    show LlamaCompletion, LlamaCompletionStreamExtension;
export 'src/core/models/chat/completion_chunk.dart';

// Tools
export 'src/core/models/tools/tool_definition.dart'
    show ToolDefinition, ToolHandler;
export 'src/core/models/tools/tool_param.dart' show ToolParam;
export 'src/core/models/tools/tool_output.dart';
export 'src/core/models/tools/tool_params.dart';

// Models - Config
// Logging
export 'src/core/llama_logger.dart';
export 'src/core/llama_logging.dart' show LlamaLogging;
export 'src/core/models/config/log_level.dart';
export 'src/core/models/config/compute_device.dart';
export 'src/core/models/config/gpu_backend.dart';
export 'src/core/models/config/gpu_device_info.dart';
export 'src/core/models/config/flash_attention.dart';
export 'src/core/models/config/kv_cache_type.dart';
export 'src/core/models/config/lora_config.dart' show LoraAdapterConfig;
export 'src/core/models/diagnostics/model_file_type.dart';

// Utils
export 'src/core/exceptions.dart';
export 'src/core/cache_policy.dart' show hasPersistentCacheSensitiveUrlParts;

// LiteRT-LM speech-to-text configuration
export 'src/backends/litert_lm/litert_lm_asr_types.dart'
    show LiteRtLmAsrBackend, LiteRtLmAsrModelPreset, LiteRtLmAsrRuntimeConfig;

export 'src/core/engine/generation_task.dart'
    show
        GenerationTaskState,
        ChatGenerationTask,
        ChatGenerationCompletion,
        TextGenerationTask,
        TextGenerationCompletion;
