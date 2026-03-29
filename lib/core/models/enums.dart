import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

enum ServerType { lmStudio, ollama, openRouter }

enum ConnectionStatus { connected, disconnected, checking, error }

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, streaming, complete, error }

class ServerTypeAdapter extends TypeAdapter<ServerType> {
  @override
  final int typeId = 10;

  @override
  ServerType read(BinaryReader reader) {
    return ServerType.values[reader.readInt()];
  }

  @override
  void write(BinaryWriter writer, ServerType obj) {
    writer.writeInt(obj.index);
  }
}

class ConnectionStatusAdapter extends TypeAdapter<ConnectionStatus> {
  @override
  final int typeId = 11;

  @override
  ConnectionStatus read(BinaryReader reader) {
    return ConnectionStatus.values[reader.readInt()];
  }

  @override
  void write(BinaryWriter writer, ConnectionStatus obj) {
    writer.writeInt(obj.index);
  }
}

class MessageRoleAdapter extends TypeAdapter<MessageRole> {
  @override
  final int typeId = 12;

  @override
  MessageRole read(BinaryReader reader) {
    return MessageRole.values[reader.readInt()];
  }

  @override
  void write(BinaryWriter writer, MessageRole obj) {
    writer.writeInt(obj.index);
  }
}

class MessageStatusAdapter extends TypeAdapter<MessageStatus> {
  @override
  final int typeId = 13;

  @override
  MessageStatus read(BinaryReader reader) {
    return MessageStatus.values[reader.readInt()];
  }

  @override
  void write(BinaryWriter writer, MessageStatus obj) {
    writer.writeInt(obj.index);
  }
}

class ThemeModeAdapter extends TypeAdapter<ThemeMode> {
  @override
  final int typeId = 14;

  @override
  ThemeMode read(BinaryReader reader) {
    return ThemeMode.values[reader.readInt()];
  }

  @override
  void write(BinaryWriter writer, ThemeMode obj) {
    writer.writeInt(obj.index);
  }
}
