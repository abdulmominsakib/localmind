// Snapshots the development docs for a release. Run from `website/`:
//
//   dart run tool/cut_version.dart 0.8.25
import 'dart:io';

import 'package:llamadart_website/src/tooling/version_cut.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/cut_version.dart <MAJOR.MINOR.PATCH>');
    exit(64);
  }
  final version = args.single;
  if (cutDocsVersion('.', version)) {
    stdout.writeln('[docs] Cut docs version $version.');
  } else {
    stdout.writeln('[docs] Version $version already exists; skipping.');
  }
}
