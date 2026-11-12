import 'dart:io';

/// Publisher staging excludes generated resolution/build files before pub
/// applies the package's own ignore rules, outside ancestor .pubignore files.
const Set<String> companionStagingExclusions = {
  '.dart_tool',
  'build',
  'pubspec.lock',
  'pubspec_overrides.yaml',
};

/// Copies the publisher's package inputs to a new standalone directory.
///
/// Links are copied without following them, as with the publisher's rsync -a.
/// Pub owns final selection; this does not implement .pubignore matching.
void stageCompanionPackage(Directory source, Directory destination) {
  final root = source.resolveSymbolicLinksSync();
  final normalized = Directory.fromUri(
    destination.absolute.uri.normalizePath(),
  );
  final parent = normalized.parent.resolveSymbolicLinksSync();
  final name = normalized.uri.pathSegments.where((s) => s.isNotEmpty).last;
  final target = '$parent${Platform.pathSeparator}$name';
  if (FileSystemEntity.typeSync(target, followLinks: false) !=
          FileSystemEntityType.notFound ||
      target == root ||
      target.startsWith('$root${Platform.pathSeparator}')) {
    throw StateError('Choose a new staging directory outside the package.');
  }
  destination.createSync(recursive: true);
  void copy(Directory from, Directory to) {
    for (final entity in from.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (companionStagingExclusions.contains(name)) continue;
      final path = '${to.path}${Platform.pathSeparator}$name';
      if (entity is Directory) {
        final child = Directory(path)..createSync();
        copy(entity, child);
      } else if (entity is File) {
        entity.copySync(path);
      } else if (entity is Link) {
        Link(path).createSync(entity.targetSync());
      } else {
        throw StateError('Companion staging requires regular files.');
      }
    }
  }

  copy(Directory(root), destination);
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart tool/release/stage_companion_package.dart <source> <new-directory>',
    );
    exitCode = 64;
    return;
  }
  try {
    stageCompanionPackage(Directory(arguments[0]), Directory(arguments[1]));
  } on Object {
    stderr.writeln(
      'Could not stage companion package; no package was published.',
    );
    exitCode = 1;
  }
}
