import 'package:flutter_test/flutter_test.dart';
import 'package:apple_mlx/apple_mlx.dart';

void main() {
  group('AppleMlxSpeechManager', () {
    test('initializes with default configuration', () {
      final manager = AppleMlxSpeechManager();
      expect(manager.isInitialized, isFalse);
      expect(manager.config.defaultVoice, equals('alba'));
      expect(
        manager.config.sttModelId,
        equals(AppleMlxModelIds.parakeetTdt06b),
      );
      expect(manager.config.ttsModelId, equals(AppleMlxModelIds.pocketTts));
    });

    test('supports custom model configuration', () {
      final config = AppleMlxConfig(
        sttModelId: AppleMlxModelIds.whisperSmall,
        ttsModelId: AppleMlxModelIds.pocketTts,
        defaultVoice: 'marius',
      );
      final manager = AppleMlxSpeechManager(config: config);
      expect(manager.config.defaultVoice, equals('marius'));
      expect(manager.config.sttModelId, equals(AppleMlxModelIds.whisperSmall));
    });
  });

  group('AppleMlxLlmManager', () {
    test('instantiates with uninitialized state', () {
      final llm = AppleMlxLlmManager();
      expect(llm.isModelLoaded, isFalse);
      expect(llm.isServerRunning, isFalse);
      expect(llm.serverInfo, isNull);
      expect(llm.modelHandle, isNull);
    });

    test('exposes popular MLX model identifiers', () {
      expect(AppleMlxModelIds.gemma22b, isNotEmpty);
      expect(AppleMlxModelIds.llama321b, isNotEmpty);
      expect(AppleMlxModelIds.qwen2505b, isNotEmpty);
    });
  });
}
