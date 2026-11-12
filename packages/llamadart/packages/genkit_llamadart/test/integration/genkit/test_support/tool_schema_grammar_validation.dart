import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/llama_cpp/bindings.dart';
import 'package:llamadart/src/core/grammar/json_schema_converter.dart';
import 'package:test/test.dart';

/// Compiles the adapter's serialized schema using the pinned native sampler.
///
/// This checks JSON-schema grammar acceptance with the Qwen3 vocabulary. The
/// real Genkit tool loop separately covers the model's chat-template grammar.
void validateCompiledToolSchema(String modelPath, ToolDefinition tool) {
  final path = modelPath.toNativeUtf8();
  final params = llama_model_default_params()..vocab_only = true;
  final model = llama_model_load_from_file(path.cast<Char>(), params);
  malloc.free(path);
  expect(model, isNot(nullptr));
  try {
    final grammar = JsonSchemaConverter.convert(tool.toJsonSchema());
    for (final candidate in {
      '{"value":null}': true,
      '{"value":"null"}': false,
      '{"value":1}': false,
      '{}': false,
      '{"value":null': false,
    }.entries) {
      expect(
        _accepts(model, grammar, candidate.key),
        candidate.value,
        reason: candidate.key,
      );
    }
    print(
      'Compiled tool JSON schema with Qwen3 vocabulary: required null accepted; string, number, missing value and incomplete output rejected.',
    );
  } finally {
    llama_model_free(model);
  }
}

bool _accepts(Pointer<llama_model> model, String grammar, String candidate) {
  final vocab = llama_model_get_vocab(model);
  final grammarText = grammar.toNativeUtf8();
  final root = 'root'.toNativeUtf8();
  final sampler = llama_sampler_init_grammar(
    vocab,
    grammarText.cast<Char>(),
    root.cast<Char>(),
  );
  malloc
    ..free(grammarText)
    ..free(root);
  expect(sampler, isNot(nullptr));
  try {
    final prefix = _tokenize(vocab, '\n');
    final tokens = _tokenize(vocab, '\n$candidate');
    expect(tokens.take(prefix.length), orderedEquals(prefix));
    final data = calloc<llama_token_data>();
    final array = calloc<llama_token_data_array>();
    try {
      array.ref
        ..data = data
        ..size = 1
        ..selected = -1
        ..sorted = false;
      for (final token in tokens.skip(prefix.length)) {
        data.ref
          ..id = token
          ..logit = 0
          ..p = 0;
        llama_sampler_apply(sampler, array);
        if (!data.ref.logit.isFinite) return false;
        llama_sampler_accept(sampler, token);
      }
      final eos = llama_vocab_eos(vocab);
      expect(llama_vocab_is_eog(vocab, eos), isTrue);
      data.ref
        ..id = eos
        ..logit = 0
        ..p = 0;
      llama_sampler_apply(sampler, array);
      return data.ref.logit.isFinite;
    } finally {
      calloc
        ..free(data)
        ..free(array);
    }
  } finally {
    llama_sampler_free(sampler);
  }
}

List<int> _tokenize(Pointer<llama_vocab> vocab, String candidate) {
  final text = candidate.toNativeUtf8();
  try {
    final length = -llama_tokenize(
      vocab,
      text.cast<Char>(),
      text.length,
      nullptr,
      0,
      false,
      false,
    );
    expect(length, greaterThan(0));
    final tokens = calloc<llama_token>(length);
    try {
      expect(
        llama_tokenize(
          vocab,
          text.cast<Char>(),
          text.length,
          tokens,
          length,
          false,
          false,
        ),
        length,
      );
      return [for (var i = 0; i < length; i++) tokens[i]];
    } finally {
      calloc.free(tokens);
    }
  } finally {
    malloc.free(text);
  }
}

/// Verifies positive and negative token sequences against an eager native grammar.
void validateCompiledGrammar(
  String modelPath,
  String grammar,
  Map<String, bool> candidates,
) {
  final path = modelPath.toNativeUtf8();
  final model = llama_model_load_from_file(
    path.cast<Char>(),
    llama_model_default_params()..vocab_only = true,
  );
  malloc.free(path);
  expect(model, isNot(nullptr));
  try {
    for (final entry in candidates.entries) {
      expect(
        _accepts(model, grammar, entry.key),
        entry.value,
        reason: entry.key,
      );
    }
  } finally {
    llama_model_free(model);
  }
}
