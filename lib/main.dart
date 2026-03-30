import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app.dart';
import 'core/storage/hive_initializer.dart';
import 'core/providers/storage_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  GoogleFonts.config.allowRuntimeFetching = false;
  
  final hiveBoxes = await HiveInitializer.initialize();
  
  runApp(
    ProviderScope(
      overrides: [
        hiveBoxesProvider.overrideWithValue(hiveBoxes),
      ],
      child: const App(),
    ),
  );
}
