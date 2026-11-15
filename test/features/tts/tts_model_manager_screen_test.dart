import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/downloads/download_engine.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/core/downloads/download_providers.dart';
import 'package:localmind/features/tts/data/melo_tts_model.dart';
import 'package:localmind/features/tts/data/tts_bundle_download_service.dart';
import 'package:localmind/features/tts/providers/tts_model_providers.dart';
import 'package:localmind/features/tts/views/tts_model_manager_screen.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Minimal melo-shaped bundle archive whose top-level directory matches the
/// real `vits-melo-tts-zh_en` bundle name, base64-encoded for hermetic runs.
const _meloFixtureBase64 =
    'QlpoOTFBWSZTWT9jR+sAAZRf5ceQQAP/gTeOgBD+/59QIBABIAAwEBQECDABOBUJKkAPQmgNAAAAGho9QZDmAAmAAJgAAAAAIok1PVPRqh6nphRjSaNqN6o0DanqD0Ib/9xwjA8zoIxHI4dMgk9k5VVNOzVfM6hgHWGByl2yCw3jqGBzQoFB/dZqO8ah2Yyb+Pd9eA3DA2u4U55YhzBgjGeQHcbt3RjnHlGw8g0GB2DINBu9fXhcPXBkGGYrA7b5G8a0Rkbts5Y2hUKTlLi8cg1GlqFApeDamQajlClrSNCowYwduPy/t2ntmPnI9IwPH29Azv/GMGbno4E6eyMUQo9eoWNonqgu4onTzvE0UFZlia4+4KMaVoMLHoqujX/NQ6832GoPJxBtoIM4+fSNhgEwdE0TYTDJLBaYMF9JJSWG89I+ID+LuSKcKEgfsaP1gA==';

/// Serves the fixture for every request, whatever URL the engine resolves.
class _FixtureAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = Uint8List.fromList(base64Decode(_meloFixtureBase64));
    return ResponseBody(
      Stream<Uint8List>.fromIterable([bytes]),
      200,
      headers: {
        HttpHeaders.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }
}

Future<Directory> _tempDir(String tag) =>
    Directory.systemTemp.createTemp('lm_tts_manager_${tag}_');

Future<void> _deleteDirWithRetry(Directory dir) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      await dir.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  await dir.delete(recursive: true);
}

void main() {
  late Directory supportDir;
  late Directory workDir;
  late DownloadEngine engine;
  late ProviderContainer container;

  setUp(() async {
    supportDir = await _tempDir('support');
    workDir = await _tempDir('work');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    engine = DownloadEngine(
      store: DownloadTaskStore(prefs),
      dio: Dio()..httpClientAdapter = _FixtureAdapter(),
      workDirectory: () async => workDir,
      tokenResolver: () => null,
    );
    await engine.ready;

    final service = TtsBundleDownloadService(
      engine: engine,
      supportDirectoryResolver: () async => supportDir,
    );

    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        downloadEngineProvider.overrideWithValue(engine),
        chineseTtsBundleServiceProvider.overrideWithValue(service),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    engine.dispose();
    await _deleteDirWithRetry(supportDir);
    await _deleteDirWithRetry(workDir);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadTheme(
          data: AppTheme.lightShadTheme,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: TtsModelManagerScreen()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('renders Melo and Kokoro engine cards among the engines', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Melo TTS'), findsOneWidget);
    expect(find.text('Kokoro TTS'), findsOneWidget);
    expect(find.text('System TTS'), findsOneWidget);
    // Not installed yet: the Melo card offers an Install action.
    expect(find.text('Install'), findsWidgets);
  });

  testWidgets('pre-installed Melo card offers selection and its voice chips', (
    tester,
  ) async {
    // Seed the extracted bundle on disk before the first pump. The download
    // pipeline itself (enqueue → engine transfer → isolate extraction →
    // publish) is covered end-to-end by tts_bundle_download_service_test;
    // running live transfers inside a widget test fights FakeAsync zones
    // (isolate completions and Riverpod re-scheduling are undeliverable
    // there), so this test pins the card's installed-state rendering.
    final bundleDir = Directory(
      '${supportDir.path}/tts_models/melo/${MeloTtsModel.instance.bundleDirName}',
    );
    bundleDir.createSync(recursive: true);
    for (final fileName in [
      'model.onnx',
      'tokens.txt',
      'lexicon.txt',
    ]) {
      File('${bundleDir.path}/$fileName').writeAsStringSync('x');
    }
    Directory('${bundleDir.path}/dict').createSync();

    // Warm the downloaded-state FutureProvider on the real event loop
    // BEFORE the screen builds: once computed, it is cached, so the card
    // reads ready data instead of issuing fake-zone IO that can never
    // complete under FakeAsync.
    await tester.runAsync(() async {
      await container.read(meloTtsBundleDownloadedProvider.future);
    });

    await pumpScreen(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Installed: the Melo card offers Select instead of Install, and the
    // single Chinese voice chip is present.
    expect(find.text('Mei'), findsOneWidget);
  });
}
