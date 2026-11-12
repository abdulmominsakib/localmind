import 'dart:convert';
import 'dart:io';

import 'package:llamadart_model_store/src/store_lock.dart';

/// Holds the store lock at `args.first`, printing `locked` once it has it,
/// until a line arrives on stdin.
Future<void> main(List<String> args) async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await StoreLock(args.first).run(() async {
    stdout.writeln('locked');
    await stdout.flush();
    await lines.first;
  });
}
