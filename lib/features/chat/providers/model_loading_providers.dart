import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'model_selection_providers.dart';

class ModelLoadingState {
  final bool isLoading;
  final String? modelId;
  final double? progress;

  const ModelLoadingState({
    this.isLoading = false,
    this.modelId,
    this.progress,
  });

  ModelLoadingState copyWith({
    bool? isLoading,
    String? modelId,
    double? progress,
  }) {
    return ModelLoadingState(
      isLoading: isLoading ?? this.isLoading,
      modelId: modelId ?? this.modelId,
      progress: progress ?? this.progress,
    );
  }
}

final modelLoadingProvider =
    NotifierProvider<ModelLoadingNotifier, ModelLoadingState>(() {
      return ModelLoadingNotifier();
    });

class ModelLoadingNotifier extends Notifier<ModelLoadingState> {
  @override
  ModelLoadingState build() => const ModelLoadingState();

  void setLoading(String modelId, {double? progress}) {
    state = ModelLoadingState(
      isLoading: true,
      modelId: modelId,
      progress: progress,
    );
  }

  void updateProgress(double progress) {
    state = state.copyWith(progress: progress);
  }

  void setLoaded() {
    state = const ModelLoadingState();
  }
}

final modelThinkingProvider = Provider<bool>((ref) {
  return ref.watch(isStreamingProvider);
});
