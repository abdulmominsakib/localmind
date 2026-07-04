import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../../../core/models/enums.dart';
import '../../../../features/chat/utils/image_upload_utils.dart';
import '../../../../features/tts/data/kitten_tts_model.dart';

enum SyntaxThemeName { light, dark }

class AppSettings {
  static const Object _unset = Object();

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
  final bool hasAskedForNotifications;
  final bool mcpEnabled;
  final bool newChatMcpEnabled;
  final SyntaxThemeName codeThemeDark;
  final SyntaxThemeName codeThemeLight;
  final PreferredBackend preferredBackend;
  final EngineId ttsEngine;
  final String? ttsVoiceId;
  final double ttsSpeed;
  final KittenTtsModelVariant kittenTtsModelVariant;
  final bool autoSpeakEnabled;
  final bool ttsProcessMarkdown;
  final int ttsSkipSeconds;
  final bool smartReplyEnabled;
  final bool aiUserResponseEnabled;
  final String? localeCode;
  final String? huggingFaceToken;
  final bool unloadModelsBeforeLoad;
  final bool tempChatKeyboardIncognito;
  final bool resumeLastChat;
  final bool imageCompressionEnabled;
  final ImageCompressionLevel imageCompressionLevel;
  final bool smartRepliesUsePersona;
  final bool keepPersonaOnNewChat;
  final bool roleSwapButtonEnabled;
  final bool showSystemMessagesInChat;

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
    this.hasAskedForNotifications = false,
    this.mcpEnabled = true,
    this.newChatMcpEnabled = true,
    this.codeThemeDark = SyntaxThemeName.dark,
    this.codeThemeLight = SyntaxThemeName.light,
    this.preferredBackend = PreferredBackend.cpu,
    this.ttsEngine = EngineId.system,
    this.ttsVoiceId,
    this.ttsSpeed = 1.0,
    this.kittenTtsModelVariant = KittenTtsModelVariant.nanoInt8,
    this.autoSpeakEnabled = false,
    this.ttsProcessMarkdown = true,
    this.ttsSkipSeconds = 10,
    this.smartReplyEnabled = true,
    this.aiUserResponseEnabled = false,
    this.localeCode,
    this.huggingFaceToken,
    this.unloadModelsBeforeLoad = false,
    this.tempChatKeyboardIncognito = true,
    this.resumeLastChat = true,
    this.imageCompressionEnabled = false,
    this.imageCompressionLevel = ImageCompressionLevel.medium,
    this.smartRepliesUsePersona = false,
    this.keepPersonaOnNewChat = false,
    this.roleSwapButtonEnabled = false,
    this.showSystemMessagesInChat = true,
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
    bool? hasAskedForNotifications,
    bool? mcpEnabled,
    bool? newChatMcpEnabled,
    SyntaxThemeName? codeThemeDark,
    SyntaxThemeName? codeThemeLight,
    PreferredBackend? preferredBackend,
    EngineId? ttsEngine,
    Object? ttsVoiceId = _unset,
    double? ttsSpeed,
    KittenTtsModelVariant? kittenTtsModelVariant,
    bool? autoSpeakEnabled,
    bool? ttsProcessMarkdown,
    int? ttsSkipSeconds,
    bool? smartReplyEnabled,
    bool? aiUserResponseEnabled,
    Object? localeCode = _unset,
    Object? huggingFaceToken = _unset,
    bool? unloadModelsBeforeLoad,
    bool? tempChatKeyboardIncognito,
    bool? resumeLastChat,
    bool? imageCompressionEnabled,
    ImageCompressionLevel? imageCompressionLevel,
    bool? smartRepliesUsePersona,
    bool? keepPersonaOnNewChat,
    bool? roleSwapButtonEnabled,
    bool? showSystemMessagesInChat,
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
      hasAskedForNotifications:
          hasAskedForNotifications ?? this.hasAskedForNotifications,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
      newChatMcpEnabled: newChatMcpEnabled ?? this.newChatMcpEnabled,
      codeThemeDark: codeThemeDark ?? this.codeThemeDark,
      codeThemeLight: codeThemeLight ?? this.codeThemeLight,
      preferredBackend: preferredBackend ?? this.preferredBackend,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      ttsVoiceId: identical(ttsVoiceId, _unset)
          ? this.ttsVoiceId
          : ttsVoiceId as String?,
      ttsSpeed: ttsSpeed ?? this.ttsSpeed,
      kittenTtsModelVariant:
          kittenTtsModelVariant ?? this.kittenTtsModelVariant,
      autoSpeakEnabled: autoSpeakEnabled ?? this.autoSpeakEnabled,
      ttsProcessMarkdown: ttsProcessMarkdown ?? this.ttsProcessMarkdown,
      ttsSkipSeconds: ttsSkipSeconds ?? this.ttsSkipSeconds,
      smartReplyEnabled: smartReplyEnabled ?? this.smartReplyEnabled,
      aiUserResponseEnabled:
          aiUserResponseEnabled ?? this.aiUserResponseEnabled,
      localeCode: identical(localeCode, _unset)
          ? this.localeCode
          : localeCode as String?,
      huggingFaceToken: identical(huggingFaceToken, _unset)
          ? this.huggingFaceToken
          : huggingFaceToken as String?,
      unloadModelsBeforeLoad:
          unloadModelsBeforeLoad ?? this.unloadModelsBeforeLoad,
      tempChatKeyboardIncognito:
          tempChatKeyboardIncognito ?? this.tempChatKeyboardIncognito,
      resumeLastChat: resumeLastChat ?? this.resumeLastChat,
      imageCompressionEnabled:
          imageCompressionEnabled ?? this.imageCompressionEnabled,
      imageCompressionLevel:
          imageCompressionLevel ?? this.imageCompressionLevel,
      smartRepliesUsePersona:
          smartRepliesUsePersona ?? this.smartRepliesUsePersona,
      keepPersonaOnNewChat: keepPersonaOnNewChat ?? this.keepPersonaOnNewChat,
      roleSwapButtonEnabled:
          roleSwapButtonEnabled ?? this.roleSwapButtonEnabled,
      showSystemMessagesInChat:
          showSystemMessagesInChat ?? this.showSystemMessagesInChat,
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
      'hasAskedForNotifications': hasAskedForNotifications,
      'mcpEnabled': mcpEnabled,
      'newChatMcpEnabled': newChatMcpEnabled,
      'codeThemeDark': codeThemeDark.index,
      'codeThemeLight': codeThemeLight.index,
      'preferredBackend': preferredBackend.index,
      'ttsEngine': ttsEngine.name,
      'ttsVoiceId': ttsVoiceId,
      'ttsSpeed': ttsSpeed,
      'kittenTtsModelVariant': kittenTtsModelVariant.name,
      'autoSpeakEnabled': autoSpeakEnabled,
      'ttsProcessMarkdown': ttsProcessMarkdown,
      'ttsSkipSeconds': ttsSkipSeconds,
      'smartReplyEnabled': smartReplyEnabled,
      'aiUserResponseEnabled': aiUserResponseEnabled,
      'localeCode': localeCode,
      'huggingFaceToken': huggingFaceToken,
      'unloadModelsBeforeLoad': unloadModelsBeforeLoad,
      'tempChatKeyboardIncognito': tempChatKeyboardIncognito,
      'resumeLastChat': resumeLastChat,
      'imageCompressionEnabled': imageCompressionEnabled,
      'imageCompressionLevel': imageCompressionLevel.name,
      'smartRepliesUsePersona': smartRepliesUsePersona,
      'keepPersonaOnNewChat': keepPersonaOnNewChat,
      'roleSwapButtonEnabled': roleSwapButtonEnabled,
      'showSystemMessagesInChat': showSystemMessagesInChat,
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
      hasAskedForNotifications: map['hasAskedForNotifications'] ?? false,
      mcpEnabled: map['mcpEnabled'] ?? true,
      newChatMcpEnabled: map['newChatMcpEnabled'] ?? true,
      codeThemeDark: SyntaxThemeName.values[map['codeThemeDark'] ?? 0],
      codeThemeLight: SyntaxThemeName.values[map['codeThemeLight'] ?? 1],
      preferredBackend: _parsePreferredBackend(map['preferredBackend']),
      ttsEngine: _parseEngine(map['ttsEngine']),
      ttsVoiceId: map['ttsVoiceId'],
      ttsSpeed: map['ttsSpeed']?.toDouble() ?? 1.0,
      kittenTtsModelVariant: _parseKittenVariant(map['kittenTtsModelVariant']),
      autoSpeakEnabled: map['autoSpeakEnabled'] ?? false,
      ttsProcessMarkdown: map['ttsProcessMarkdown'] ?? true,
      ttsSkipSeconds: _parseTtsSkipSeconds(map['ttsSkipSeconds']),
      smartReplyEnabled: map['smartReplyEnabled'] ?? true,
      aiUserResponseEnabled: map['aiUserResponseEnabled'] ?? false,
      localeCode: map['localeCode'] as String?,
      huggingFaceToken: map['huggingFaceToken'] as String?,
      unloadModelsBeforeLoad: map['unloadModelsBeforeLoad'] ?? false,
      tempChatKeyboardIncognito: map['tempChatKeyboardIncognito'] ?? true,
      resumeLastChat: map['resumeLastChat'] ?? true,
      imageCompressionEnabled: map['imageCompressionEnabled'] ?? false,
      imageCompressionLevel:
          _parseImageCompressionLevel(map['imageCompressionLevel']),
      smartRepliesUsePersona: map['smartRepliesUsePersona'] ?? false,
      keepPersonaOnNewChat: map['keepPersonaOnNewChat'] ?? false,
      roleSwapButtonEnabled: map['roleSwapButtonEnabled'] ?? false,
      showSystemMessagesInChat: map['showSystemMessagesInChat'] ?? true,
    );
  }

  static ImageCompressionLevel _parseImageCompressionLevel(dynamic value) {
    if (value is String) {
      try {
        return ImageCompressionLevel.values.byName(value);
      } catch (_) {}
    }
    return ImageCompressionLevel.medium;
  }

  static PreferredBackend _parsePreferredBackend(dynamic value) {
    if (value is int && value < PreferredBackend.values.length) {
      return PreferredBackend.values[value];
    }
    // Handle migration from old LiteLmBackendType (had cpu=0, gpu=1, npu=2)
    // Map npu (2) to gpu since flutter_gemma only has cpu/gpu
    if (value is int && value == 2) return PreferredBackend.gpu;
    return PreferredBackend.cpu;
  }

  static EngineId _parseEngine(dynamic value) {
    if (value is String) {
      return engineIdFromString(value);
    }
    if (value is int) {
      return EngineId.values[value];
    }
    return EngineId.system;
  }

  static KittenTtsModelVariant _parseKittenVariant(dynamic value) {
    if (value is String) {
      try {
        return KittenTtsModelVariant.values.byName(value);
      } catch (_) {}
    }
    return KittenTtsModelVariant.nanoInt8;
  }

  static int _parseTtsSkipSeconds(dynamic value) {
    const allowed = {5, 10, 15, 30};
    if (value is int && allowed.contains(value)) return value;
    return 10;
  }

  String toJson() => json.encode(toMap());

  factory AppSettings.fromJson(String source) =>
      AppSettings.fromMap(json.decode(source));
}
