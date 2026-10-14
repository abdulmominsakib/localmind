import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/device/device_memory_service.dart';
import 'package:localmind/core/providers/device_info_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/on_device/data/models/download_progress_info.dart';
import 'package:localmind/features/on_device/data/models/download_status.dart';
import 'package:localmind/features/on_device/data/models/on_device_model.dart';
import 'package:localmind/features/on_device/providers/foreground_download_providers.dart';
import 'package:localmind/features/on_device/providers/on_device_providers.dart';
import 'package:localmind/features/onboarding/components/onboarding_model_warning_dialog.dart';
import 'package:localmind/features/onboarding/screens/onboarding_model_download_screen.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Widget _createTestWidget({
  Set<String> downloadedModels = const {},
  Map<String, DownloadProgressInfo> downloadStates = const {},
}) {
  return ProviderScope(
    overrides: [
      onDeviceModelsProvider.overrideWith((ref) => OnDeviceModel.curatedModels),
      downloadedModelsProvider.overrideWith((ref) async => downloadedModels),
      foregroundDownloadNotifierProvider.overrideWith(
        () => _FakeForegroundDownloadNotifier(downloadStates),
      ),
      deviceMemoryProvider.overrideWith(
        (ref) async => const DeviceMemoryInfo(
          totalMemoryMb: 4096,
          availableMemoryMb: 2048,
        ),
      ),
    ],
    child: ShadTheme(
      data: AppTheme.lightShadTheme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OnboardingModelDownloadScreen(),
      ),
    ),
  );
}

class _FakeForegroundDownloadNotifier extends ForegroundDownloadNotifier {
  final Map<String, DownloadProgressInfo> initialStates;

  _FakeForegroundDownloadNotifier(this.initialStates);

  @override
  Map<String, DownloadProgressInfo> build() {
    return initialStates;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shows warning dialog when user presses Continue without downloaded model',
    (tester) async {
      await tester.pumpWidget(_createTestWidget());
      await tester.pumpAndSettle();

      // Verify Skip button in AppBar
      expect(find.text('Skip'), findsOneWidget);

      // Verify hint above continue button
      expect(
        find.text(
          'At least one downloaded model is required for on-device chat.',
        ),
        findsOneWidget,
      );

      // Tap Continue
      final continueButton = find.widgetWithText(ShadButton, 'Continue');
      expect(continueButton, findsOneWidget);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Verify warning dialog is shown
      expect(find.byType(OnboardingModelWarningDialog), findsOneWidget);
      expect(find.text('No Model Downloaded'), findsOneWidget);
      expect(
        find.text(
          'To use on-device AI, you need to download or select at least one model. You can choose a model now, or skip and download one later in settings.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Skip'), findsOneWidget);
      expect(
        find.widgetWithText(ElevatedButton, 'Choose Model'),
        findsOneWidget,
      );

      // Tap "Choose Model" dismisses the dialog
      await tester.tap(find.widgetWithText(ElevatedButton, 'Choose Model'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingModelWarningDialog), findsNothing);
    },
  );

  testWidgets(
    'shows in-progress dialog when user presses Continue during active download',
    (tester) async {
      final downloadStates = <String, DownloadProgressInfo>{
        'qwen-3-0.6b': const DownloadProgressInfo(
          modelId: 'qwen-3-0.6b',
          status: DownloadStatus.running,
          progress: 0.45,
          bytesPerSecond: 2500000,
        ),
      };

      await tester.pumpWidget(
        _createTestWidget(downloadStates: downloadStates),
      );
      await tester.pumpAndSettle();

      // Hint should NOT be shown when download is active
      expect(
        find.text(
          'At least one downloaded model is required for on-device chat.',
        ),
        findsNothing,
      );

      // Tap Continue
      final continueButton = find.widgetWithText(ShadButton, 'Continue');
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      // Verify download in-progress dialog is shown
      expect(find.byType(OnboardingModelWarningDialog), findsOneWidget);
      expect(find.text('Download in Progress'), findsOneWidget);
      expect(
        find.text(
          'A model is currently downloading. You can wait for it to complete or continue in the background.',
        ),
        findsOneWidget,
      );
      expect(find.text('Wait'), findsOneWidget);
      expect(find.text('Continue Anyway'), findsOneWidget);

      // Tap "Wait" dismisses dialog
      await tester.tap(find.text('Wait'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingModelWarningDialog), findsNothing);
    },
  );
}
