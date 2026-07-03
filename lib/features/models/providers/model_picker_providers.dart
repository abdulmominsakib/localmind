import 'package:flutter_riverpod/flutter_riverpod.dart';

final modelSearchQueryProvider = NotifierProvider<ModelSearchNotifier, String>(
  ModelSearchNotifier.new,
);

class ModelSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String q) => state = q;
  void clear() => state = '';
}

enum ModelSortOption { favorites, nameAsc, sizeAsc, sizeDesc, contextDesc }

final modelSortOptionProvider =
    NotifierProvider<ModelSortNotifier, ModelSortOption>(
      ModelSortNotifier.new,
    );

class ModelSortNotifier extends Notifier<ModelSortOption> {
  @override
  ModelSortOption build() => ModelSortOption.favorites;

  void setOption(ModelSortOption option) => state = option;
}
