class Persona {
  final String id;
  final String name;
  final String emoji;
  final String systemPrompt;
  final String? description;
  final bool isBuiltIn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? category;
  final Map<String, dynamic>? preferredParams;

  Persona({
    required this.id,
    required this.name,
    required this.emoji,
    required this.systemPrompt,
    this.description,
    this.isBuiltIn = false,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.preferredParams,
  });

  Persona copyWith({
    String? id,
    String? name,
    String? emoji,
    String? systemPrompt,
    String? description,
    bool? isBuiltIn,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? category,
    Map<String, dynamic>? preferredParams,
  }) {
    return Persona(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      description: description ?? this.description,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      category: category ?? this.category,
      preferredParams: preferredParams ?? this.preferredParams,
    );
  }
}
