import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 4)
class AppSettings extends HiveObject {
  @HiveField(0)
  final double temperature;

  @HiveField(1)
  final double topP;

  @HiveField(2)
  final int maxTokens;

  @HiveField(3)
  final int contextLength;

  @HiveField(4)
  final ThemeMode themeMode;

  @HiveField(5)
  final double fontSize;

  @HiveField(6)
  final bool showSystemMessages;

  @HiveField(7)
  final bool hapticFeedbackEnabled;

  @HiveField(8)
  final bool sendOnEnter;

  @HiveField(9)
  final String? defaultServerId;

  @HiveField(10)
  final bool showDataIndicator;

  @HiveField(11)
  final bool autoGenerateTitle;

  @HiveField(12)
  final bool streamingEnabled;

  @HiveField(13)
  final String? defaultPersonaId;

  @HiveField(14, defaultValue: false)
  final bool hasCompletedOnboarding;

  @HiveField(15, defaultValue: true)
  final bool mcpEnabled;

  AppSettings({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.maxTokens = 2048,
    this.contextLength = 4096,
    this.themeMode = ThemeMode.dark,
    this.fontSize = 16.0,
    this.showSystemMessages = false,
    this.hapticFeedbackEnabled = true,
    this.sendOnEnter = false,
    this.defaultServerId,
    this.showDataIndicator = true,
    this.autoGenerateTitle = true,
    this.streamingEnabled = true,
    this.defaultPersonaId,
    this.hasCompletedOnboarding = false,
    this.mcpEnabled = true,
  });

  AppSettings copyWith({
    double? temperature,
    double? topP,
    int? maxTokens,
    int? contextLength,
    ThemeMode? themeMode,
    double? fontSize,
    bool? showSystemMessages,
    bool? hapticFeedbackEnabled,
    bool? sendOnEnter,
    String? defaultServerId,
    bool? showDataIndicator,
    bool? autoGenerateTitle,
    bool? streamingEnabled,
    String? defaultPersonaId,
    bool? hasCompletedOnboarding,
    bool? mcpEnabled,
  }) {
    return AppSettings(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      contextLength: contextLength ?? this.contextLength,
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      showSystemMessages: showSystemMessages ?? this.showSystemMessages,
      hapticFeedbackEnabled:
          hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
      sendOnEnter: sendOnEnter ?? this.sendOnEnter,
      defaultServerId: defaultServerId ?? this.defaultServerId,
      showDataIndicator: showDataIndicator ?? this.showDataIndicator,
      autoGenerateTitle: autoGenerateTitle ?? this.autoGenerateTitle,
      streamingEnabled: streamingEnabled ?? this.streamingEnabled,
      defaultPersonaId: defaultPersonaId ?? this.defaultPersonaId,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
    );
  }
}
