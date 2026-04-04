// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final typeId = 1;

  @override
  Message read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Message(
      id: fields[0] as String,
      conversationId: fields[1] as String,
      role: fields[2] as MessageRole,
      content: fields[3] as String,
      createdAt: fields[4] as DateTime,
      status: fields[5] == null
          ? MessageStatus.complete
          : fields[5] as MessageStatus,
      modelId: fields[6] as String?,
      tokenCount: (fields[7] as num?)?.toInt(),
      errorMessage: fields[8] as String?,
      attachmentPaths: (fields[9] as List?)?.cast<String>(),
      generationTimeMs: (fields[10] as num?)?.toInt(),
      reasoningContent: fields[11] as String?,
      toolCalls: (fields[12] as List?)?.cast<ToolCallData>(),
      toolCallId: fields[13] as String?,
      isProcessing: fields[14] == null ? false : fields[14] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.conversationId)
      ..writeByte(2)
      ..write(obj.role)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.modelId)
      ..writeByte(7)
      ..write(obj.tokenCount)
      ..writeByte(8)
      ..write(obj.errorMessage)
      ..writeByte(9)
      ..write(obj.attachmentPaths)
      ..writeByte(10)
      ..write(obj.generationTimeMs)
      ..writeByte(11)
      ..write(obj.reasoningContent)
      ..writeByte(12)
      ..write(obj.toolCalls)
      ..writeByte(13)
      ..write(obj.toolCallId)
      ..writeByte(14)
      ..write(obj.isProcessing);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
