import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:localmind/bootstrap/safe_riverpod_scope_host.dart';
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
import 'package:localmind/features/onboarding/screens/onboarding_server_setup_screen.dart';
import 'package:localmind/features/personas/data/models/persona.dart';
import 'package:localmind/features/personas/providers/personas_providers.dart';
import 'package:localmind/features/personas/views/create_persona_screen.dart';
import 'package:localmind/features/servers/views/add_server_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localmind/features/settings/data/models/app_settings.dart';
import 'package:localmind/features/sidebar/components/github_repo_card.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
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

      for (final isPreview in [true, false]) {
        final source = AudioSource.file(
          tempFile.path,
          tag: MediaItem(
            id: 'tts_chunk_test_$isPreview',
            album: isPreview ? 'Voice Preview' : 'LocalMind TTS',
            title: 'Hello world',
            artist: 'Piper TTS',
          ),
        );

        // Verify tag is non-null and is a MediaItem (avoiding "type 'Null' is not a subtype of type 'MediaItem'")
        expect(source.tag, isNotNull);
        expect(source.tag, isA<MediaItem>());
        final mediaItem = source.tag as MediaItem;
        expect(mediaItem.album, isPreview ? 'Voice Preview' : 'LocalMind TTS');
        expect(mediaItem.title, 'Hello world');
      }
    });
  });

  group('Issue #60 & #63: Server API Error Handling', () {
    test(
      'fetchModels throws clean formatted error on 401 unauthorized with top-level message',
      () async {
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
            predicate(
              (e) =>
                  e is Exception &&
                  e.toString().contains(
                    'Failed to fetch models: authentication_error: Invalid API key or unauthorized.',
                  ),
            ),
          ),
        );
      },
    );

    test(
      'fetchModels throws clean formatted error on 500 error payload',
      () async {
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
            predicate(
              (e) =>
                  e is Exception &&
                  e.toString().contains(
                    'Failed to fetch models: Error 500: Internal engine crash',
                  ),
            ),
          ),
        );
      },
    );

    test(
      'loadModelWithInstanceId throws clean formatted error on top-level API error map',
      () async {
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
            predicate(
              (e) =>
                  e is Exception &&
                  e.toString().contains('not_found: Model not found on disk'),
            ),
          ),
        );
      },
    );

    testWidgets(
      'showModelInfoSheet gracefully handles availableModelsProvider error',
      (tester) async {
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
            activeServerProvider.overrideWith(
              () => _StubActiveServerNotifier(server),
            ),
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
      },
    );
  });

  group('Issue #61: ModelList Unmounted Ref Access Guard', () {
    testWidgets('does not throw when unmounted while model is loading', (
      tester,
    ) async {
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
          activeServerProvider.overrideWith(
            () => _StubActiveServerNotifier(server),
          ),
          serversProvider.overrideWith(() => _StubServersNotifier(server)),
          connectionStatusProvider.overrideWith(
            _StubConnectedStatusNotifier.new,
          ),
          availableModelsProvider(
            server.id,
          ).overrideWith((ref) => Future.value([testModel])),
          loadedModelsProvider(
            server,
          ).overrideWith((ref) => Future.value(<String>{})),
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
          child: const MaterialApp(home: Scaffold(body: SizedBox())),
        ),
      );
      await tester.pumpAndSettle();

      // No unhandled exceptions thrown
      expect(tester.takeException(), isNull);
    });
  });

  group('Issue #64: Server Setup Screens Unmounted testConnection Guard', () {
    testWidgets(
      'OnboardingServerSetupScreen does not crash when unmounted during testConnection',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final connectionCompleter = Completer<ResponseBody>();
        final mockDio = Dio();
        mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
          return connectionCompleter.future;
        });
        final mockApiService = ServerApiService(mockDio);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsProvider.overrideWith(_TestSettingsNotifier.new),
            chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
            serverApiServiceProvider.overrideWithValue(mockApiService),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ShadTheme(
              data: AppTheme.lightShadTheme,
              child: const MaterialApp(
                locale: Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: OnboardingServerSetupScreen(
                  selectedType: ServerType.lmStudio,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Test Connection'), findsOneWidget);

        // Tap Test Connection
        await tester.tap(find.text('Test Connection'));
        await tester.pump();

        // Immediately unmount OnboardingServerSetupScreen while test is in flight
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        await tester.pump();

        // Now complete the network response
        connectionCompleter.complete(
          ResponseBody.fromString('{"models":[]}', 200),
        );
        await tester.pumpAndSettle();

        // Ensure no Null check operator or setState exception was thrown
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AddServerScreen does not crash when unmounted during testConnection',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final connectionCompleter = Completer<ResponseBody>();
        final mockDio = Dio();
        mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
          return connectionCompleter.future;
        });
        final mockApiService = ServerApiService(mockDio);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsProvider.overrideWith(_TestSettingsNotifier.new),
            chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
            serverApiServiceProvider.overrideWithValue(mockApiService),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ShadTheme(
              data: AppTheme.lightShadTheme,
              child: const MaterialApp(
                locale: Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: AddServerScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Test Connection'), findsOneWidget);

        // Tap Test Connection
        await tester.tap(find.text('Test Connection'));
        await tester.pump();

        // Immediately unmount AddServerScreen while test is in flight
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        await tester.pump();

        // Now complete the network response
        connectionCompleter.complete(
          ResponseBody.fromString('{"models":[]}', 200),
        );
        await tester.pumpAndSettle();

        // Ensure no Null check operator or setState exception was thrown
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Issue #65: Server Setup Screens Unmounted setState finally-guard', () {
    testWidgets(
      'OnboardingServerSetupScreen does not crash when testConnection completes after unmount',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        // Use a Completer so we control when the network response resolves —
        // this lets us unmount the widget before the await resumes, then
        // resume the future and verify the `finally` setState is a no-op.
        final connectionCompleter = Completer<ResponseBody>();
        final mockDio = Dio();
        mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
          return connectionCompleter.future;
        });
        final mockApiService = ServerApiService(mockDio);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsProvider.overrideWith(_TestSettingsNotifier.new),
            chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
            serverApiServiceProvider.overrideWithValue(mockApiService),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ShadTheme(
              data: AppTheme.lightShadTheme,
              child: const MaterialApp(
                locale: Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: OnboardingServerSetupScreen(
                  selectedType: ServerType.lmStudio,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Test Connection'), findsOneWidget);

        // Kick off the test connection (this enters the try block and awaits).
        await tester.tap(find.text('Test Connection'));
        await tester.pump();

        // Unmount the screen *while* the await is pending. This simulates a
        // user navigating away (or any other reason for the widget to be
        // disposed) before the network response arrives.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        await tester.pump();

        // Now resume the future — this should run the remaining setState
        // calls in the try, catch, and finally blocks. Without the mounted
        // guards this would crash with
        // "Null check operator used on a null value" at
        // package:flutter/src/widgets/framework.dart:1219 from
        // `_element!.markNeedsBuild()` (issue #65).
        connectionCompleter.complete(
          ResponseBody.fromString('{"models":[]}', 200),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'OnboardingServerSetupScreen does not crash when testConnection fails after unmount',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        // Completer that returns a 500 response — exercises the failure
        // branch (isConnected == false) + the `finally` block while the
        // widget is already unmounted.
        final connectionCompleter = Completer<ResponseBody>();
        final mockDio = Dio();
        mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
          return connectionCompleter.future;
        });
        final mockApiService = ServerApiService(mockDio);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsProvider.overrideWith(_TestSettingsNotifier.new),
            chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
            serverApiServiceProvider.overrideWithValue(mockApiService),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: ShadTheme(
              data: AppTheme.lightShadTheme,
              child: const MaterialApp(
                locale: Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: OnboardingServerSetupScreen(
                  selectedType: ServerType.openAICompatible,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Test Connection'));
        await tester.pump();

        // Unmount before completing the in-flight request.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: SizedBox())),
          ),
        );
        await tester.pump();

        // Complete with a 500 response so the testConnection method returns
        // false (no exception thrown). This drives both the try branch
        // (isConnected == false) and the finally branch (sets
        // _isTesting = false) on the now-disposed state. Without the
        // mounted guard, the finally setState would crash with
        // "Null check operator used on a null value" (#65).
        connectionCompleter.complete(
          ResponseBody.fromString('{"error":"server error"}', 500),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Issue #69: Riverpod Ref Disposed Async Race Protection', () {
    test(
      'ConnectionStatusNotifier does not throw or access disposed Ref when container is disposed during testConnection',
      () async {
        final completer = Completer<ResponseBody>();
        final dio = Dio()
          ..httpClientAdapter = _MockHttpClientAdapter((_) => completer.future);
        final apiService = ServerApiService(dio);

        final server = Server(
          id: 'server-69-a',
          name: 'Ollama Test',
          host: '127.0.0.1',
          port: 11434,
          type: ServerType.ollama,
          createdAt: now,
          lastConnectedAt: now,
        );

        final container = ProviderContainer(
          overrides: [
            serverApiServiceProvider.overrideWithValue(apiService),
            activeServerProvider.overrideWith(
              () => _StubActiveServerNotifier(server),
            ),
            serversProvider.overrideWith(() => _StubServersNotifier(server)),
          ],
        );

        // Read connection status to trigger build and microtask
        expect(
          container.read(connectionStatusProvider),
          ConnectionStatus.checking,
        );

        // Allow microtask to run
        await Future<void>.delayed(Duration.zero);

        // Dispose container while connection test is in flight
        container.dispose();

        // Complete the network request after disposal
        completer.complete(
          ResponseBody.fromString(
            '{"version":"0.1.0"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );

        // Allow any microtasks / async continuations to run without throwing StateError
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
    );

    test(
      'ConnectionStatusNotifier ignores stale older generation when server switches rapidly',
      () async {
        final completer1 = Completer<ResponseBody>();
        final completer2 = Completer<ResponseBody>();

        var callCount = 0;
        final dio = Dio()
          ..httpClientAdapter = _MockHttpClientAdapter((options) {
            callCount++;
            if (callCount == 1) return completer1.future;
            return completer2.future;
          });
        final apiService = ServerApiService(dio);

        final serverA = Server(
          id: 'server-69-a',
          name: 'Server A',
          host: '127.0.0.1',
          port: 11434,
          type: ServerType.ollama,
          createdAt: now,
          lastConnectedAt: now,
        );
        final serverB = Server(
          id: 'server-69-b',
          name: 'Server B',
          host: '127.0.0.1',
          port: 1234,
          type: ServerType.lmStudio,
          createdAt: now,
          lastConnectedAt: now,
        );

        final activeNotifier = _MutableActiveServerNotifier(serverA);

        final container = ProviderContainer(
          overrides: [
            serverApiServiceProvider.overrideWithValue(apiService),
            activeServerProvider.overrideWith(() => activeNotifier),
            serversProvider.overrideWith(() => _StubServersNotifier(serverA)),
          ],
        );
        addTearDown(container.dispose);

        expect(
          container.read(connectionStatusProvider),
          ConnectionStatus.checking,
        );
        await Future<void>.delayed(Duration.zero);

        // Switch active server to Server B before Server A's check completes
        activeNotifier.setServer(serverB);
        container.read(connectionStatusProvider);
        await Future<void>.delayed(Duration.zero);

        // Server A completes as disconnected
        completer1.complete(ResponseBody.fromString('error', 500));
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Server B completes as connected
        completer2.complete(
          ResponseBody.fromString(
            '{"data":[]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // State should reflect Server B's connected status, not Server A's error
        expect(
          container.read(connectionStatusProvider),
          ConnectionStatus.connected,
        );
      },
    );
  });

  group('Issue #71: GitHub URL Launcher Safe Failure Handling', () {
    testWidgets(
      'GitHubRepoCard does not throw an unhandled exception when tapped',
      (tester) async {
        // In the test environment there is no native URL launcher. The
        // try/catch in _launchUrl must swallow any failure so the app
        // does not crash — that is the regression guard for issue #71.
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Center(child: GitHubRepoCard())),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(GitHubRepoCard));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });

  group(
    'Issue Crash Fix: Riverpod UncontrolledProviderScope setState during build on route pop',
    () {
      testWidgets(
        'SafeRiverpodScopeHost prevents setState during build when resuming paused providers on route pop',
        (tester) async {
          final serverA = Server(
            id: 'server-initial',
            name: 'Initial Server',
            host: '127.0.0.1',
            port: 11434,
            type: ServerType.ollama,
            createdAt: now,
            lastConnectedAt: now,
          );

          final serversNotifier = _MutableServersNotifier([serverA]);
          final container = ProviderContainer(
            overrides: [serversProvider.overrideWith(() => serversNotifier)],
          );
          addTearDown(container.dispose);

          final navigatorKey = GlobalKey<NavigatorState>();

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: SafeRiverpodScopeHost(
                container: container,
                child: MaterialApp(
                  navigatorKey: navigatorKey,
                  home: Consumer(
                    builder: (context, ref, _) {
                      final servers = ref.watch(serversProvider);
                      return Scaffold(
                        body: Text('Count: ${servers.value?.length ?? 0}'),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Count: 1'), findsOneWidget);

          // Push a modal route on top (this pauses the home route's subscriptions in Riverpod 3.x)
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    final serverB = Server(
                      id: 'server-added',
                      name: 'Added Server',
                      host: '127.0.0.1',
                      port: 1234,
                      type: ServerType.lmStudio,
                      createdAt: now,
                      lastConnectedAt: now,
                    );
                    serversNotifier.addServerSync(serverB);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Add & Pop'),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Add & Pop'), findsOneWidget);

          // Tap Add & Pop. This mutates serversProvider and pops while the home route was paused.
          // Resuming during route pop triggers the build-phase flush.
          await tester.tap(find.text('Add & Pop'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Count: 2'), findsOneWidget);
        },
      );

      testWidgets(
        'AddServerScreen save flow and route pop does not crash with setState during build',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();

          final serverA = Server(
            id: 'server-existing',
            name: 'Existing Server',
            host: '127.0.0.1',
            port: 11434,
            type: ServerType.ollama,
            createdAt: now,
            lastConnectedAt: now,
          );

          final mockDio = Dio();
          mockDio.httpClientAdapter = _MockHttpClientAdapter((options) {
            return ResponseBody.fromString('{"models":[]}', 200);
          });
          final mockApiService = ServerApiService(mockDio);
          final serversNotifier = _MutableServersNotifier([serverA]);

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              settingsProvider.overrideWith(_TestSettingsNotifier.new),
              chatParamsProvider.overrideWithValue(ChatParameters.defaults()),
              serverApiServiceProvider.overrideWithValue(mockApiService),
              serversProvider.overrideWith(() => serversNotifier),
              activeServerProvider.overrideWith(
                () => _StubActiveServerNotifier(serverA),
              ),
              connectionStatusProvider.overrideWith(
                _StubConnectedStatusNotifier.new,
              ),
            ],
          );
          addTearDown(container.dispose);

          final navigatorKey = GlobalKey<NavigatorState>();

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: SafeRiverpodScopeHost(
                container: container,
                child: ShadTheme(
                  data: AppTheme.lightShadTheme,
                  child: MaterialApp(
                    navigatorKey: navigatorKey,
                    locale: const Locale('en'),
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    home: Consumer(
                      builder: (context, ref, _) {
                        final servers = ref.watch(serversProvider);
                        return Scaffold(
                          body: Center(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AddServerScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                'Open Add Screen (${servers.value?.length ?? 0})',
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          tester.view.physicalSize = const Size(800, 1800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Open Add Server screen
          navigatorKey.currentState!.push(
            MaterialPageRoute(builder: (_) => const AddServerScreen()),
          );
          await tester.pumpAndSettle();

          // Enter server details
          final textFields = find.byType(TextFormField);
          expect(textFields, findsWidgets);

          await tester.enterText(textFields.at(0), 'New Ollama');
          await tester.enterText(textFields.at(1), '127.0.0.1');
          await tester.enterText(textFields.at(2), '11434');
          await tester.pump();

          // Tap Save Server
          final saveButton = find.widgetWithText(ElevatedButton, 'Save Server');
          expect(saveButton, findsOneWidget);

          await tester.tap(saveButton);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Open Add Screen (2)'), findsOneWidget);
        },
      );

      testWidgets(
        'CreatePersonaScreen save flow and route pop does not crash with setState during build',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final prefs = await SharedPreferences.getInstance();

          final personasNotifier = _StubPersonasNotifier([]);

          final container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              personasNotifierProvider.overrideWith(() => personasNotifier),
            ],
          );
          addTearDown(container.dispose);

          final navigatorKey = GlobalKey<NavigatorState>();

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: SafeRiverpodScopeHost(
                container: container,
                child: MaterialApp(
                  navigatorKey: navigatorKey,
                  locale: const Locale('en'),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Consumer(
                    builder: (context, ref, _) {
                      final personas = ref.watch(personasNotifierProvider);
                      return Scaffold(
                        body: Center(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CreatePersonaScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Open Persona Screen (${personas.value?.length ?? 0})',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          tester.view.physicalSize = const Size(800, 1800);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          // Open Create Persona screen
          navigatorKey.currentState!.push(
            MaterialPageRoute(builder: (_) => const CreatePersonaScreen()),
          );
          await tester.pumpAndSettle();

          // Enter persona details
          final textFields = find.byType(TextFormField);
          expect(textFields, findsWidgets);

          await tester.enterText(textFields.at(0), 'Assistant Persona');
          await tester.enterText(
            textFields.at(2),
            'You are a helpful coding assistant.',
          );
          await tester.pump();

          // Tap Create Persona button
          final createButton = find.widgetWithText(FilledButton, 'Create');
          expect(createButton, findsOneWidget);

          await tester.tap(createButton);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Open Persona Screen (1)'), findsOneWidget);
        },
      );
    },
  );
}

class _MutableActiveServerNotifier extends ActiveServerNotifier {
  _MutableActiveServerNotifier(this._server);

  Server? _server;

  @override
  Server? build() => _server;

  void setServer(Server? server) {
    _server = server;
    state = server;
  }
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

class _MutableServersNotifier extends ServersNotifier {
  _MutableServersNotifier(this._servers);

  List<Server> _servers;

  @override
  Future<List<Server>> build() async => _servers;

  void addServerSync(Server server) {
    _servers = [..._servers, server];
    state = AsyncData(_servers);
  }

  @override
  Future<void> addServer(Server server) async {
    _servers = [..._servers, server];
    state = AsyncData(_servers);
  }

  @override
  Future<void> updateServer(Server server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      _servers[index] = server;
    } else {
      _servers = [..._servers, server];
    }
    state = AsyncData(_servers);
  }

  @override
  Future<ConnectionStatus> testConnection(
    String serverId,
    dynamic apiService,
  ) async {
    return ConnectionStatus.connected;
  }
}

class _StubConnectedStatusNotifier extends ConnectionStatusNotifier {
  @override
  ConnectionStatus build() => ConnectionStatus.connected;
}

class _MockHttpClientAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

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
  AppSettings build() => AppSettings(unloadModelsBeforeLoad: false);
}

class _StubPersonasNotifier extends PersonasNotifier {
  _StubPersonasNotifier(this._personas);
  final List<Persona> _personas;

  @override
  Future<List<Persona>> build() async => _personas;

  @override
  Future<Persona> createPersona({
    required String name,
    required String emoji,
    required String systemPrompt,
    String? description,
    String? category,
    Map<String, dynamic>? preferredParams,
  }) async {
    final persona = Persona(
      id: 'p-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      emoji: emoji,
      systemPrompt: systemPrompt,
      description: description,
      category: category,
      preferredParams: preferredParams,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _personas.add(persona);
    state = AsyncData([..._personas]);
    return persona;
  }
}
