// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ServerAdapter extends TypeAdapter<Server> {
  @override
  final typeId = 0;

  @override
  Server read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Server(
      id: fields[0] as String,
      name: fields[1] as String,
      type: fields[2] as ServerType,
      host: fields[3] as String,
      port: (fields[4] as num).toInt(),
      apiKey: fields[5] as String?,
      isDefault: fields[6] == null ? false : fields[6] as bool,
      createdAt: fields[7] as DateTime,
      lastConnectedAt: fields[8] as DateTime,
      status: fields[9] == null
          ? ConnectionStatus.disconnected
          : fields[9] as ConnectionStatus,
      iconName: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Server obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.host)
      ..writeByte(4)
      ..write(obj.port)
      ..writeByte(5)
      ..write(obj.apiKey)
      ..writeByte(6)
      ..write(obj.isDefault)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.lastConnectedAt)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.iconName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
