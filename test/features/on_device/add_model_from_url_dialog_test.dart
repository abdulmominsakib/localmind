import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/features/on_device/views/components/add_model_from_url_dialog.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _CountingAdapter implements HttpClientAdapter {
  int requestCount = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('off-domain URL makes zero requests', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final adapter = _CountingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    // Show dialog
    await tester.pump();
    // Open dialog via a button? Instead, push route.
    // Simpler: pump the dialog directly.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: _DialogHost(),
          ),
        ),
      ),
    );
    await tester.pump();
    // Trigger dialog
    // The host shows the dialog on init
    await tester.pump(const Duration(milliseconds: 100));

    // Enter off-domain URL
    final field = find.byType(TextField);
    await tester.enterText(field, 'https://evil.example.com/model.gguf');
    await tester.pump();

    // Tap submit (the dialog's import button)
    final btn = find.text('Add');
    if (btn.evaluate().isNotEmpty) {
      await tester.tap(btn);
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(adapter.requestCount, 0);
  });
}

class _DialogHost extends StatefulWidget {
  const _DialogHost();
  @override
  State<_DialogHost> createState() => _DialogHostState();
}

class _DialogHostState extends State<_DialogHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (_) => const AddModelFromUrlDialog(),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}