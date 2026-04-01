// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SyntaxThemeNameAdapter extends TypeAdapter<SyntaxThemeName> {
  @override
  final typeId = 5;

  @override
  SyntaxThemeName read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return SyntaxThemeName.vscodeDark;
      case 1:
        return SyntaxThemeName.vscodeLight;
      case 2:
        return SyntaxThemeName.dracula;
      case 3:
        return SyntaxThemeName.monokaiSublime;
      case 4:
        return SyntaxThemeName.ayuLight;
      case 5:
        return SyntaxThemeName.ayuDark;
      case 6:
        return SyntaxThemeName.gravityLight;
      case 7:
        return SyntaxThemeName.gravityDark;
      case 8:
        return SyntaxThemeName.obsidian;
      case 9:
        return SyntaxThemeName.oceanSunset;
      case 10:
        return SyntaxThemeName.standard;
      default:
        return SyntaxThemeName.vscodeDark;
    }
  }

  @override
  void write(BinaryWriter writer, SyntaxThemeName obj) {
    switch (obj) {
      case SyntaxThemeName.vscodeDark:
        writer.writeByte(0);
        break;
      case SyntaxThemeName.vscodeLight:
        writer.writeByte(1);
        break;
      case SyntaxThemeName.dracula:
        writer.writeByte(2);
        break;
      case SyntaxThemeName.monokaiSublime:
        writer.writeByte(3);
        break;
      case SyntaxThemeName.ayuLight:
        writer.writeByte(4);
        break;
      case SyntaxThemeName.ayuDark:
        writer.writeByte(5);
        break;
      case SyntaxThemeName.gravityLight:
        writer.writeByte(6);
        break;
      case SyntaxThemeName.gravityDark:
        writer.writeByte(7);
        break;
      case SyntaxThemeName.obsidian:
        writer.writeByte(8);
        break;
      case SyntaxThemeName.oceanSunset:
        writer.writeByte(9);
        break;
      case SyntaxThemeName.standard:
        writer.writeByte(10);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyntaxThemeNameAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final typeId = 4;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      temperature: fields[0] == null ? 0.7 : (fields[0] as num).toDouble(),
      topP: fields[1] == null ? 0.9 : (fields[1] as num).toDouble(),
      maxTokens: fields[2] == null ? 2048 : (fields[2] as num).toInt(),
      contextLength: fields[3] == null ? 4096 : (fields[3] as num).toInt(),
      themeMode: fields[4] == null ? ThemeMode.dark : fields[4] as ThemeMode,
      fontSize: fields[5] == null ? 16.0 : (fields[5] as num).toDouble(),
      showSystemMessages: fields[6] == null ? false : fields[6] as bool,
      hapticFeedbackEnabled: fields[7] == null ? true : fields[7] as bool,
      sendOnEnter: fields[8] == null ? false : fields[8] as bool,
      defaultServerId: fields[9] as String?,
      showDataIndicator: fields[10] == null ? true : fields[10] as bool,
      autoGenerateTitle: fields[11] == null ? true : fields[11] as bool,
      streamingEnabled: fields[12] == null ? true : fields[12] as bool,
      defaultPersonaId: fields[13] as String?,
      hasCompletedOnboarding: fields[14] == null ? false : fields[14] as bool,
      mcpEnabled: fields[15] == null ? true : fields[15] as bool,
      codeTheme: fields[16] == null
          ? SyntaxThemeName.vscodeDark
          : fields[16] as SyntaxThemeName,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.temperature)
      ..writeByte(1)
      ..write(obj.topP)
      ..writeByte(2)
      ..write(obj.maxTokens)
      ..writeByte(3)
      ..write(obj.contextLength)
      ..writeByte(4)
      ..write(obj.themeMode)
      ..writeByte(5)
      ..write(obj.fontSize)
      ..writeByte(6)
      ..write(obj.showSystemMessages)
      ..writeByte(7)
      ..write(obj.hapticFeedbackEnabled)
      ..writeByte(8)
      ..write(obj.sendOnEnter)
      ..writeByte(9)
      ..write(obj.defaultServerId)
      ..writeByte(10)
      ..write(obj.showDataIndicator)
      ..writeByte(11)
      ..write(obj.autoGenerateTitle)
      ..writeByte(12)
      ..write(obj.streamingEnabled)
      ..writeByte(13)
      ..write(obj.defaultPersonaId)
      ..writeByte(14)
      ..write(obj.hasCompletedOnboarding)
      ..writeByte(15)
      ..write(obj.mcpEnabled)
      ..writeByte(16)
      ..write(obj.codeTheme);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
