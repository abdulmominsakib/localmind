import 'package:localmind/core/constants/app_constants.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/models/providers/model_picker_providers.dart';

/// Whether [model] is a provider's routed model. The default picker order
/// lists it ahead of the pinned models it routes between.
bool isRouterModel(ModelInfo model) =>
    model.serverType == ServerType.standardCompute &&
    model.id == AppConstants.standardComputeRoutedModelId;

/// Returns [models] in picker order for [option].
///
/// The default [ModelSortOption.favorites] order lists favorites first, then
/// router models, then the rest by display name. The explicit sorts keep
/// their own order.
List<ModelInfo> sortPickerModels(
  List<ModelInfo> models,
  ModelSortOption option, {
  required bool Function(ModelInfo model) isFavorite,
}) {
  final sorted = List<ModelInfo>.from(models);

  int byName(ModelInfo a, ModelInfo b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

  switch (option) {
    case ModelSortOption.favorites:
      sorted.sort((a, b) {
        final aFavorite = isFavorite(a);
        final bFavorite = isFavorite(b);
        if (aFavorite != bFavorite) return aFavorite ? -1 : 1;
        final aRouter = isRouterModel(a);
        final bRouter = isRouterModel(b);
        if (aRouter != bRouter) return aRouter ? -1 : 1;
        return byName(a, b);
      });
    case ModelSortOption.nameAsc:
      sorted.sort(byName);
    case ModelSortOption.sizeAsc:
      sorted.sort((a, b) {
        final size = (a.fileSize ?? 0).compareTo(b.fileSize ?? 0);
        return size != 0 ? size : byName(a, b);
      });
    case ModelSortOption.sizeDesc:
      sorted.sort((a, b) {
        final size = (b.fileSize ?? 0).compareTo(a.fileSize ?? 0);
        return size != 0 ? size : byName(a, b);
      });
    case ModelSortOption.contextDesc:
      sorted.sort((a, b) {
        final ctx = (b.contextLength ?? 0).compareTo(a.contextLength ?? 0);
        return ctx != 0 ? ctx : byName(a, b);
      });
  }

  return sorted;
}
