import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/utils/ascii_logo.dart';
import 'package:localmind/features/chat/views/components/message_list/ascii_logo_view.dart';

Future<void> _pump(WidgetTester tester, {bool paused = false}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: AsciiLogoView(
          logo: AsciiLogo.openRouter,
          semanticLabel: 'OpenRouter',
          paused: paused,
        ),
      ),
    ),
  );
}

/// The base layer as drawn right now.
String _base(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).first.data!;

final _still = asciiLogoMask(AsciiLogo.openRouter).join('\n');

void main() {
  testWidgets('plays, then settles on the still logo', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_base(tester), isNot(_still));

    await tester.pump(AsciiLogoView.playDuration);
    expect(_base(tester), _still);
    // Settled means no ticker left scheduling frames.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('holds still while paused', (tester) async {
    await _pump(tester, paused: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_base(tester), _still);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('tapping a settled logo plays it again', (tester) async {
    await _pump(tester);
    await tester.pump(AsciiLogoView.playDuration);
    expect(_base(tester), _still);

    await tester.tap(find.byType(AsciiLogoView));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_base(tester), isNot(_still));
  });

  testWidgets('pausing mid-play settles it', (tester) async {
    await _pump(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _pump(tester, paused: true);
    expect(_base(tester), _still);
  });
}
