import 'package:localmind/features/models/data/models/model_info.dart';

import '../data/catalog_models.dart';

String _normalize(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Whether [quant] of [model] is already present on the server, matched by
/// comparing the local model's own `quantization` field (not a loose
/// substring search over its display name/id) plus a normalized identity
/// check against the catalog model's name/owner.
bool isQuantDownloaded({
  required LmCatalogModel model,
  required LmModelQuantOption quant,
  required List<ModelInfo> downloadedModels,
}) {
  final targetQuant = _normalize(quant.quantization);
  if (targetQuant.isEmpty) return false;

  final modelNameNorm = _normalize(model.name);
  final catalogIdNorm = _normalize(model.catalogId);

  for (final local in downloadedModels) {
    final localQuant = _normalize(local.quantization ?? '');
    if (localQuant.isEmpty || localQuant != targetQuant) continue;

    final idNorm = _normalize(local.id);
    final nameNorm = _normalize(local.name);
    if (idNorm.contains(modelNameNorm) ||
        nameNorm.contains(modelNameNorm) ||
        idNorm.contains(catalogIdNorm) ||
        (idNorm.isNotEmpty && modelNameNorm.contains(idNorm))) {
      return true;
    }
  }
  return false;
}
