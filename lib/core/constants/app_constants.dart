class AppConstants {
  static const String appName = 'LocalMind';
  static const String appTagline = 'Your AI. Your Device. Your Rules.';
  static const String version = '1.0.0';

  static const double defaultTemperature = 0.7;
  static const double defaultTopP = 0.9;
  static const int defaultMaxTokens = 2048;
  static const int defaultContextLength = 4096;

  static const int connectionTimeoutMs = 5000;
  static const int receiveTimeoutMs = 60000;

  static const String serversBox = 'servers';
  static const String messagesBox = 'messages';
  static const String conversationsBox = 'conversations';
  static const String personasBox = 'personas';
  static const String settingsBox = 'settings';

  static const int lmStudioDefaultPort = 1234;
  static const int openAICompatibleDefaultPort = 8080;
  static const int ollamaDefaultPort = 11434;

  static const String openRouterBaseUrl = 'https://openrouter.ai/api/v1';
}
