
/// Returns true for split/multi-part GGUF files such as
/// `model-00001-of-00004.gguf`.
bool isSplitModelFile(String nameOrPath) {
  final name = nameOrPath.split('/').last.toLowerCase();
  return RegExp(r'-\d{5}-of-\d{5}\.').hasMatch(name);
}

/// Returns true for projector (mmproj) files.
bool isProjectorFile(String nameOrPath) {
  final name = nameOrPath.split('/').last.toLowerCase();
  return name.startsWith('mmproj') || name.contains('mmproj');
}

/// Returns true for a primary model file (.gguf or .litertlm) that is neither
/// a split part nor a projector.
bool isPrimaryModelFile(String nameOrPath) {
  final name = nameOrPath.split('/').last.toLowerCase();
  final isModelExt = name.endsWith('.gguf') || name.endsWith('.litertlm');
  if (!isModelExt) return false;
  if (isProjectorFile(name)) return false;
  if (isSplitModelFile(name)) return false;
  return true;
}
