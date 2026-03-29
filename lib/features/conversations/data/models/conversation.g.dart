// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ConversationAdapter extends TypeAdapter<Conversation> {
  @override
  final typeId = 2;

  @override
  Conversation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Conversation(
      id: fields[0] as String,
      title: fields[1] as String,
      createdAt: fields[2] as DateTime,
      updatedAt: fields[3] as DateTime,
      isPinned: fields[4] == null ? false : fields[4] as bool,
      personaId: fields[5] as String?,
      serverId: fields[6] as String?,
      modelId: fields[7] as String?,
      messageCount: fields[8] == null ? 0 : (fields[8] as num).toInt(),
      lastMessagePreview: fields[9] as String?,
      systemPrompt: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Conversation obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt)
      ..writeByte(4)
      ..write(obj.isPinned)
      ..writeByte(5)
      ..write(obj.personaId)
      ..writeByte(6)
      ..write(obj.serverId)
      ..writeByte(7)
      ..write(obj.modelId)
      ..writeByte(8)
      ..write(obj.messageCount)
      ..writeByte(9)
      ..write(obj.lastMessagePreview)
      ..writeByte(10)
      ..write(obj.systemPrompt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConversationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
