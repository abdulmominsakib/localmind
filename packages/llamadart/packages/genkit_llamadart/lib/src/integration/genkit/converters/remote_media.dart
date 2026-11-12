import 'dart:async';
import 'dart:typed_data';

import 'package:genkit/plugin.dart' as genkit;
import 'package:llamadart/llamadart.dart' as llama;

import '../../../api/media_resolver.dart';
import 'genkit_to_llama.dart';

FutureOr<List<llama.LlamaChatMessage>> resolveLlamaMessages(
  List<genkit.Message> messages, {
  LlamaDartMediaResolver? resolver,
  genkit.CancellationToken? cancel,
}) {
  if (!const bool.fromEnvironment('dart.library.io') || resolver == null) {
    return toLlamaMessages(messages);
  }
  final pending = <(String, String?), String>{};
  final overrides = <(String, String?), llama.LlamaContentPart>{};
  for (final message in messages) {
    if (message.role == genkit.Role.tool) continue;
    for (final part in message.content) {
      if (!part.isMedia) continue;
      final media = part.media!;
      final uri = Uri.tryParse(media.url);
      if (uri?.scheme != 'http' && uri?.scheme != 'https') continue;
      final type = (media.contentType ?? inferMediaContentType(media.url))
          ?.toLowerCase();
      if (type == null ||
          !RegExp(r'^(image|audio)/[a-z0-9!#$&^_.+*-]+$').hasMatch(type)) {
        throw genkit.GenkitException(
          'Remote media requires an image/* or audio/* MIME type.',
          status: genkit.StatusCode.invalidArgument,
        );
      }
      final key = (media.url, media.contentType);
      pending[key] = type;
      overrides[key] = type.startsWith('image/')
          ? llama.LlamaImageContent(bytes: Uint8List(0))
          : llama.LlamaAudioContent(bytes: Uint8List(0));
    }
  }
  final validated = toLlamaMessages(messages, mediaOverrides: overrides);
  if (pending.isEmpty) return validated;
  return () async {
    final replacements =
        Map<llama.LlamaContentPart, llama.LlamaContentPart>.identity();
    for (final entry in pending.entries) {
      if (cancel?.isCancelled ?? false) {
        throw genkit.CancelledException(token: cancel);
      }
      final Uint8List bytes;
      try {
        bytes = await resolver.resolve(
          Uri.parse(entry.key.$1),
          contentType: entry.value,
          cancel: cancel,
        );
        if (bytes.isEmpty) throw StateError('Empty media.');
      } catch (error) {
        if (cancel?.isCancelled ?? false) {
          throw genkit.CancelledException(token: cancel);
        }
        throw genkit.GenkitException(
          'Remote media resolution failed. Check URL policy, authentication, '
          'response MIME type and transfer limits.',
          status: error is genkit.GenkitException
              ? error.status
              : genkit.StatusCode.invalidArgument,
        );
      }
      if (cancel?.isCancelled ?? false) {
        throw genkit.CancelledException(token: cancel);
      }
      replacements[overrides[entry.key]!] = entry.value.startsWith('image/')
          ? llama.LlamaImageContent(bytes: bytes)
          : llama.LlamaAudioContent(bytes: bytes);
    }
    // Reuse validated text and decoded inline media instead of parsing mutable
    // caller input again after awaiting downloads.
    return [
      for (final message in validated)
        llama.LlamaChatMessage.withContent(
          role: message.role,
          content: [
            for (final part in message.parts) replacements[part] ?? part,
          ],
        ),
    ];
  }();
}
