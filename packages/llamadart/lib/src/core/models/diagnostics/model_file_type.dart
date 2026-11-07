/// Model file type and quantization metadata for a loaded model.
///
/// For llama.cpp/GGUF models, [id] is the native `llama_ftype` enum value and
/// [name] is the human-readable value returned by `llama_ftype_name`, such as
/// `Q8_0` or `Q4_K - Medium`.
class ModelFileType {
  /// Native model file type identifier.
  final int id;

  /// Human-readable model file type name.
  final String name;

  /// Creates a new [ModelFileType].
  const ModelFileType({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelFileType && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'ModelFileType(id: $id, name: $name)';
}
