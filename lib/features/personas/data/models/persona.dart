import 'package:hive_ce/hive.dart';

part 'persona.g.dart';

@HiveType(typeId: 3)
class Persona extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String emoji;

  @HiveField(3)
  final String systemPrompt;

  @HiveField(4)
  final String? description;

  @HiveField(5)
  final bool isBuiltIn;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  final DateTime updatedAt;

  @HiveField(8)
  final String? category;

  @HiveField(9)
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
