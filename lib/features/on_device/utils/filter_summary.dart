/// Pure helper for the filter bar summary text. Extracted for unit testing.

enum FilterFramework { litert, gguf, both, none }

String formatFilterSummary({
  required bool litertEnabled,
  required bool ggufEnabled,
  required String? modalityLabel,
  required double? minParamBillions,
  required double? maxParamBillions,
  String litertLabel = 'LiteRT',
  String ggufLabel = 'GGUF',
  String bothLabel = 'Both',
  String noneLabel = 'No framework',
}) {
  final parts = <String>[];
  if (litertEnabled && !ggufEnabled) parts.add(litertLabel);
  if (!litertEnabled && ggufEnabled) parts.add(ggufLabel);
  if (litertEnabled && ggufEnabled) parts.add(bothLabel);
  if (!litertEnabled && !ggufEnabled) parts.add(noneLabel);
  if (modalityLabel != null) parts.add(modalityLabel);
  if (minParamBillions != null || maxParamBillions != null) {
    final min = minParamBillions;
    final max = maxParamBillions;
    if (min != null && max != null) {
      parts.add('${min.toStringAsFixed(0)}-${max.toStringAsFixed(0)}B');
    } else if (min != null) {
      parts.add('>=${min.toStringAsFixed(0)}B');
    } else if (max != null) {
      parts.add('<=${max.toStringAsFixed(0)}B');
    }
  }
  return parts.join(' · ');
}