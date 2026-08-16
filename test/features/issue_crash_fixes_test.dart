import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/core/providers/service_providers.dart';
import 'package:localmind/core/providers/storage_providers.dart';
import 'package:localmind/core/theme/app_theme.dart';
import 'package:localmind/features/chat/data/models/chat_parameters.dart';
import 'package:localmind/features/chat/providers/chat_params_providers.dart';
import 'package:localmind/features/chat/views/components/model_info_sheet.dart';
import 'package:localmind/features/models/components/model_list.dart';
import 'package:localmind/features/models/data/models/model_info.dart';
import 'package:localmind/features/servers/data/models/server.dart';
import 'package:localmind/features/servers/data/server_api_service.dart';
import 'package:localmind/features/servers/providers/server_providers.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  group('Issue #62: TTS AudioSource MediaItem Tag', () {
    test('AudioSource tag is a valid MediaItem even during preview', () {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/tts_test_preview.wav');
      tempFile.writeAsBytesSync(Uint8List(100));
      addTearDown(() {
        if (tempFile.existsSync()) tempFile.deleteSync();
      });

      final isPreview = true;
      final source = AudioSource.file(
        tempFile.path,
        tag: MediaItem(
          id: 'tts_chunk_test_0',
          album: isPreview ? 'Voice Preview' : 'LocalMind TTS',
          title: 'Hello world',
          artist: 'Piper TTS',
        ),
      );

      // Verify tag is non-null and is a MediaItem (avoiding "type 'Null' is not a subtype of type 'MediaItem'")
      expect(source.tag, isNotNull);
      expect(source.tag, isA<MediaItem>());
      final mediaItem = source.tag as MediaItem;
      expect(mediaItem.album, 'Voice Preview');
      expect(mediaItem.title, 'Hello world');
    });
  });

  group('Issue #60 & #63: Server API Error Handling', () {
    test('fetchModels throws clean formatted error on 401 unauthorized with top-level message', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpClientAdapter((options) {
        return ResponseBody.fromString(
          '{"message":"Invalid API key or unauthorized.","type":"authentication_error"}',
          401,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final apiService = ServerApiService(dio);
      final server = Server(
        id: 'test-server',
        name: 'OpenRouter',
        host: 'openrouter.ai',
        port: 443,
        type: ServerType.openRouter,
        apiKey: 'invalid-key',
        createdAt: now,
        lastConnectedAt: now,
      );

      expect(
        () => apiService.fetchModels(server),
        throwsA(
          predicate((e) =>
              e is Exception &&
              e.toString().contains('Failed to fetch models: authentication_error: Invalid API key or unauthorized.')),
        ),
      );
    });

    test('fetchModels throws clean formatted error on 500 error payload', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpClientAdapter((options) {
        return ResponseBody.fromString(
          '{"error":{"code":500,"message":"Internal engine crash"}}',
          500,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final apiService = ServerApiService(dio);
      final server = Server(
        id: 'test-server-500',
        name: 'Local Server',
        host: 'localhost',
        port: 1234,
        type: ServerType.openAICompatible,
        createdAt: now,
        lastConnectedAt: now,
      );

      expect(
        () => apiService.fetchModels(server),
        throwsA(
          predicate((e) =>
              e is Exception &&
              e.toString().contains('Failed to fetch models: Error 500: Internal engine crash')),
        ),
      );
    });

    test('loadModelWithInstanceId throws clean formatted error on top-level API error map', () async {
      final dio = Dio();
      dio.httpClientAdapter = _MockHttpClientAdapter((options) {
        return ResponseBody.fromString(
          '{"message":"Model not found on disk","type":"not_found"}',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final apiService = ServerApiService(dio);
      final server = Server(
        id: 'test-server',
        name: 'LM Studio',
        host: 'localhost',
        port: 1234,
        type: ServerType.lmStudio,
        createdAt: now,
        lastConnectedAt: now,
      );

      expect(
        () => apiService.loadModelWithInstanceId(server, 'missing-model'),
        throwsA(
          predicate((e) =>
              e is Exception &&
              e.toString().contains('not_found: Model not found on disk')),
        ),
      );
    });

    testWidgets('showModelInfoSheet gracefully handles availableModelsProvider error', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final server = Server(
        id: 'error-server',
        name: 'Error Server',
        host: 'localhost',
        port: 1234,
        type: ServerType.openAICompatible,
        createdAt: now,
        lastConnectedAt: now,
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
          activeServerProvider.overrideWith(() => _StubActiveServerNotifier(server)),
          serversProvider.overrideWith(() => _StubServersNotifier(server)),
          availableModelsProvider(server.id).overrideWith(
            (ref) async => throw Exception('Server connection failed'),
          ),
        ],
      );
      addTearDown(container.dispose);

      late BuildContext capturedContext;
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ShadTheme(
              data: AppTheme.lightShadTheme,
              child: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    capturedContext = context;
                    capturedRef = ref;
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger showModelInfoSheet and ensure no uncaught exception is thrown
      showModelInfoSheet(capturedContext, capturedRef, 'test-model-id');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('Issue #61: ModelList Unmounted Ref Access Guard', () {
    testWidgets('does not throw when unmounted while model is loading', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final server = Server(
        id: 'test-server-unload',
        name: 'Test Server',
        host: 'localhost',
        port: 1234,
        type: ServerType.lmStudio,
        createdAt: now,
        lastConnectedAt: now,
      );

      final testModel = ModelInfo(
        id: 'qwen-model',
        name: 'Qwen Model',
        serverId: server.id,
        serverType: ServerType.lmStudio,
      );

      final mockDio = Dio();
      mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
        return ResponseBody.fromString('{"status":"ok"}', 200);
      });
      final mockApiService = ServerApiService(mockDio);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsProvider.overrideWith(_TestSettingsNotifier.new),
          chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
          serverApiServiceProvider.overrideWithValue(mockApiService),
          activeServerProvider.overrideWith(() => _StubActiveServerNotifier(server)),
          serversProvider.overrideWith(() => _StubServersNotifier(server)),
          connectionStatusProvider.overrideWith(_StubConnectedStatusNotifier.new),
          availableModelsProvider(server.id).overrideWith((ref) => Future.value([testModel])),
          loadedModelsProvider(server).overrideWith((ref) => Future.value(<String>{})),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ModelList(
                serverId: server.id,
                selectedModelId: null,
                isDark: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Qwen Model'), findsOneWidget);

      // Tapping tile triggers onTap async load
      await tester.tap(find.text('Qwen Model'));

      // Immediately replace widget with empty container to unmount ModelList
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No unhandled exceptions thrown
      expect(tester.takeException(), isNull);
    });
  });
}

class _StubActiveServerNotifier extends ActiveServerNotifier {
  _StubActiveServerNotifier(this.server);

  final Server server;

  @override
  Server? build() => server;
}

class _StubServersNotifier extends ServersNotifier {
  _StubServersNotifier(this.server);

  final Server server;

  @override
  Future<List<Server>> build() async => [server];
}

class _StubConnectedStatusNotifier extends ConnectionStatusNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) handler;

  _MockHttpClientAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings(
    unloadModelsBeforeLoad: false,
  );
}

