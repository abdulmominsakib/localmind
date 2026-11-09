import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/providers/storage_providers.dart';
import '../data/huggingface_model_search_service.dart';
import '../utils/model_modality_classifier.dart';
import '../utils/model_param_size_parser.dart';

const String kShowSplitModelsPref = 'on_device_show_split_models';

enum UnifiedModelTypeFilter { both, litert, gguf, none }

class UnifiedModelSearchState {
  const UnifiedModelSearchState({
    this.query = '',
    this.modelType = UnifiedModelTypeFilter.both,
    this.modality, // null = all
    this.minParamBillions,
    this.maxParamBillions,
    this.includeUnknownParam = false,
    this.showSplitModels = false,
    this.results = const <HuggingFaceModelSearchResult>[],
    this.isLoading = false,
    this.error,
    this.hiddenUnknownCount = 0,
    this.hasSearched = false,
  });

  final String query;
  final UnifiedModelTypeFilter modelType;
  final ModelModality? modality;
  final double? minParamBillions;
  final double? maxParamBillions;
  final bool includeUnknownParam;
  final bool showSplitModels;
  final List<HuggingFaceModelSearchResult> results;
  final bool isLoading;
  final String? error;
  final int hiddenUnknownCount;
  final bool hasSearched;

  UnifiedModelSearchState copyWith({
    String? query,
    UnifiedModelTypeFilter? modelType,
    ModelModality? modality,
    bool clearModality = false,
    double? minParamBillions,
    bool clearMinParam = false,
    double? maxParamBillions,
    bool clearMaxParam = false,
    bool? includeUnknownParam,
    bool? showSplitModels,
    List<HuggingFaceModelSearchResult>? results,
    bool? isLoading,
    String? error,
    bool clearError = false,
    int? hiddenUnknownCount,
    bool? hasSearched,
  }) {
    return UnifiedModelSearchState(
      query: query ?? this.query,
      modelType: modelType ?? this.modelType,
      modality: clearModality ? null : (modality ?? this.modality),
      minParamBillions: clearMinParam
          ? null
          : (minParamBillions ?? this.minParamBillions),
      maxParamBillions: clearMaxParam
          ? null
          : (maxParamBillions ?? this.maxParamBillions),
      includeUnknownParam: includeUnknownParam ?? this.includeUnknownParam,
      showSplitModels: showSplitModels ?? this.showSplitModels,
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      hiddenUnknownCount: hiddenUnknownCount ?? this.hiddenUnknownCount,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

class UnifiedModelSearchNotifier extends Notifier<UnifiedModelSearchState> {
  CancelToken? _cancelToken;
  int _generation = 0;

  @override
  UnifiedModelSearchState build() {
    bool showSplit = false;
    try {
      showSplit = ref.read(sharedPreferencesProvider).getBool(kShowSplitModelsPref) ?? false;
    } catch (_) {
      showSplit = false;
    }
    return UnifiedModelSearchState(showSplitModels: showSplit);
  }

  HuggingFaceModelSearchService get _service =>
      HuggingFaceModelSearchService(dio: ref.read(dioProvider));

  String? get _token {
    try {
      return ref.read(settingsProvider).huggingFaceToken;
    } catch (_) {
      return null;
    }
  }

  void setQuery(String value) {
    state = state.copyWith(query: value);
  }

  void setModelType(UnifiedModelTypeFilter value) {
    state = state.copyWith(modelType: value);
  }

  void setLitertEnabled(bool enabled) {
    final gguf = state.modelType == UnifiedModelTypeFilter.gguf ||
        state.modelType == UnifiedModelTypeFilter.both;
    UnifiedModelTypeFilter next;
    if (enabled && gguf) {
      next = UnifiedModelTypeFilter.both;
    } else if (enabled) {
      next = UnifiedModelTypeFilter.litert;
    } else if (gguf) {
      next = UnifiedModelTypeFilter.gguf;
    } else {
      next = UnifiedModelTypeFilter.none;
    }
    state = state.copyWith(modelType: next);
  }

  void setGgufEnabled(bool enabled) {
    final litert = state.modelType == UnifiedModelTypeFilter.litert ||
        state.modelType == UnifiedModelTypeFilter.both;
    UnifiedModelTypeFilter next;
    if (litert && enabled) {
      next = UnifiedModelTypeFilter.both;
    } else if (litert) {
      next = UnifiedModelTypeFilter.litert;
    } else if (enabled) {
      next = UnifiedModelTypeFilter.gguf;
    } else {
      next = UnifiedModelTypeFilter.none;
    }
    state = state.copyWith(modelType: next);
  }

  void setModality(ModelModality? value) {
    if (value == null) {
      state = state.copyWith(clearModality: true);
    } else {
      state = state.copyWith(modality: value);
    }
  }

  void setMinParam(String? text) {
    final parsed = _parseParam(text);
    if (parsed == null && (text == null || text.trim().isEmpty)) {
      state = state.copyWith(clearMinParam: true);
    } else if (parsed != null) {
      state = state.copyWith(minParamBillions: parsed);
    }
  }

  void setMaxParam(String? text) {
    final parsed = _parseParam(text);
    if (parsed == null && (text == null || text.trim().isEmpty)) {
      state = state.copyWith(clearMaxParam: true);
    } else if (parsed != null) {
      state = state.copyWith(maxParamBillions: parsed);
    }
  }

  double? _parseParam(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    return double.tryParse(text.trim());
  }

  void setIncludeUnknownParam(bool value) {
    state = state.copyWith(includeUnknownParam: value);
  }

  void setShowSplitModels(bool value) {
    state = state.copyWith(showSplitModels: value);
    try {
      ref.read(sharedPreferencesProvider).setBool(kShowSplitModelsPref, value);
    } catch (_) {}
  }

  Future<void> search() async {
    _cancelToken?.cancel('New search started');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    final generation = ++_generation;

    final trimmedQuery = state.query.trim();

    if (trimmedQuery.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        results: const [],
        clearError: true,
        hiddenUnknownCount: 0,
        hasSearched: false,
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true, results: const []);

    final filters = _filtersFor(state.modelType);
    final merged = <String, HuggingFaceModelSearchResult>{};
    int hiddenUnknown = 0;

    try {
      for (final filter in filters) {
        if (cancelToken.isCancelled) return;
        try {
          final repos = await _service.searchModels(
            query: trimmedQuery,
            filter: filter,
            token: _token,
            cancelToken: cancelToken,
          );
          if (cancelToken.isCancelled || generation != _generation) return;
          for (final repo in repos) {
            merged.putIfAbsent(repo.repoId, () => repo);
          }
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) return;
          // One filter failing should not abort the whole search; continue.
          state = state.copyWith(error: e.toString());
        }
      }
      if (cancelToken.isCancelled || generation != _generation) return;

      // Modality filter (client-side).
      var filtered = merged.values.toList();
      if (state.modality != null) {
        filtered = filtered.where((r) {
          final m = classifyModality(
            pipelineTag: r.pipelineTag,
            tags: r.tags,
            name: r.name,
          );
          return m == state.modality;
        }).toList();
      }

      // Param size filter (client-side) with hidden-unknown counting.
      final hasRange = state.minParamBillions != null || state.maxParamBillions != null;
      if (hasRange) {
        final kept = <HuggingFaceModelSearchResult>[];
        for (final r in filtered) {
          final size = parseParameterSizeBillions(r.repoId);
          if (size == null) {
            hiddenUnknown++;
            if (state.includeUnknownParam) kept.add(r);
          } else {
            final min = state.minParamBillions;
            final max = state.maxParamBillions;
            final okMin = min == null || size >= min;
            final okMax = max == null || size <= max;
            if (okMin && okMax) kept.add(r);
          }
        }
        filtered = kept;
      }

      state = state.copyWith(
        results: filtered,
        isLoading: false,
        hiddenUnknownCount: hiddenUnknown,
        hasSearched: true,
      );
    } catch (e) {
      if (cancelToken.isCancelled || generation != _generation) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    } finally {
      if (identical(_cancelToken, cancelToken)) {
        _cancelToken = null;
      }
    }
  }

  void cancel() {
    _cancelToken?.cancel('User canceled');
    _cancelToken = null;
    state = state.copyWith(isLoading: false);
  }

  void clearResults() {
    state = state.copyWith(results: const [], hiddenUnknownCount: 0);
  }

  List<String?> _filtersFor(UnifiedModelTypeFilter type) {
    switch (type) {
      case UnifiedModelTypeFilter.both:
        return ['gguf', 'litert-lm', 'litertlm'];
      case UnifiedModelTypeFilter.litert:
        return ['litert-lm', 'litertlm'];
      case UnifiedModelTypeFilter.gguf:
        return ['gguf'];
      case UnifiedModelTypeFilter.none:
        return [null];
    }
  }
}

final unifiedModelSearchProvider =
    NotifierProvider<UnifiedModelSearchNotifier, UnifiedModelSearchState>(
  UnifiedModelSearchNotifier.new,
);
