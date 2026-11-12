import 'dart:io';

/// The `version` this checkout's core `pubspec.yaml` declares.
String readCheckoutCoreVersion() => RegExp(
  r'^version:\s*(\S+)\s*$',
  multiLine: true,
).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
