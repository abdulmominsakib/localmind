// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'persona.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PersonaAdapter extends TypeAdapter<Persona> {
  @override
  final typeId = 3;

  @override
  Persona read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Persona(
      id: fields[0] as String,
      name: fields[1] as String,
      emoji: fields[2] as String,
      systemPrompt: fields[3] as String,
      description: fields[4] as String?,
      isBuiltIn: fields[5] == null ? false : fields[5] as bool,
      createdAt: fields[6] as DateTime,
      updatedAt: fields[7] as DateTime,
      category: fields[8] as String?,
      preferredParams: (fields[9] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, Persona obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.emoji)
      ..writeByte(3)
      ..write(obj.systemPrompt)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.isBuiltIn)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.category)
      ..writeByte(9)
      ..write(obj.preferredParams);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersonaAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
