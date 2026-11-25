part of 'llama_cpp_service.dart';

/// Native query/document classifier scoring on the service's owned context.
extension NativeReranking on LlamaCppService {
  /// Explicit owning-load path, requiring a real classifier tensor directory.
  int createRerankingContext(int modelHandle, ModelParams params) {
    final model = _models[modelHandle];
    if (model == null) {
      throw LlamaStateException('The reranker model is no longer loaded.');
    }
    final info = _calls.rerankingModelInfo(model.pointer);
    final source = model.sourcePath;
    if ((info.encoder && info.decoder) ||
        source == null ||
        !hasRerankingClassifier(source, info.labels.length)) {
      throw LlamaUnsupportedException(
        'Explicit native reranker loading requires a GGUF with a verified classifier head matching n_cls_out; ordinary chat/embedding models and unverified tensor directories are unsupported.',
      );
    }
    return createContext(modelHandle, params, reranking: true);
  }

  /// Checks effective pooling and actual allocated limits before inference.
  LlamaRerankingCapabilities getRerankingCapabilities(int contextHandle) {
    final context = _contexts[contextHandle];
    final model = _models[_contextToModel[contextHandle]];
    if (context == null || model == null) {
      return LlamaRerankingCapabilities(
        isSupported: false,
        unsupportedReason: 'Load a native llama.cpp reranker model first.',
      );
    }
    _ensureContextUsable(contextHandle, context);
    final limits = _calls.embeddingContextInfo(context.pointer);
    if (limits.pooling != llama_pooling_type.LLAMA_POOLING_TYPE_RANK) {
      return LlamaRerankingCapabilities(
        isSupported: false,
        unsupportedReason:
            'Native reranking requires a GGUF model with RANK pooling; ordinary embeddings and chat models cannot rerank.',
      );
    }
    final info = _calls.rerankingModelInfo(model.pointer);
    if (info.encoder && info.decoder) {
      return LlamaRerankingCapabilities(
        isSupported: false,
        unsupportedReason:
            'Native reranking supports encoder-only or decoder-only models, not encoder-decoder models.',
      );
    }
    return LlamaRerankingCapabilities(
      isSupported: true,
      classifierLabels: info.labels,
      maxInputTokens: limits.capacity,
      maxParallelSequences: limits.sequences,
    );
  }

  /// Preflights all complete pairs before any encoding/decoding or memory reset.
  BackendRerankingOutput rerank(
    int contextHandle,
    String query,
    List<String> documents, {
    Pointer<Int8>? cancelToken,
  }) {
    _ensureNoActiveTts(contextHandle, 'rerank');
    _contexts[contextHandle]?.performanceAvailable = false;
    final support = getRerankingCapabilities(contextHandle);
    if (!support.isSupported) {
      throw LlamaUnsupportedException(support.unsupportedReason!);
    }
    final context = _contexts[contextHandle]!;
    final model = _models[_contextToModel[contextHandle]]!;
    final info = _calls.rerankingModelInfo(model.pointer);
    void checkCancelled() {
      if (cancelToken != null &&
          cancelToken != nullptr &&
          cancelToken.value != 0) {
        throw LlamaInferenceException('Native reranking cancelled.');
      }
    }

    final prepared = <List<int>>[];
    for (var index = 0; index < documents.length; index++) {
      checkCancelled();
      final tokens = _rerankTokens(
        info.vocab,
        query,
        documents[index],
        info.template,
      );
      if (tokens.isEmpty || tokens.length > support.maxInputTokens) {
        throw LlamaInferenceException(
          'Reranking pair $index has ${tokens.length} tokens; a complete pair must fit contextSize, batchSize and microBatchSize (effective capacity ${support.maxInputTokens}). Shorten the input or increase those limits.',
        );
      }
      prepared.add(tokens);
    }
    if (prepared.isEmpty) {
      return BackendRerankingOutput(
        scores: const [],
        classifierLabels: info.labels,
      );
    }
    checkCancelled();
    _calls.synchronize(context.pointer);
    _resetRequestPerformance(contextHandle, context);
    final scores = <List<double>>[];
    var start = 0;
    while (start < prepared.length) {
      checkCancelled();
      var end = start;
      var count = 0;
      while (end < prepared.length &&
          end - start < support.maxParallelSequences &&
          count + prepared[end].length <= support.maxInputTokens) {
        count += prepared[end++].length;
      }
      if (end == start) {
        throw LlamaInferenceException(
          'No complete reranking pair fits the allocated batch.',
        );
      }
      final batch = _batchInit(count, 0, 1);
      try {
        _clearContextMemory(context.pointer, strict: false);
        context.cachedPromptTokens = null;
        _calls.setRerankingOutput(context.pointer, true);
        batch.n_tokens = count;
        var row = 0;
        for (var item = start; item < end; item++) {
          final tokens = prepared[item];
          for (var pos = 0; pos < tokens.length; pos++, row++) {
            batch.token[row] = tokens[pos];
            batch.pos[row] = pos;
            batch.n_seq_id[row] = 1;
            batch.seq_id[row][0] = item - start;
            batch.logits[row] = 1;
          }
        }
        checkCancelled();
        final status = info.encoder
            ? _calls.encode(context.pointer, batch)
            : _calls.decode(context.pointer, batch);
        if (status != 0) {
          throw LlamaInferenceException(
            'Native reranking forward pass failed.',
          );
        }
        checkCancelled();
        for (var item = start; item < end; item++) {
          final output = _calls.rerankingOutput(
            context.pointer,
            item - start,
            info.labels.length,
          );
          if (output.any((value) => !value.isFinite)) {
            throw LlamaInferenceException(
              'Native reranking returned nonfinite classifier scores.',
            );
          }
          scores.add(output);
        }
      } finally {
        _calls.setRerankingOutput(context.pointer, false);
        _batchFree(batch);
      }
      start = end;
    }
    checkCancelled();
    return BackendRerankingOutput(
      scores: scores,
      classifierLabels: info.labels,
    );
  }

  List<int> _rerankTokens(
    Pointer<llama_vocab> vocab,
    String query,
    String document,
    String? template,
  ) {
    if (template != null) {
      // Match upstream's ordered substitution, including placeholders in inputs.
      final prompt = template
          .replaceAll('{query}', query)
          .replaceAll('{document}', document);
      return _rerankTokenize(vocab, prompt, parseSpecial: true);
    }
    final special = _calls.rerankingSpecialTokens(vocab);
    if ([
      special.bos,
      special.eos,
      special.sep,
    ].any((token) => token == LLAMA_TOKEN_NULL)) {
      throw LlamaUnsupportedException(
        'The reranker vocabulary lacks a required BOS, EOS or SEP token.',
      );
    }
    return [
      if (special.bos != null) special.bos!,
      ..._rerankTokenize(vocab, query, parseSpecial: false),
      if (special.eos != null) special.eos!,
      if (special.sep != null) special.sep!,
      ..._rerankTokenize(vocab, document, parseSpecial: false),
      if (special.eos != null) special.eos!,
    ];
  }

  List<int> _rerankTokenize(
    Pointer<llama_vocab> vocab,
    String text, {
    required bool parseSpecial,
  }) {
    final (textPtr, length) = _toNativeUtf8WithLength(text);
    try {
      final required = -_calls.tokenize(
        vocab,
        textPtr.cast(),
        length,
        nullptr,
        0,
        false,
        parseSpecial,
      );
      if (required == 0) return const [];
      if (required < 0) {
        throw LlamaInferenceException('Native reranking token sizing failed.');
      }
      final tokens = malloc<Int32>(required);
      try {
        final count = _calls.tokenize(
          vocab,
          textPtr.cast(),
          length,
          tokens,
          required,
          false,
          parseSpecial,
        );
        if (count != required) {
          throw LlamaInferenceException(
            'Native reranking tokenization failed.',
          );
        }
        return List<int>.of(tokens.asTypedList(count));
      } finally {
        malloc.free(tokens);
      }
    } finally {
      malloc.free(textPtr);
    }
  }
}
