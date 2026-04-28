import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers/highlighter_provider.dart';
import 'core/providers/storage_providers.dart';
import 'core/storage/objectbox_store.dart';
import 'features/chat/providers/tts_providers.dart';
import 'features/on_device/providers/on_device_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeHighlighter();

  final prefs = await SharedPreferences.getInstance();
  final database = await ObjectBoxStore.create();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(database),
    ],
  );

  // Initialize services
  await container.read(downloadNotificationServiceProvider).init();
  
  // Pre-initialize KittenTTS (neural engine)
  // Don't await it to avoid blocking app startup, but start the process
  container.read(kittenTtsServiceProvider).initialize().catchError((e) {
    debugPrint('Failed to pre-initialize KittenTTS: $e');
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const App(),
    ),
  );
}
