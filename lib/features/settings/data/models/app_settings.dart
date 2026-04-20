import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';

enum SyntaxThemeName {
  light,
  dark,
}

class AppSettings {
  final double temperature;
  final double topP;
  final int maxTokens;
  final int contextLength;
  final ThemeMode themeMode;
  final double fontSize;
  final bool showSystemMessages;
  final bool hapticFeedbackEnabled;
  final bool sendOnEnter;
  final String? defaultServerId;
  final bool showDataIndicator;
  final bool autoGenerateTitle;
  final bool streamingEnabled;
  final String? defaultPersonaId;
  final bool hasCompletedOnboarding;
  final bool mcpEnabled;
  final SyntaxThemeName codeThemeDark;
  final SyntaxThemeName codeThemeLight;
  final LiteLmBackendType preferredBackend;

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
    this.codeThemeDark = SyntaxThemeName.dark,
    this.codeThemeLight = SyntaxThemeName.light,
    this.preferredBackend = LiteLmBackendType.cpu,
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
    SyntaxThemeName? codeThemeDark,
    SyntaxThemeName? codeThemeLight,
    LiteLmBackendType? preferredBackend,
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
      codeThemeDark: codeThemeDark ?? this.codeThemeDark,
      codeThemeLight: codeThemeLight ?? this.codeThemeLight,
      preferredBackend: preferredBackend ?? this.preferredBackend,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'topP': topP,
      'maxTokens': maxTokens,
      'contextLength': contextLength,
      'themeMode': themeMode.index,
      'fontSize': fontSize,
      'showSystemMessages': showSystemMessages,
      'hapticFeedbackEnabled': hapticFeedbackEnabled,
      'sendOnEnter': sendOnEnter,
      'defaultServerId': defaultServerId,
      'showDataIndicator': showDataIndicator,
      'autoGenerateTitle': autoGenerateTitle,
      'streamingEnabled': streamingEnabled,
      'defaultPersonaId': defaultPersonaId,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'mcpEnabled': mcpEnabled,
      'codeThemeDark': codeThemeDark.index,
      'codeThemeLight': codeThemeLight.index,
      'preferredBackend': preferredBackend.index,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      temperature: map['temperature']?.toDouble() ?? 0.7,
      topP: map['topP']?.toDouble() ?? 0.9,
      maxTokens: map['maxTokens']?.toInt() ?? 2048,
      contextLength: map['contextLength']?.toInt() ?? 4096,
      themeMode: ThemeMode.values[map['themeMode'] ?? 2],
      fontSize: map['fontSize']?.toDouble() ?? 16.0,
      showSystemMessages: map['showSystemMessages'] ?? false,
      hapticFeedbackEnabled: map['hapticFeedbackEnabled'] ?? true,
      sendOnEnter: map['sendOnEnter'] ?? false,
      defaultServerId: map['defaultServerId'],
      showDataIndicator: map['showDataIndicator'] ?? true,
      autoGenerateTitle: map['autoGenerateTitle'] ?? true,
      streamingEnabled: map['streamingEnabled'] ?? true,
      defaultPersonaId: map['defaultPersonaId'],
      hasCompletedOnboarding: map['hasCompletedOnboarding'] ?? false,
      mcpEnabled: map['mcpEnabled'] ?? true,
      codeThemeDark: SyntaxThemeName.values[map['codeThemeDark'] ?? 0],
      codeThemeLight: SyntaxThemeName.values[map['codeThemeLight'] ?? 1],
      preferredBackend: LiteLmBackendType.values[map['preferredBackend'] ?? 0],
    );
  }

  String toJson() => json.encode(toMap());

  factory AppSettings.fromJson(String source) =>
      AppSettings.fromMap(json.decode(source));
}
