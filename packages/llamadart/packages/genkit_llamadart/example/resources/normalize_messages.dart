import 'dart:convert';

import 'package:genkit/genkit.dart';

/// Expands explicitly approved resources and renders JSON data as text.
///
/// This application recipe accepts text/image/audio input and resource/data
/// parts, preserving message roles and order. Limits are 16 messages, 32 visited
/// parts, four resource/JSON levels, 64 JSON nodes per data part, and 16 KiB of
/// text and media URLs combined. These bounds are not a token budget.
/// Resource action names must be safe source IDs. No URI is fetched implicitly;
/// media transport and decoding remain subject to the model/resolver policy.
/// The caller owns resource actions, media resolution, Genkit and cancellation.
/// Throws [FormatException] for unsupported input or exceeded limits.
Future<List<Message>> normalizeResourceMessages(
  Iterable<Message> messages,
  Map<String, ResourceAction> resources, {
  CancellationToken? cancel,
}) async {
  var visited = 0;
  var bytes = 0;
  final active = <String>{};
  final result = <Message>[];

  Future<List<Part>> expand(List<Part> parts, int depth) async {
    final output = <Part>[];
    void append(Part part, String content) {
      if (content.length > 16384) {
        throw const FormatException('Expanded content exceeds 16 KiB.');
      }
      bytes += utf8.encode(content).length;
      if (bytes > 16384) {
        throw const FormatException('Expanded content exceeds 16 KiB.');
      }
      output.add(part);
    }

    for (final part in parts) {
      cancel?.throwIfCancelled();
      if (++visited > 32) {
        throw const FormatException('Too many expanded parts.');
      }
      if (part.isText) {
        append(part, part.text!);
      } else if (part.isMedia) {
        final type = part.media!.contentType ?? '';
        if (!type.startsWith('image/') && !type.startsWith('audio/')) {
          throw const FormatException('Only image/audio media is supported.');
        }
        append(part, part.media!.url);
      } else if (part.isData) {
        final text = _jsonData(part.data);
        append(TextPart(text: text), text);
      } else if (part.isResource) {
        if (depth >= 4) {
          throw const FormatException('Resource nesting exceeds the limit.');
        }
        final uri = part.resource!['uri'];
        if (part.resource!.length != 1 || uri is! String) {
          throw const FormatException(
            'A resource must contain only a URI string.',
          );
        }
        final action = resources[uri];
        if (action == null || !action.matches(ResourceInput(uri: uri))) {
          throw const FormatException('Resource is not explicitly approved.');
        }
        if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(action.name)) {
          throw const FormatException(
            'Resource action needs a safe source ID.',
          );
        }
        if (!active.add(uri)) {
          throw const FormatException('Cyclic resource expansion.');
        }
        try {
          final ResourceOutput resolved;
          try {
            resolved = await action(ResourceInput(uri: uri), cancel: cancel);
          } catch (_) {
            cancel?.throwIfCancelled();
            throw const FormatException('Approved resource resolution failed.');
          }
          cancel?.throwIfCancelled();
          final label = '\n[Source: ${action.name}]\n';
          append(TextPart(text: label), label);
          output.addAll(await expand(resolved.content, depth + 1));
          const end = '\n[/Source]\n';
          append(TextPart(text: end), end);
        } finally {
          active.remove(uri);
        }
      } else {
        throw const FormatException('Unsupported resource/data input part.');
      }
    }
    return output;
  }

  for (final message in messages) {
    cancel?.throwIfCancelled();
    if (result.length >= 16) {
      throw const FormatException('Too many input messages.');
    }
    if (message.role != Role.user &&
        message.content.any((part) => part.isData || part.isResource)) {
      throw const FormatException(
        'Resource/data input belongs in a user message.',
      );
    }
    result.add(
      Message(
        role: message.role,
        metadata: message.metadata,
        content: await expand(message.content, 0),
      ),
    );
  }
  cancel?.throwIfCancelled();
  return result;
}

String _jsonData(Object? value) {
  var nodes = 0;
  var characters = 0;
  void validate(Object? value, int depth) {
    if (++nodes > 64 || depth > 4) {
      throw const FormatException('JSON data exceeds the nesting/node limit.');
    }
    if (value == null || value is bool) return;
    if (value is num && value.isFinite) return;
    if (value is String) {
      characters += value.length;
      if (characters > 16384) {
        throw const FormatException('JSON data exceeds the size limit.');
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        validate(item, depth + 1);
      }
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String || (entry.key as String).length > 16384) {
          throw const FormatException(
            'JSON data keys must be bounded strings.',
          );
        }
        characters += (entry.key as String).length;
        if (characters > 16384) {
          throw const FormatException('JSON data exceeds the size limit.');
        }
        validate(entry.value, depth + 1);
      }
      return;
    }
    throw const FormatException('Data must contain bounded JSON values.');
  }

  validate(value, 0);
  return jsonEncode(value);
}
