import 'dart:io';

import 'package:genkit_llamadart/genkit_llamadart.dart';

/// Shared download/cache manager; the override keeps opt-in CLI tests isolated.
final exampleDownloads = DefaultModelDownloadManager(
  defaultCacheDirectory: Platform.environment['LLAMADART_EXAMPLE_CACHE'],
);

/// Resolves a local path, HTTPS URL or hf:// source without loading a model.
///
/// Owner pools and experimental bidi accept local definitions. Resolving first
/// lets their examples download/cache a source without loading a spare runtime.
Future<String> resolveExampleModel(String source) async =>
    (await exampleDownloads.ensureModel(ModelSource.parse(source))).filePath;
