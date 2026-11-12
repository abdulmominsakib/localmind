import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:llamadart_validation/src/desktop_bundle.dart';
import 'package:llamadart_validation/src/runtime_environment.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  try {
    final options = parseOptions(args, {
      'help',
      'list',
      'assets',
      'profile',
      'profile-file',
      'model',
      'projector',
      'cache',
      'out',
      'run-id',
      'environment-file',
      'native-log',
    });
    final assets =
        options['assets'] ??
        p.join(File.fromUri(Platform.script).parent.parent.path, 'assets');
    if (options.containsKey('help')) {
      stdout.writeln(
        'llamadart-validate --profile <id> [--model <verified-file>] '
        '[--out <new-directory>] [--cache <directory>] [--assets <directory>] '
        '[--native-log <captured-stderr-path>]\n'
        '--list lists bundled profiles. --profile-file loads an explicit locked manifest.',
      );
      return;
    }
    if (options.containsKey('list')) {
      for (final file in Directory(
        p.join(assets, 'profiles'),
      ).listSync().whereType<File>()) {
        if (file.path.endsWith('.json')) {
          stdout.writeln(p.basenameWithoutExtension(file.path));
        }
      }
      return;
    }
    // The caller redirects native stderr before launching this process.
    // Reject a missing or invalid capture before any model work begins.
    if (options['native-log'] case final path?) {
      File(path).readAsStringSync();
    }
    requireValidationRuntimeEnvironment();
    final launchDirectory = Directory.current.path;
    // Resolve caller paths before anchoring runtime discovery in the bundle.
    for (final name in [
      'assets',
      'profile-file',
      'model',
      'projector',
      'cache',
      'out',
      'environment-file',
      'native-log',
    ]) {
      if (options[name] != null) options[name] = p.absolute(options[name]!);
    }
    final assetRoot = p.absolute(assets);
    final executableRoot = File(Platform.resolvedExecutable).parent.parent;
    final bundleManifest = File(
      p.join(executableRoot.path, 'bundle-manifest.json'),
    );
    final portable = bundleManifest.existsSync();
    final Map<String, dynamic> provenance;
    if (portable) {
      provenance = await verifyDesktopValidationBundle(executableRoot);
      if (options['environment-file'] case final requested?) {
        final supplied = File(requested).readAsStringSync();
        final bundled = File(
          p.join(executableRoot.path, 'environment.json'),
        ).readAsStringSync();
        if (supplied != bundled) {
          throw const FormatException('Use the bundled desktop environment');
        }
      }
      // LiteRT searches CWD before executable-relative caches. The verified
      // bundle must be first, regardless of where the user launched the CLI.
      Directory.current = executableRoot;
    } else {
      if (const bool.fromEnvironment('dart.vm.product')) {
        throw const FormatException('Portable validation bundle is missing');
      }
      provenance = {
        if (options['environment-file'] case final path?)
          ...jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
        'runtime_payload_verified': false,
      };
    }
    final profileId = options['profile'] ?? 'tiny-gguf-cpu';
    if (!RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(profileId)) {
      throw const FormatException('Invalid profile id');
    }
    final profile = ValidationProfile.fromJson(
      jsonDecode(
            File(
              options['profile-file'] ??
                  p.join(assetRoot, 'profiles', '$profileId.json'),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
    final runId =
        options['run-id'] ??
        'local-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final directory = Directory(
      options['out'] ??
          p.join(launchDirectory, '.dart_tool', 'validation', 'runs', runId),
    );
    final journal = FileValidationJournal(directory);
    try {
      final cache = Directory(
        options['cache'] ??
            p.join(launchDirectory, '.dart_tool', 'validation', 'model-cache'),
      );
      final prepared = await prepareModel(
        profile,
        cache,
        suppliedPath: options['model'],
        onProgress: journal.emitPreparation,
      );
      final projector = profile.isEmbedding
          ? await prepareEmbeddingProjector(
              profile,
              cache,
              suppliedPath: options['projector'],
              onProgress: journal.emitPreparation,
            )
          : null;
      final visionProjector = profile.toolResultProjector == null
          ? null
          : await prepareToolResultProjector(
              profile,
              cache,
              suppliedPath: options['projector'],
              onProgress: journal.emitPreparation,
            );
      final decision = profile.isDecision
          ? await prepareDecisionAssets(
              profile,
              cache,
              onProgress: journal.emitPreparation,
            )
          : null;
      final environment = <String, dynamic>{
        ...provenance,
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
        'dart': Platform.version,
        'build_mode': const bool.fromEnvironment('dart.vm.product')
            ? 'release'
            : 'jit',
      };
      final runner = ValidationRunner(
        profile: profile,
        engine: profile.isEmbedding
            ? PublicEmbeddingValidationEngine(projector: projector!.path)
            : PublicValidationEngine(
                decisionHead: decision?.head,
                decisionConfig: decision?.config,
                projector: visionProjector?.path,
              ),
        emit: journal.emit,
        stateWorkspaceFactory: IoStateValidationWorkspace.create,
        embeddingAssets: profile.isEmbedding
            ? {
                for (final name
                    in (embeddingValidationFixture['files'] as Map).keys)
                  name as String: Uint8List.fromList(
                    File(
                      p.join(assetRoot, 'embeddings', 'v1', name),
                    ).readAsBytesSync(),
                  ),
              }
            : null,
        decisionReference: profile.isDecision
            ? File(
                p.join(
                  p.dirname(assetRoot),
                  profile.fixtureText('decision', 'reference'),
                ),
              ).readAsStringSync()
            : null,
      );
      final interrupt = ProcessSignal.sigint.watch().listen(
        (_) => runner.cancel(),
      );
      try {
        await runner.run(
          prepared.path,
          runId: runId,
          environment: environment,
          preparation: {
            ...prepared.evidence,
            ...?decision?.evidence,
            if (projector != null) 'embedding_projector': projector.evidence,
            if (visionProjector != null) 'projector': visionProjector.evidence,
          },
        );
      } finally {
        await interrupt.cancel();
      }
    } catch (error) {
      await journal.emit({
        'type': 'preparation_error',
        'message': redactDiagnostic('$error'),
      });
      rethrow;
    } finally {
      journal.close();
      await stderr.flush();
      final report = writeRunReports(
        directory,
        nativeLogPath: options['native-log'],
      );
      stdout.writeln(
        'REPORT ${p.join(directory.absolute.path, 'summary.html')}',
      );
      if (!report.qualified) exitCode = 1;
    }
  } catch (error) {
    stderr.writeln(redactDiagnostic('$error'));
    exitCode = 1;
  }
}

/// Writes the launcher report using the same captured native log as the reporter.
/// An absent option retains the existing qualification rules; an unreadable or
/// invalid UTF-8 capture throws instead of silently dropping accelerator proof.
ValidationReport writeRunReports(
  Directory directory, {
  String? nativeLogPath,
}) => writeReports(
  directory,
  nativeLog: nativeLogPath == null
      ? null
      : File(nativeLogPath).readAsStringSync(),
);
