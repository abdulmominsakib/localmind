import 'dart:io';

import 'package:llamadart_validation/io.dart';

void main(List<String> args) {
  if (args.length != 1 && !(args.length == 3 && args[1] == '--native-log')) {
    stderr.writeln('Usage: report <run-directory> [--native-log <path>]');
    exitCode = 64;
    return;
  }
  try {
    exitCode =
        writeReports(
          Directory(args.first),
          nativeLog: args.length == 3 ? File(args[2]).readAsStringSync() : null,
        ).qualified
        ? 0
        : 1;
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
