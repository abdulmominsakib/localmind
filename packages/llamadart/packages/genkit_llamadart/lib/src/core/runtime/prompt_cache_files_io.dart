import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

Future<T> withPromptCacheFile<T>(
  Future<T> Function(String path) operation,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'genkit-prompt-cache-',
  );
  try {
    return await operation('${directory.path}/state.bin');
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<List<int>> readPromptCache(String path, int maxBytes) async {
  final file = File(path);
  final length = await file.length();
  if (length <= 0 || length > maxBytes) {
    throw LlamaStateException(
      'The raw prompt cache exceeds the pool byte budget.',
    );
  }
  final input = await file.open();
  try {
    final bytes = await input.read(length + 1);
    if (bytes.length != length) {
      throw LlamaStateException(
        'The raw prompt cache changed while being read.',
      );
    }
    return bytes;
  } finally {
    await input.close();
  }
}

Future<void> writePromptCache(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<String> promptModelIdentity(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
