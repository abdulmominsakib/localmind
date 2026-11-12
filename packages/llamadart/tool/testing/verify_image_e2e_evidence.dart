import 'dart:convert';
import 'dart:io';

import 'package:llamadart/src/hook/native_release_pins.dart';

import '../../example/chat_app/integration_test/support/image_evidence.dart';
// Use the example's maintained model lock without its Flutter package resolver.
// ignore: avoid_relative_lib_imports
import '../../example/chat_app/lib/models/image_model_profile.dart';

/// Validates actual downloaded PNGs; APK/model/runtime provenance stays separate.
void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/testing/verify_image_e2e_evidence.dart '
      '<run-directory> <exact-source-commit> <backend>',
    );
    exitCode = 64;
    return;
  }
  try {
    final profile = ImageModelProfile.sdxs;
    final modelUri = Uri.parse(profile.modelSource.url);
    final result = verifyImageEvidence(
      Directory(arguments[0]),
      expectedCommit: arguments[1],
      expectedBackend: arguments[2],
      expectedRuntimeTag: stableDiffusionReleaseTag,
      expectedModelLock: {
        'id': profile.id,
        'filename': profile.modelSource.filename,
        'sha256': profile.modelSource.sha256,
        'bytes': profile.modelSource.sizeBytes,
        'revision':
            modelUri.pathSegments[modelUri.pathSegments.indexOf('resolve') + 1],
      },
    );
    stdout.writeln(jsonEncode({'verified': true, 'evidence': result}));
  } on Object catch (error) {
    stderr.writeln(
      'Image evidence verification failed (${error.runtimeType}).',
    );
    exitCode = 1;
  }
}
