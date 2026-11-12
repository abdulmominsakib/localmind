import 'package:llamadart/llamadart.dart';

Future<T> withPromptCacheFile<T>(Future<T> Function(String path) operation) =>
    throw LlamaUnsupportedException(
      'Prompt caches require native file support.',
    );

Future<List<int>> readPromptCache(String path, int maxBytes) =>
    throw LlamaUnsupportedException(
      'Prompt caches require native file support.',
    );

Future<void> writePromptCache(String path, List<int> bytes) =>
    throw LlamaUnsupportedException(
      'Prompt caches require native file support.',
    );

Future<String> promptModelIdentity(String path) =>
    throw LlamaUnsupportedException(
      'Prompt caches require native file support.',
    );
