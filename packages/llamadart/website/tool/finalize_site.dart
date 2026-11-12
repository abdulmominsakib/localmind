// Turns `jaspr build` output into the deployed site and fails on broken
// internal links. Run from `website/` after `jaspr build`.
import 'dart:io';

import 'package:llamadart_website/src/tooling/site_output.dart';

void main(List<String> args) {
  final output = SiteOutput(
    Directory(args.isEmpty ? 'build/jaspr' : args.single),
  );
  if (!File('${output.directory.path}/index.html').existsSync()) {
    stderr.writeln('[docs] ERROR: ${output.directory.path} has no index.html.');
    exit(1);
  }
  output
    ..removeBuildArtifacts()
    ..flattenPages();
  final notFound = File('${output.directory.path}/404.html');
  if (!notFound.existsSync()) {
    stderr.writeln('[docs] ERROR: the build produced no 404 page.');
    exit(1);
  }
  final indexed = output.writeSitemap();
  final broken = output.brokenLinks();
  if (broken.isNotEmpty) {
    stderr.writeln('[docs] ERROR: ${broken.length} broken internal links:');
    for (final problem in broken.take(50)) {
      stderr.writeln('  $problem');
    }
    exit(1);
  }
  stdout.writeln(
    '[docs] ${output.routes().length} pages, ${indexed.length} in the '
    'sitemap, no broken internal links.',
  );
}
