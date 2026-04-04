import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/storage/hive_initializer.dart';
import 'core/providers/storage_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final hiveBoxes = await HiveInitializer.initialize();

  runApp(
    ProviderScope(
      overrides: [hiveBoxesProvider.overrideWithValue(hiveBoxes)],
      child: const App(),
    ),
  );
}
