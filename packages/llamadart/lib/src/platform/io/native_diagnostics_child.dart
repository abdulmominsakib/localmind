import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'native_diagnostics.dart';
import 'native_diagnostics_hook_cache.dart';
import 'native_diagnostics_probe.dart';

/// Private source entry point. Native stdout/stderr are discarded by its owner.
Future<void> main() async {
  try {
    final bytes = <int>[];
    await for (final chunk in stdin) {
      if (bytes.length + chunk.length > 32 * 1024) {
        exitCode = 1;
        return;
      }
      bytes.addAll(chunk);
    }
    final request = decodeNativeDiagnosticJson(utf8.decode(bytes));
    if (request is! Map ||
        request.keys.join(',') != 'runtime,nonce,output,phase,manifest,abi' ||
        !nativeDiagnosticRuntimes.contains(request['runtime']) ||
        request['nonce'] is! String ||
        !RegExp(r'^[a-f0-9]{48}$').hasMatch(request['nonce'] as String) ||
        request['output'] is! String ||
        request['phase'] is! String ||
        request['manifest'] is! String ||
        request['abi'] is! String ||
        !RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(request['abi'] as String)) {
      exitCode = 1;
      return;
    }
    final output = File(request['output'] as String);
    final phase = File(request['phase'] as String);
    if (!path.isAbsolute(output.path) ||
        !path.isAbsolute(phase.path) ||
        output.path.length > 4096 ||
        phase.path.length > 4096 ||
        path.basename(output.path) != 'result.json' ||
        path.basename(phase.path) != 'phase' ||
        path.dirname(output.path) != path.dirname(phase.path) ||
        !path
            .basename(path.dirname(output.path))
            .startsWith('llamadart_native_diagnostic_')) {
      exitCode = 1;
      return;
    }
    final manifest = File(request['manifest'] as String);
    if (!path.isAbsolute(manifest.path) ||
        manifest.path.length > 4096 ||
        manifest.path.contains('\u0000')) {
      exitCode = 1;
      return;
    }
    phase.writeAsStringSync('declaration', flush: true);
    var source = 'local_manifest_declaration';
    Map<String, Object> observeDeclaration() {
      final type = FileSystemEntity.typeSync(manifest.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return nativeDiagnosticObservation(
          request['runtime'] as String,
          'ASSET_DECLARATION_UNAVAILABLE',
          phase: 'declaration',
        );
      }
      NativeDiagnosticTarget? target;
      try {
        target = parseNativeDiagnosticManifest(
          readNativeDiagnosticFile(manifest, 256 * 1024),
          request['abi'] as String,
          request['runtime'] as String,
        );
      } catch (_) {
        return nativeDiagnosticObservation(
          request['runtime'] as String,
          'ASSET_DECLARATION_INVALID',
          phase: 'declaration',
        );
      }
      if (target == null && request['runtime'] == 'litert_lm') {
        // The macOS hook keeps LiteRT-LM in its cache instead of declaring it.
        target = nativeDiagnosticLiteRtLmHookCacheTarget(
          File(path.join(path.dirname(manifest.path), 'package_config.json')),
          request['abi'] as String,
        );
        if (target != null) source = 'build_hook_cache';
      }
      if (target == null) {
        return nativeDiagnosticObservation(
          request['runtime'] as String,
          'ASSET_NOT_DECLARED',
          phase: 'declaration',
        );
      }
      return probeNativeDiagnostic(
        request['runtime'] as String,
        target,
        onPhase: (value) => phase.writeAsStringSync(value, flush: true),
      );
    }

    final observation = observeDeclaration();
    await output.writeAsString(
      jsonEncode({
        'runtime': request['runtime'],
        'nonce': request['nonce'],
        'code': observation['code'],
        'phase': observation['phase'],
        'marker': observation['abi_marker'],
        'source': source,
      }),
      flush: true,
    );
  } catch (_) {
    exitCode = 1;
  }
}
