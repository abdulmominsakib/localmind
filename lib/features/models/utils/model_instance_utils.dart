bool isModelKeyLoaded(Set<String> instanceIds, String modelKey) {
  return instanceIds.any((id) => id == modelKey || id.startsWith('$modelKey:'));
}

List<String> instanceIdsForModelKey(Set<String> instanceIds, String modelKey) {
  return instanceIds
      .where((id) => id == modelKey || id.startsWith('$modelKey:'))
      .toList();
}

String modelKeyFromInstanceId(String instanceId) {
  final colonIndex = instanceId.lastIndexOf(':');
  if (colonIndex <= 0) return instanceId;
  final suffix = instanceId.substring(colonIndex + 1);
  if (int.tryParse(suffix) != null) {
    return instanceId.substring(0, colonIndex);
  }
  return instanceId;
}
