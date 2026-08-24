import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/os_widget/views/components/model_loading_overlay.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  Widget createWidget({
    required String modelName,
    String? serverName,
    String statusMessage = 'Loading model into memory...',
    VoidCallback? onCancel,
  }) {
    return ShadApp(
      home: Scaffold(
        body: ModelLoadingOverlay(
          modelName: modelName,
          serverName: serverName,
          statusMessage: statusMessage,
          onCancel: onCancel,
        ),
      ),
    );
  }

  testWidgets('ModelLoadingOverlay renders model info and status correctly', (
    tester,
  ) async {
    await tester.pumpWidget(
      createWidget(
        modelName: 'Llama-3-8B-Instruct',
        serverName: 'Local On-Device Engine',
        statusMessage: 'Allocating context memory...',
      ),
    );
    await tester.pump();

    expect(find.text('Preparing Model'), findsOneWidget);
    expect(find.text('Llama-3-8B-Instruct'), findsOneWidget);
    expect(find.text('Local On-Device Engine'), findsOneWidget);
    expect(find.text('Allocating context memory...'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('ModelLoadingOverlay triggers onCancel when cancel is pressed', (
    tester,
  ) async {
    var canceled = false;
    await tester.pumpWidget(
      createWidget(
        modelName: 'Gemma-2-2B',
        onCancel: () {
          canceled = true;
        },
      ),
    );
    await tester.pump();

    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(canceled, isTrue);
  });
}
