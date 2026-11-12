part of 'litert_lm_v1_runtime.dart';

typedef _TokenizeN =
    Int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _TokenizeD =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Pointer<Void>>);
typedef _DetokenizeN =
    Int Function(Pointer<Void>, Pointer<Int>, Size, Pointer<Pointer<Void>>);
typedef _DetokenizeD =
    int Function(Pointer<Void>, Pointer<Int>, int, Pointer<Pointer<Void>>);
typedef _TokenCountN = Int Function(Pointer<Void>, Pointer<Size>);
typedef _TokenCountD = int Function(Pointer<Void>, Pointer<Size>);
typedef _TokenPointerN = Int Function(Pointer<Void>, Pointer<Pointer<Int>>);
typedef _TokenPointerD = int Function(Pointer<Void>, Pointer<Pointer<Int>>);
typedef _TokenStringN = Int Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _TokenStringD = int Function(Pointer<Void>, Pointer<Pointer<Utf8>>);
typedef _TokenTypeN = Int Function(Pointer<Void>, Pointer<Int>);
typedef _TokenTypeD = int Function(Pointer<Void>, Pointer<Int>);
typedef _TokenIdsN =
    Int Function(Pointer<Void>, Pointer<Pointer<Int>>, Pointer<Size>);
typedef _TokenIdsD =
    int Function(Pointer<Void>, Pointer<Pointer<Int>>, Pointer<Size>);

final class _V1TokenizerBindings {
  _V1TokenizerBindings(this.library) {
    for (final symbol in _symbols) {
      if (!library.providesSymbol(symbol)) {
        throw LlamaUnsupportedException(
          'C API 1.0 tokenizer requires native export $symbol.',
        );
      }
    }
  }

  static const _symbols = <String>[
    'litert_lm_engine_tokenize',
    'litert_lm_tokenize_result_delete',
    'litert_lm_tokenize_result_get_tokens',
    'litert_lm_tokenize_result_get_num_tokens',
    'litert_lm_engine_detokenize',
    'litert_lm_detokenize_result_delete',
    'litert_lm_detokenize_result_get_string',
    'litert_lm_engine_get_start_token',
    'litert_lm_token_union_delete',
    'litert_lm_token_union_get_type',
    'litert_lm_token_union_get_string',
    'litert_lm_token_union_get_ids',
  ];

  final DynamicLibrary library;
  late final _tokenize = library.lookupFunction<_TokenizeN, _TokenizeD>(
    'litert_lm_engine_tokenize',
  );
  late final _deleteTokens = library.lookupFunction<_DeleteN, _DeleteD>(
    'litert_lm_tokenize_result_delete',
  );
  late final _tokens = library.lookupFunction<_TokenPointerN, _TokenPointerD>(
    'litert_lm_tokenize_result_get_tokens',
  );
  late final _count = library.lookupFunction<_TokenCountN, _TokenCountD>(
    'litert_lm_tokenize_result_get_num_tokens',
  );
  late final _detokenize = library.lookupFunction<_DetokenizeN, _DetokenizeD>(
    'litert_lm_engine_detokenize',
  );
  late final _deleteText = library.lookupFunction<_DeleteN, _DeleteD>(
    'litert_lm_detokenize_result_delete',
  );
  late final _text = library.lookupFunction<_TokenStringN, _TokenStringD>(
    'litert_lm_detokenize_result_get_string',
  );
  late final _start = library.lookupFunction<_CreateFromN, _CreateFromD>(
    'litert_lm_engine_get_start_token',
  );
  late final _deleteUnion = library.lookupFunction<_DeleteN, _DeleteD>(
    'litert_lm_token_union_delete',
  );
  late final _type = library.lookupFunction<_TokenTypeN, _TokenTypeD>(
    'litert_lm_token_union_get_type',
  );
  late final _string = library.lookupFunction<_TokenStringN, _TokenStringD>(
    'litert_lm_token_union_get_string',
  );
  late final _ids = library.lookupFunction<_TokenIdsN, _TokenIdsD>(
    'litert_lm_token_union_get_ids',
  );

  List<int> tokenize(
    LiteRtLmV1Runtime runtime,
    String text, {
    required bool addSpecial,
  }) {
    final tokens = _raw(runtime, text);
    if (!addSpecial) return tokens;
    return [..._startTokens(runtime), ...tokens];
  }

  List<int> _copyTokens(Pointer<Int> tokens, int count) {
    if (count < 0 || count > 0x7fffffff || (count > 0 && tokens == nullptr)) {
      throw LlamaStateException(
        'C API 1.0 tokenizer returned an invalid token array/count.',
      );
    }
    return List<int>.generate(count, (index) => tokens[index]);
  }

  List<int> _raw(LiteRtLmV1Runtime runtime, String text) {
    final input = text.toNativeUtf8(allocator: calloc);
    final output = calloc<Pointer<Void>>();
    final tokens = calloc<Pointer<Int>>();
    final count = calloc<Size>();
    Pointer<Void> result = nullptr;
    try {
      final status = _tokenize(runtime._engine, input, output);
      result = output.value;
      runtime._check(status, 'engine_tokenize');
      if (result == nullptr) {
        throw LlamaStateException(
          'engine_tokenize reported success without a result.',
        );
      }
      runtime._check(_count(result, count), 'tokenize_result_get_num_tokens');
      runtime._check(_tokens(result, tokens), 'tokenize_result_get_tokens');
      return _copyTokens(tokens.value, count.value);
    } finally {
      if (result != nullptr) _deleteTokens(result);
      calloc.free(count);
      calloc.free(tokens);
      calloc.free(output);
      calloc.free(input);
    }
  }

  List<int> _startTokens(LiteRtLmV1Runtime runtime) {
    final output = calloc<Pointer<Void>>();
    final type = calloc<Int>();
    final string = calloc<Pointer<Utf8>>();
    final tokens = calloc<Pointer<Int>>();
    final count = calloc<Size>();
    Pointer<Void> result = nullptr;
    try {
      final status = _start(runtime._engine, output);
      result = output.value;
      runtime._check(status, 'engine_get_start_token');
      // The v1 contract explicitly permits success with no configured BOS.
      if (result == nullptr) return const [];
      runtime._check(_type(result, type), 'token_union_get_type');
      switch (type.value) {
        case 1:
          runtime._check(_ids(result, tokens, count), 'token_union_get_ids');
          return _copyTokens(tokens.value, count.value);
        case 0:
          runtime._check(_string(result, string), 'token_union_get_string');
          if (string.value == nullptr) {
            throw LlamaStateException(
              'token_union_get_string reported success without a string.',
            );
          }
          final text = string.value.toDartString();
          return text.isEmpty ? const [] : _raw(runtime, text);
        default:
          throw LlamaUnsupportedException(
            'C API 1.0 tokenizer returned unknown token union type ${type.value}.',
          );
      }
    } finally {
      if (result != nullptr) _deleteUnion(result);
      calloc.free(count);
      calloc.free(tokens);
      calloc.free(string);
      calloc.free(type);
      calloc.free(output);
    }
  }

  String detokenize(LiteRtLmV1Runtime runtime, List<int> tokens) {
    final input = calloc<Int>(tokens.length);
    final output = calloc<Pointer<Void>>();
    final text = calloc<Pointer<Utf8>>();
    Pointer<Void> result = nullptr;
    try {
      for (var i = 0; i < tokens.length; ++i) {
        input[i] = tokens[i];
      }
      final status = _detokenize(runtime._engine, input, tokens.length, output);
      result = output.value;
      runtime._check(status, 'engine_detokenize');
      if (result == nullptr) {
        throw LlamaStateException(
          'engine_detokenize reported success without a result.',
        );
      }
      runtime._check(_text(result, text), 'detokenize_result_get_string');
      if (text.value == nullptr) {
        throw LlamaStateException(
          'detokenize_result_get_string reported success without a string.',
        );
      }
      return text.value.toDartString();
    } finally {
      if (result != nullptr) _deleteText(result);
      calloc.free(text);
      calloc.free(output);
      calloc.free(input);
    }
  }
}
