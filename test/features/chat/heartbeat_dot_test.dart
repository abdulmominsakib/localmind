import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/chat/views/components/heartbeat_dot.dart';

void main() {
  group('HeartbeatDot', () {
    testWidgets('renders with default size and primary color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: HeartbeatDot())),
        ),
      );

      expect(find.byType(HeartbeatDot), findsOneWidget);
      // Ensure initial frame renders
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with custom size and custom color', (tester) async {
      const customColor = Colors.teal;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: HeartbeatDot(size: 10, color: customColor)),
          ),
        ),
      );

      expect(find.byType(HeartbeatDot), findsOneWidget);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('animates heartbeat cycle smoothly over time', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: HeartbeatDot(size: 7))),
        ),
      );

      // Advance through heartbeat phases (first beat, recoil, second beat, rest)
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
    });
  });
}
