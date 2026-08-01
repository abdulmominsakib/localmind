import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/features/tts/providers/tts_providers.dart';
import 'package:localmind/features/voice_mode/providers/voice_mode_provider.dart';
import 'package:localmind/features/voice_mode/views/components/voice_transcript.dart';

void main() {
  testWidgets('highlights the word reported by native TTS progress', (
    tester,
  ) async {
    const response = 'Hello world from LocalMind';
    const ttsState = TtsState(
      isSpeaking: true,
      activeEngine: EngineId.system,
      playingContent: response,
      chunks: [response],
      currentChunkIndex: 0,
      spokenCharOffset: 6,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [ttsProvider.overrideWith(() => _StubTtsNotifier(ttsState))],
        child: const MaterialApp(
          home: Scaffold(
            body: VoiceTranscript(
              phase: VoiceModePhase.speaking,
              transcript: '',
              response: response,
            ),
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(find.byType(RichText).last);
    final root = richText.text as TextSpan;
    final wordSpan = root.children!.whereType<TextSpan>().singleWhere(
      (span) => span.text == 'world',
    );

    expect(wordSpan.style?.fontWeight, FontWeight.w700);
    expect(wordSpan.style?.color, isNot(root.style?.color));
  });

  test('resetProgress clears a native spoken character offset', () {
    const state = TtsState(spokenCharOffset: 12);

    expect(state.copyWith(resetProgress: true).spokenCharOffset, -1);
  });

  testWidgets('auto-scrolls to keep a later spoken word visible', (
    tester,
  ) async {
    final response = List.generate(80, (index) => 'word$index').join(' ');
    final activeOffset = response.indexOf('word70');
    final ttsState = TtsState(
      isSpeaking: true,
      activeEngine: EngineId.system,
      playingContent: response,
      chunks: [response],
      currentChunkIndex: 0,
      spokenCharOffset: 0,
    );
    final notifier = _StubTtsNotifier(ttsState);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [ttsProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: VoiceTranscript(
                phase: VoiceModePhase.speaking,
                transcript: '',
                response: response,
              ),
            ),
          ),
        ),
      ),
    );

    notifier.setSpokenCharOffset(activeOffset);
    await tester.pump();

    final updatedText = tester.widget<RichText>(find.byType(RichText).last);
    final updatedRoot = updatedText.text as TextSpan;
    final activeWord = updatedRoot.children!.whereType<TextSpan>().singleWhere(
      (span) => span.text == 'word70',
    );
    expect(activeWord.style?.fontWeight, FontWeight.w700);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byKey(const ValueKey('speaking-scroll')),
    );
    expect(scrollView.controller!.offset, greaterThan(0));
  });
}

class _StubTtsNotifier extends TtsNotifier {
  _StubTtsNotifier(this.initialState);

  final TtsState initialState;

  @override
  TtsState build() => initialState;

  void setSpokenCharOffset(int offset) {
    state = state.copyWith(
      spokenCharOffset: offset,
      playingContent: state.playingContent,
    );
  }
}
