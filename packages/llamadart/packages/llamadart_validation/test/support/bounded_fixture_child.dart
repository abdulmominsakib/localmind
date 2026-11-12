import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  stdout.writeln('fixture-out');
  stderr.writeln('fixture-err');
  switch (arguments.first) {
    case 'exit':
      exitCode = 7;
    case 'stdin':
      await stdin.drain<void>();
    case 'hang':
      File(arguments[1]).writeAsStringSync('$pid');
      if (!Platform.isWindows) {
        ProcessSignal.sigterm.watch().listen((_) {});
      }
      Timer.periodic(const Duration(seconds: 30), (_) {});
    default:
      throw ArgumentError('Unknown fixture mode');
  }
}
