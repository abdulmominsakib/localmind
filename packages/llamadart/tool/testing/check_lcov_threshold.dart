import 'dart:io';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/testing/check_lcov_threshold.dart <lcov-file> <threshold-percent>',
    );
    exitCode = 64;
    return;
  }

  final lcovFile = File(args[0]);
  if (!lcovFile.existsSync()) {
    stderr.writeln('LCOV file not found: ${lcovFile.path}');
    exitCode = 66;
    return;
  }

  final threshold = double.tryParse(args[1]);
  if (threshold == null || threshold < 0 || threshold > 100) {
    stderr.writeln('Threshold must be a number between 0 and 100.');
    exitCode = 64;
    return;
  }

  var linesFound = 0;
  var linesHit = 0;

  for (final line in lcovFile.readAsLinesSync()) {
    if (line.startsWith('LF:')) {
      linesFound += int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      linesHit += int.parse(line.substring(3));
    }
  }

  final coverage = linesFound == 0 ? 0.0 : (linesHit * 100.0 / linesFound);
  stdout.writeln(
    'LCOV line coverage: ${coverage.toStringAsFixed(2)}% ($linesHit/$linesFound)',
  );

  if (coverage + 1e-9 < threshold) {
    stderr.writeln(
      'Coverage ${coverage.toStringAsFixed(2)}% is below required ${threshold.toStringAsFixed(2)}%.',
    );
    exitCode = 1;
  }
}
