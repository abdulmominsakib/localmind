import 'dart:convert';

import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../../api/generation_config.dart';
import 'schema_to_tool_params.dart';

/// Preserves visible conversation content while omitting reasoning in all roles.
///
/// Genkit owns the original history; conversion must not edit those messages.
/// Reasoning replay needs a model/template-specific contract and is intentionally
/// unavailable even when a runtime can generate or represent thinking content.
List<llama.LlamaChatMessage> toLlamaMessages(
  List<genkit.Message> messages, {
  Map<(String, String?), llama.LlamaContentPart> mediaOverrides = const {},
}) {
  final converted = <llama.LlamaChatMessage>[];

  for (final message in messages) {
    if (message.role == genkit.Role.tool) {
      final toolResponses = message.content
          .where((part) => part.isToolResponse)
          .map((part) => part.toolResponsePart!)
          .toList(growable: false);

      if (toolResponses.isEmpty) {
        throw genkit.GenkitException(
          'Tool messages must contain at least one tool response part.',
          status: genkit.StatusCode.invalidArgument,
        );
      }

      for (final part in toolResponses) {
        converted.add(
          llama.LlamaChatMessage.withContent(
            role: llama.LlamaChatRole.tool,
            content: [_toLlamaToolResult(part.toolResponse)],
          ),
        );
      }
      continue;
    }

    final parts = <llama.LlamaContentPart>[];
    for (final part in message.content) {
      final media = part.isMedia ? part.media! : null;
      final convertedPart =
          (media == null
              ? null
              : mediaOverrides[(media.url, media.contentType)]) ??
          _toLlamaPart(part);
      if (convertedPart != null) {
        parts.add(convertedPart);
      }
    }

    converted.add(
      llama.LlamaChatMessage.withContent(
        role: _toLlamaRole(message.role),
        content: parts.isEmpty
            ? <llama.LlamaContentPart>[const llama.LlamaTextContent('')]
            : parts,
      ),
    );
  }

  return converted;
}

typedef LlamaToolDefinitions = ({
  List<llama.ToolDefinition> tools,
  Map<String, Map<String, dynamic>> inputSchemas,
});

LlamaToolDefinitions toLlamaTools(List<genkit.ToolDefinition>? tools) {
  final converted = <llama.ToolDefinition>[];
  final schemas = <String, Map<String, dynamic>>{};
  final names = <String>{};
  for (final tool in tools ?? const <genkit.ToolDefinition>[]) {
    if (!names.add(tool.name)) {
      throw genkit.GenkitException(
        'Tool names must be unique within a model request.',
        status: genkit.StatusCode.invalidArgument,
      );
    }
    final input = tool.inputSchema;
    final schema = input == null
        ? const <String, dynamic>{'type': 'object'}
        : normalizeToolInputSchema(input);
    // Keep established simple tools usable on best-effort runtimes. Richer
    // contracts opt into the owning runtime's schema and grammar validation.
    try {
      converted.add(
        llama.ToolDefinition(
          name: tool.name,
          description: tool.description,
          parameters: schemaToToolParams(schema),
        ),
      );
    } on genkit.GenkitException {
      final llama.ToolDefinition definition;
      try {
        definition = llama.ToolDefinition.fromJsonSchema(
          name: tool.name,
          description: tool.description,
          schema: schema,
        );
      } on llama.LlamaException {
        throw genkit.GenkitException(
          "The tool input schema is invalid or outside llamadart 0.13's "
          'supported object-schema subset. Numeric bounds, patterns, formats, '
          'oneOf/allOf and non-object roots remain unsupported.',
          status: genkit.StatusCode.invalidArgument,
        );
      }
      converted.add(definition);
      schemas[tool.name] = definition.toJsonSchema();
    }
  }
  return (tools: converted, inputSchemas: schemas);
}

llama.GenerationParams toGenerationParams(LlamaDartGenerationConfig config) {
  return llama.GenerationParams(
    maxTokens: config.maxTokens ?? LlamaDartGenerationConfig.defaultMaxTokens,
    temp: config.temperature ?? LlamaDartGenerationConfig.defaultTemperature,
    topK: config.topK ?? LlamaDartGenerationConfig.defaultTopK,
    topP: config.topP ?? LlamaDartGenerationConfig.defaultTopP,
    minP: config.minP ?? LlamaDartGenerationConfig.defaultMinP,
    penalty: config.penalty ?? LlamaDartGenerationConfig.defaultPenalty,
    presencePenalty: config.presencePenalty ?? 0.0,
    thinkingBudget: config.thinkingBudget,
    speculativeDecoding: config.speculativeDecoding ?? false,
    speculativeDecodingConfig: config.speculativeDecodingConfig,
    reusePromptPrefix:
        config.reusePromptPrefix ??
        llama.GenerationParams.defaultReusePromptPrefix,
    streamBatchTokenThreshold:
        config.streamBatchTokenThreshold ??
        llama.GenerationParams.defaultStreamBatchTokenThreshold,
    streamBatchByteThreshold:
        config.streamBatchByteThreshold ??
        llama.GenerationParams.defaultStreamBatchByteThreshold,
    seed: config.seed,
    stopSequences: config.stop ?? const <String>[],
  );
}

llama.ToolChoice? toLlamaToolChoice(
  genkit.ToolChoice? toolChoice, {
  required bool hasTools,
}) {
  if (!hasTools) {
    return null;
  }

  return switch (toolChoice) {
    genkit.ToolChoice.none => llama.ToolChoice.none,
    genkit.ToolChoice.required => llama.ToolChoice.required,
    _ => llama.ToolChoice.auto,
  };
}

Map<String, dynamic>? toResponseFormat(genkit.OutputConfig? output) {
  if (output == null) {
    return null;
  }

  if (output.schema != null) {
    return {
      'type': 'json_schema',
      'json_schema': {'schema': output.schema},
    };
  }

  if (output.format == 'json' || output.contentType == 'application/json') {
    return {'type': 'json_object'};
  }

  return null;
}

bool shouldUseStructuredGeneration(genkit.OutputConfig? output) {
  if (output == null || output.constrained == false) {
    return false;
  }

  return output.schema != null ||
      output.format == 'json' ||
      output.contentType == 'application/json';
}

String documentToPlainText(genkit.DocumentData document) {
  final buffer = StringBuffer();

  for (final part in document.content) {
    if (part.isText) {
      buffer.write(part.text);
      continue;
    }

    if (part.isReasoning) {
      continue;
    }

    throw genkit.GenkitException(
      'llamadart embeddings currently support text-only documents.',
      status: genkit.StatusCode.invalidArgument,
    );
  }

  return buffer.toString();
}

llama.LlamaChatRole _toLlamaRole(genkit.Role role) {
  return switch (role) {
    final value when value == genkit.Role.system => llama.LlamaChatRole.system,
    final value when value == genkit.Role.user => llama.LlamaChatRole.user,
    final value when value == genkit.Role.tool => llama.LlamaChatRole.tool,
    _ => llama.LlamaChatRole.assistant,
  };
}

llama.LlamaContentPart? _toLlamaPart(genkit.Part part) {
  if (part.isText) {
    return llama.LlamaTextContent(part.text!);
  }

  if (part.isMedia) {
    return _toLlamaMediaPart(part.media!);
  }

  if (part.isToolRequest) {
    final toolRequest = part.toolRequest!;
    final arguments = toLlamaToolArguments(toolRequest.input);
    return llama.LlamaToolCallContent(
      id: toolRequest.ref,
      name: toolRequest.name,
      arguments: arguments,
      rawJson: jsonEncode(arguments),
    );
  }

  if (part.isToolResponse) {
    return _toLlamaToolResult(part.toolResponse!);
  }

  if (part.isReasoning) {
    return null;
  }

  if (part.isData || part.isCustom || part.isResource) {
    throw genkit.GenkitException(
      'Unsupported Genkit part type for llamadart requests: ${part.toJson().keys.join(', ')}',
      status: genkit.StatusCode.invalidArgument,
    );
  }

  return null;
}

Map<String, dynamic> toLlamaToolArguments(Object? input) {
  if (input == null) {
    return const <String, dynamic>{};
  }
  if (input is Map<String, dynamic>) {
    return input;
  }
  if (input is Map && input.keys.every((key) => key is String)) {
    return <String, dynamic>{
      for (final entry in input.entries) entry.key as String: entry.value,
    };
  }
  throw genkit.GenkitException(
    'llamadart tool requests require object-shaped input.',
    status: genkit.StatusCode.invalidArgument,
  );
}

llama.LlamaContentPart _toLlamaMediaPart(genkit.Media media) {
  final uri = Uri.tryParse(media.url);
  if (uri == null && !_windowsDrivePath.hasMatch(media.url)) {
    throw genkit.GenkitException(
      'Malformed media URI for llamadart; use a local path, file URL or data URL.',
      status: genkit.StatusCode.invalidArgument,
    );
  }
  final String? contentType;
  try {
    contentType = media.contentType ?? inferMediaContentType(media.url);
  } on FormatException {
    throw genkit.GenkitException(
      'Invalid media data URL; check its MIME type and encoded payload.',
      status: genkit.StatusCode.invalidArgument,
    );
  }
  final isImage = contentType?.startsWith('image/') ?? false;
  final isAudio = contentType?.startsWith('audio/') ?? false;

  if (!isImage && !isAudio) {
    throw genkit.GenkitException(
      'Unsupported media type for llamadart; specify an image/* or audio/* MIME type.',
      status: genkit.StatusCode.invalidArgument,
    );
  }

  if (uri?.scheme == 'data') {
    try {
      final bytes = UriData.parse(media.url).contentAsBytes();
      return isImage
          ? llama.LlamaImageContent(bytes: bytes)
          : llama.LlamaAudioContent(bytes: bytes);
    } on FormatException {
      throw genkit.GenkitException(
        'Invalid media data URL; check its MIME type and encoded payload.',
        status: genkit.StatusCode.invalidArgument,
      );
    }
  }

  final filePath = _toFilePath(uri, media.url);
  if (filePath != null) {
    return isImage
        ? llama.LlamaImageContent(path: filePath)
        : llama.LlamaAudioContent(path: filePath);
  }

  if (isImage && (uri?.scheme == 'http' || uri?.scheme == 'https')) {
    return llama.LlamaImageContent(url: media.url);
  }

  throw genkit.GenkitException(
    'Unsupported media URI scheme for llamadart. Audio requires a local path, '
    'file URL or data URL; remote images require an HTTP(S)-capable backend.',
    status: genkit.StatusCode.invalidArgument,
  );
}

String? inferMediaContentType(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null && uri.scheme == 'data') {
    return UriData.parse(url).mimeType;
  }

  final lowerPath = (uri?.path.isNotEmpty ?? false)
      ? uri!.path.toLowerCase()
      : url.toLowerCase();
  if (lowerPath.endsWith('.png') ||
      lowerPath.endsWith('.jpg') ||
      lowerPath.endsWith('.jpeg') ||
      lowerPath.endsWith('.gif') ||
      lowerPath.endsWith('.webp')) {
    return 'image/*';
  }
  if (lowerPath.endsWith('.wav') ||
      lowerPath.endsWith('.mp3') ||
      lowerPath.endsWith('.m4a') ||
      lowerPath.endsWith('.ogg')) {
    return 'audio/*';
  }

  return null;
}

String? _toFilePath(Uri? uri, String originalUrl) {
  if (_windowsDrivePath.hasMatch(originalUrl)) {
    return originalUrl;
  }
  if (uri == null || uri.scheme.isEmpty) {
    return originalUrl;
  }

  if (uri.scheme == 'file') {
    if (uri.hasQuery || uri.hasFragment) {
      throw genkit.GenkitException(
        'Local file media URLs cannot contain query parameters or fragments.',
        status: genkit.StatusCode.invalidArgument,
      );
    }
    try {
      return uri.toFilePath();
    } on UnsupportedError {
      throw genkit.GenkitException(
        'Invalid local file media URL; use a file URL valid for this platform.',
        status: genkit.StatusCode.invalidArgument,
      );
    }
  }

  return null;
}

final RegExp _windowsDrivePath = RegExp(r'^[A-Za-z]:[\\/]');

String _normalizeToolResultOutput(Object? output) {
  if (output == null) {
    return 'null';
  }
  if (output is String) {
    return output;
  }

  try {
    return jsonEncode(output);
  } catch (_) {
    return output.toString();
  }
}

llama.LlamaToolResultContent _toLlamaToolResult(genkit.ToolResponse response) =>
    llama.LlamaToolResultContent(
      id: response.ref,
      name: response.name,
      result: response.content?.isNotEmpty == true
          ? response.content!.map(_toolResultText).join('\n')
          : _normalizeToolResultOutput(response.output),
    );

String _toolResultText(Object? part) {
  final value = part is genkit.Part ? part.toJson() : part;
  if (value is Map &&
      value['text'] is String &&
      value.keys.every((key) => key == 'text' || key == 'metadata')) {
    return value['text'] as String;
  }
  throw genkit.GenkitException(
    'llamadart tool-result content supports text parts only; return TextPart values or structured output.',
    status: genkit.StatusCode.unimplemented,
  );
}
