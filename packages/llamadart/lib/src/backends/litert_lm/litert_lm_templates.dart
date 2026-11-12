import 'litert_lm_chat_templates.dart';

/// The current canonical Qwen3 text template for `ModelParams.chatTemplate`.
///
/// Use this accessor instead of copying a template file: it follows the
/// installed llamadart version and explicitly identifies renamed legacy
/// Qwen3 LiteRT-LM bundles, even when they lack model-family metadata.
/// Native text conversations honor `enableThinking: false` with this override;
/// a native runtime without the conversation-template setter throws
/// `LlamaUnsupportedException`.
///
/// Web `@litert-lm/core@0.19.0` cannot replace its conversation template and
/// rejects this override with `LlamaUnsupportedException` at model load.
/// This does not select Qwen3.5, add media support, or identify bundle contents.
///
/// ```dart
/// final params = ModelParams(chatTemplate: liteRtLmQwen3ChatTemplate);
/// ```
String get liteRtLmQwen3ChatTemplate => kLiteRtLmChatTemplates
    .singleWhere((template) => template.id == 'qwen3')
    .template;
