// A scheduled public-path qualifier; its outer process owns compilation and work.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:llamadart/backend.dart' as spi;
import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/core/url_redaction.dart';
import 'package:llamadart/src/backends/litert_lm/litert_lm_runtime.dart'
    as runtime;
import 'package:llamadart/src/backends/litert_lm/litert_lm_service.dart';

import '../../tool/litert_lm_asr_smoke.dart' as speech;
import '../support/litert_lm_thinking_direct_cache.dart';
import '../support/litert_lm_v1_public_qualification.dart';

Future<String> _digest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();
String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
void _event(String stage, [Map<String, Object?> values = const {}]) =>
    stdout.writeln(
      '$publicLiteRtLmEventPrefix${jsonEncode({'stage': stage, ...values})}',
    );

Future<void> _checkFile(String path, String expected, String label) async {
  try {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected) ||
        await _digest(path) != expected) {
      throw StateError('$label SHA256 mismatch before native loading.');
    }
  } on FileSystemException {
    throw StateError('$label input unavailable before native loading.');
  }
}

Future<List<PublicLiteRtLmPayload>> _checkInputs(
  List<String> args, {
  required bool expectedDisabled,
}) async {
  for (final (path, hash, label) in [
    (args[1], args[2], 'Core'),
    (args[3], args[4], 'Model'),
    (args[5], args[6], 'Runtime manifest'),
    (args[7], args[8], 'Qualification config'),
  ]) {
    await _checkFile(path, hash, label);
  }
  final manifest = publicLiteRtLmRuntimeManifest(
    await File(args[5]).readAsString(),
  );
  final directory = File(args[1]).parent.resolveSymbolicLinksSync();
  final coreName = File(args[1]).uri.pathSegments.last;
  if (!manifest.any(
    (item) => item.name == coreName && item.sha256 == args[2],
  )) {
    throw StateError('The manifest does not bind the supplied core.');
  }
  final suffix = Platform.isMacOS ? '.dylib' : '.so';
  final names = Directory(directory)
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith(suffix))
      .map((file) => file.uri.pathSegments.last)
      .toSet();
  if (names.length != manifest.length ||
      !names.containsAll(manifest.map((item) => item.name))) {
    throw StateError('Runtime manifest must bind every adjacent library.');
  }
  for (final item in manifest) {
    final file = File('$directory/${item.name}');
    if (File(file.resolveSymbolicLinksSync()).parent.path != directory ||
        await file.length() != item.bytes ||
        await _digest(file.path) != item.sha256) {
      throw StateError('Runtime payload identity mismatch: ${item.name}.');
    }
  }
  final config = _config(args[7]);
  if (args[0] == 'speech') {
    for (final name in ['tokenizer', 'audio']) {
      final item = config[name] as Map<String, dynamic>;
      await _checkFile(item['path'] as String, item['sha256'] as String, name);
    }
  } else {
    final model = config['model'] as Map<String, dynamic>;
    if (model['sha256'] != args[4] ||
        model['bytes'] != await File(args[3]).length()) {
      throw StateError('The fixed profile does not bind these model bytes.');
    }
    if (!expectedDisabled &&
        await _digest(args[7]) !=
            await _digest(
              'packages/llamadart_validation/assets/profiles/chat-litert-cpu.json',
            )) {
      throw StateError(
        'Public chat qualification requires the tracked CPU profile.',
      );
    }
  }
  return manifest;
}

void _requireCApi1(DynamicLibrary library) {
  if (!library.providesSymbol('litert_lm_get_api_version')) {
    throw LlamaUnsupportedException(
      'Public v1 qualification requires C API 1.0.',
    );
  }
  final values = calloc<Int32>(3);
  try {
    final status = library
        .lookupFunction<
          Int32 Function(Pointer<Int32>, Pointer<Int32>, Pointer<Int32>),
          int Function(Pointer<Int32>, Pointer<Int32>, Pointer<Int32>)
        >('litert_lm_get_api_version')(values, values + 1, values + 2);
    if (status != 0 || values[0] != 1 || values[1] != 0 || values[2] < 0) {
      throw LlamaUnsupportedException(
        'The supplied core does not admit C API 1.0.x.',
      );
    }
  } finally {
    calloc.free(values);
  }
}

Future<void> _loadedPayloadIdentity(
  List<String> args,
  List<PublicLiteRtLmPayload> manifest,
) async {
  final paths = <String>{};
  if (Platform.isMacOS) {
    final process = DynamicLibrary.process();
    final count = process.lookupFunction<Uint32 Function(), int Function()>(
      '_dyld_image_count',
    );
    final name = process
        .lookupFunction<
          Pointer<Utf8> Function(Uint32),
          Pointer<Utf8> Function(int)
        >('_dyld_get_image_name');
    for (var index = 0; index < count(); index++) {
      final value = name(index);
      if (value != nullptr) paths.add(value.toDartString());
    }
  } else if (Platform.isLinux) {
    for (final line in await File('/proc/self/maps').readAsLines()) {
      final path = line.substring(
        !line.contains('/') ? line.length : line.indexOf('/'),
      );
      if (path.isNotEmpty) paths.add(path);
    }
  }
  final names = {for (final item in manifest) item.name: item};
  final observed = <Map<String, Object?>>[];
  var coreSeen = false;
  for (final path in paths) {
    final name = File(path).uri.pathSegments.last;
    final expected = names[name];
    if (expected == null) continue;
    final digest = await _digest(path);
    observed.add({'name': name, 'sha256': digest});
    if (digest != expected.sha256) {
      throw StateError(
        'Another loaded runtime payload has different bytes: $name.',
      );
    }
    if (name == File(args[1]).uri.pathSegments.last) {
      coreSeen = true;
    }
  }
  _event('loaded_runtime_payloads', {
    'payloads': observed,
    'qualified_core_seen': coreSeen,
  });
  if (!coreSeen) {
    throw StateError('The bound runtime core was not observed loaded.');
  }
}

Map<String, dynamic> _config(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void _chatOracle(Map<String, dynamic> fixture, String answer) {
  if (!RegExp(
        fixture['regex'] as String,
        caseSensitive: false,
      ).hasMatch(answer.trim()) ||
      answer.contains('<think>') ||
      answer.contains('</think>') ||
      answer.contains('<|channel>thought') ||
      answer.contains('<channel|>')) {
    throw StateError('The fixed prescribed chat fixture failed.');
  }
}

Future<void> _direct(List<String> args, bool expectedDisabled) async {
  final profile = _config(args[7]);
  final client = spi.LiteRtLmRuntimeClient(libraryPath: args[1]);
  client.configureResponseThinkingTags(startTag: '<think>', endTag: '</think>');
  final watch = Stopwatch()..start();
  try {
    final directCache = createThinkingDirectCache(Directory(args[9]));
    Future<void> load() => client.initialize(
      modelPath: args[3],
      backend: 'cpu',
      numberOfThreads: profile['threads'] as int,
      maxTokens: profile['context_size'] as int,
      outputTokens: profile['max_tokens'] as int,
      cacheDir: directCache.path,
      speculativeDecoding: false,
    );
    await load();
    if (expectedDisabled) {
      throw StateError('Public direct initialization bypassed disabled v1.');
    }
    if (!client.supportsFinishReasons || !client.supportsMessageRendering) {
      throw StateError(
        'The public direct route lacks v1 finish/render support.',
      );
    }
    void conversation() => client.createConversation(
      promptTemplate: liteRtLmQwen3ChatTemplate,
      extraContext: {'enable_thinking': false},
      temperature: 0,
      topK: 40,
      topP: 0.9,
      seed: 1,
    );
    Future<void> cases(int lifetime) async {
      for (final entry in (profile['fixtures'] as Map).entries) {
        final fixture = entry.value as Map<String, dynamic>;
        conversation();
        final chunks = <String>[];
        await for (final chunk in client.generate(
          fixture['prompt'] as String,
          maxOutputTokens: profile['max_tokens'] as int,
        )) {
          chunks.add(chunk);
        }
        final answer = chunks.join();
        _event('chat_boundary', {
          'lifetime': lifetime,
          'case': entry.key,
          'boundary': 'public RuntimeClient text chunks',
          'chunks': chunks,
          'utf8_hex': _hex(utf8.encode(answer)),
        });
        final metrics = client.readMetrics(
          wallMilliseconds: watch.elapsedMilliseconds,
        );
        _event('chat_observation', {
          'lifetime': lifetime,
          'case': entry.key,
          'boundary': 'public RuntimeClient text chunks',
          'chunks': chunks,
          'utf8_hex': _hex(utf8.encode(answer)),
          'native_finish': client.lastFinishReason?.name,
          'native_settlement': client.nativeSettlement.name,
          'metrics': metrics.toJson(),
        });
        _chatOracle(fixture, answer);
        if (client.nativeSettlement != spi.LiteRtLmNativeSettlement.settled ||
            client.lastFinishReason != spi.LiteRtLmFinishReason.stop ||
            metrics.inputTokens <= 0 ||
            metrics.outputTokens <= 0) {
          throw StateError('Public direct chat did not finish and settle.');
        }
        _event('chat_pass', {'lifetime': lifetime, 'case': entry.key});
      }
    }

    await cases(1);
    conversation();
    var sent = false, received = 0;
    final cancelledChunks = <String>[];
    await for (final chunk in client.generate(
      'Write the numbers 1 through 1000, one per line. Start immediately.',
      maxOutputTokens: 512,
    )) {
      cancelledChunks.add(chunk);
      received += utf8.encode(chunk).length;
      if (!sent && chunk.isNotEmpty) {
        if (client.nativeSettlement != spi.LiteRtLmNativeSettlement.pending) {
          throw StateError('Cancellation did not observe pending native work.');
        }
        client.cancel();
        sent = true;
      }
    }
    _event('cancel', {
      'received_bytes': received,
      'cancel_sent': sent,
      'native_finish': client.lastFinishReason?.name,
      'native_settlement': client.nativeSettlement.name,
      'utf8_hex': _hex(utf8.encode(cancelledChunks.join())),
    });
    if (!sent ||
        received == 0 ||
        client.lastFinishReason != spi.LiteRtLmFinishReason.cancelled ||
        client.nativeSettlement != spi.LiteRtLmNativeSettlement.settled) {
      throw StateError('Public direct cancellation did not settle.');
    }
    await load();
    await cases(2);
  } finally {
    if (client.nativeSettlement != spi.LiteRtLmNativeSettlement.settled) {
      _event('cleanup_retained', {'route': 'direct'});
      await Completer<void>().future;
    }
    client.dispose();
  }
}

Future<void> _service(List<String> args, bool expectedDisabled) async {
  final profile = _config(args[7]);
  // Runtime selection and every fresh capability probe use the public defaults.
  final service = LiteRtLmService(
    linkParentDirectory: Directory('${args[9]}/links')
      ..createSync(recursive: true),
    useTempCacheDir: false,
  );
  final params = ModelParams(
    device: ComputeDevice.cpu,
    numberOfThreads: profile['threads'] as int,
    contextSize: profile['context_size'] as int,
    liteRtLmCacheDir: '${args[9]}/service-cache',
  );
  try {
    Future<({int model, int context})> load() async {
      final model = await service.loadModel(args[3], params);
      return (model: model, context: service.createContext(model, params));
    }

    if (!expectedDisabled) {
      if (!service.reportsFinishReasons()) {
        throw LlamaUnsupportedException(
          'The default service has not admitted the required v1 finish contract; #1677 activation or artifact support is missing.',
        );
      }
      final manifest = publicLiteRtLmRuntimeManifest(
        await File(args[5]).readAsString(),
      );
      await _loadedPayloadIdentity(args, manifest);
    }
    final first = await load();
    if (expectedDisabled) {
      await service.tokenize(first.model, 'hello', false);
      throw StateError('Default service bypassed disabled v1.');
    }
    if (!service.reportsFinishReasons()) {
      throw StateError('Default service did not admit native finish reports.');
    }
    Future<void> cases(int lifetime, int context) async {
      for (final entry in (profile['fixtures'] as Map).entries) {
        final fixture = entry.value as Map<String, dynamic>;
        final bytes = <int>[];
        await for (final chunk in service.generateChat(
          context,
          [
            LlamaChatMessage.fromText(
              role: LlamaChatRole.user,
              text: fixture['prompt'] as String,
            ),
          ],
          GenerationParams(
            maxTokens: profile['max_tokens'] as int,
            temp: 0,
            seed: 1,
          ),
          enableThinking: false,
        )) {
          bytes.addAll(chunk);
        }
        _event('chat_boundary', {
          'lifetime': lifetime,
          'case': entry.key,
          'boundary': 'default service UTF8 chunks',
          'utf8_hex': _hex(bytes),
        });
        final answer = utf8.decode(bytes);
        final metrics = service.getPerformanceContext(context);
        _event('chat_observation', {
          'lifetime': lifetime,
          'case': entry.key,
          'boundary': 'default service UTF8 chunks',
          'utf8_hex': _hex(bytes),
          'answer': answer,
          'native_finish': 'not_exposed_by_default_service',
          'native_settlement': service.nativeSettlement.name,
          'input_tokens': metrics?.promptEvalTokens,
          'output_tokens': metrics?.evalTokens,
        });
        _chatOracle(fixture, answer);
        if (service.nativeSettlement != spi.LiteRtLmNativeSettlement.settled ||
            metrics == null ||
            metrics.promptEvalTokens <= 0 ||
            metrics.evalTokens <= 0) {
          throw StateError('Default service chat did not settle with metrics.');
        }
        _event('chat_pass', {'lifetime': lifetime, 'case': entry.key});
      }
    }

    await cases(1, first.context);
    var sent = false, received = 0;
    final cancelledBytes = <int>[];
    await for (final chunk in service.generateChat(
      first.context,
      const [
        LlamaChatMessage.fromText(
          role: LlamaChatRole.user,
          text:
              'Write the numbers 1 through 1000, one per line. Start immediately.',
        ),
      ],
      const GenerationParams(maxTokens: 512, temp: 0, seed: 1),
      enableThinking: false,
    )) {
      cancelledBytes.addAll(chunk);
      received += chunk.length;
      if (!sent && chunk.isNotEmpty) {
        service.cancelGeneration();
        sent = true;
      }
    }
    _event('cancel', {
      'received_bytes': received,
      'cancel_sent': sent,
      'native_finish': 'not_exposed_by_default_service',
      'native_settlement': service.nativeSettlement.name,
      'utf8_hex': _hex(cancelledBytes),
    });
    if (!sent ||
        received == 0 ||
        service.nativeSettlement != spi.LiteRtLmNativeSettlement.settled) {
      throw StateError('Default service cancellation did not settle.');
    }
    final second = await load();
    if (first == second ||
        first.model == second.model ||
        first.context == second.context) {
      throw StateError('Default service reload retained old public handles.');
    }
    await cases(2, second.context);
  } finally {
    if (service.nativeSettlement != spi.LiteRtLmNativeSettlement.settled) {
      _event('cleanup_retained', {'route': 'service'});
      await Completer<void>().future;
    }
    service.dispose();
  }
}

Future<void> _speech(List<String> args, bool expectedDisabled) async {
  final config = _config(args[7]);
  for (final name in ['tokenizer', 'audio']) {
    final item = config[name] as Map<String, dynamic>;
    await _checkFile(item['path'] as String, item['sha256'] as String, name);
  }
  // runLiteRtLmAsrSmoke constructs SpeechToTextEngine and uses its default driver.
  await speech.runLiteRtLmAsrSmoke(
    [
      args[3],
      (config['tokenizer'] as Map)['path'] as String,
      (config['audio'] as Map)['path'] as String,
      config['preset'] as String,
      config['expected_transcript'] as String,
    ],
    libraryPath: args[1],
    numberOfThreads: 2,
    onObservation: (observation) => _event('speech_observation', observation),
  );
  if (expectedDisabled) {
    throw StateError('Default speech bypassed disabled v1.');
  }
}

Future<void> _child(List<String> args, bool expectedDisabled) async {
  var success = false;
  try {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw LlamaUnsupportedException(
        'This owned public qualifier supports macOS and Linux CPU hosts.',
      );
    }
    final manifest = await _checkInputs(
      args,
      expectedDisabled: expectedDisabled,
    );
    if (Platform.isMacOS) {
      final version = await Process.run('/usr/bin/sw_vers', [
        '-productVersion',
      ]);
      final major = int.tryParse('${version.stdout}'.trim().split('.').first);
      if (version.exitCode != 0 || major == null || major < 14) {
        throw LlamaUnsupportedException(
          'The qualified v1 artifact requires macOS 14 or later.',
        );
      }
    }
    if (args[0] == 'service') {
      final required = runtime.liteRtLmRequiredLibrariesForAbi(Abi.current());
      final missing = required
          .where((name) => !manifest.any((item) => item.name == name))
          .toList();
      _event('discovery_inventory', {
        'legacy_inventory_reference': required,
        'not_a_dynamic_admission_decision': true,
        'manifest': manifest.map((item) => item.name).toList(),
        'missing': missing,
      });
      // Diagnostic only: final discovery may admit a version-specific inventory.
      // The actual default route and loaded-byte check below must still pass.
    }
    _event('identity', {
      'route': args[0],
      'source_revision': args[10],
      'library_sha256': args[2],
      'model_sha256': args[4],
      'runtime_manifest_sha256': args[6],
      'config_sha256': args[8],
      'injected_runtime_factory': false,
      'injected_speech_driver': false,
      'discovery': args[0] == 'service'
          ? 'default LIB_DIR directory'
          : 'public explicit libraryPath',
      'requested_backend': 'cpu',
      'abi': Abi.current().toString(),
    });
    final suppliedCore = DynamicLibrary.open(args[1]);
    _requireCApi1(suppliedCore);
    await _loadedPayloadIdentity(args, manifest);
    DynamicLibrary? fixture;
    if (expectedDisabled) {
      fixture = suppliedCore;
      if (!fixture.providesSymbol('fixture_public_engine_attempts')) {
        throw StateError(
          'The disabled-selection control requires a compiled model-free fixture.',
        );
      }
    }
    try {
      await switch (args[0]) {
        'direct' => _direct(args, expectedDisabled),
        'service' => _service(args, expectedDisabled),
        'speech' => _speech(args, expectedDisabled),
        _ => throw ArgumentError('Unknown public path.'),
      };
      if (expectedDisabled) {
        throw StateError('The disabled-selection control did not refuse.');
      }
      success = true;
    } on LlamaException catch (error) {
      if (!expectedDisabled || !error.toString().contains('#1677')) rethrow;
      final attempts = fixture!.lookupFunction<Int Function(), int Function()>(
        'fixture_public_engine_attempts',
      )();
      _event('disabled', {
        'error_type': error.runtimeType.toString(),
        'mentions_migration': true,
        'engine_attempts': attempts,
      });
      success = attempts == 0;
    }
    // Recheck every bound input after the selected route finishes or refuses.
    await _loadedPayloadIdentity(args, manifest);
    await _checkInputs(args, expectedDisabled: expectedDisabled);
  } on Object catch (error) {
    success = false;
    var detail = redactUrlSecrets('$error');
    final paths = <String>{
      for (final index in [1, 3, 5, 7, 9]) ...[
        args[index],
        File(args[index]).parent.path,
      ],
    }.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final path in paths) {
      if (path.length > 1) {
        detail = detail.replaceAll(path, '<qualification-input>');
      }
    }
    _event('failure', {
      'type': error.runtimeType.toString(),
      'detail': detail.substring(0, detail.length.clamp(0, 512)),
    });
  }
  _event('run_end', {
    'success': success,
    'qualified_public_v1': success && !expectedDisabled,
  });
  exitCode = success ? 0 : 1;
}

class _OwnedResult {
  const _OwnedResult(
    this.code,
    this.timedOut,
    this.pid,
    this.exitConfirmed,
    this.outBytes,
    this.errBytes,
  );
  final int code;
  final bool timedOut;
  final int pid;
  final bool exitConfirmed;
  final List<int> outBytes;
  final List<int> errBytes;
  String get out => utf8.decode(outBytes, allowMalformed: true);
  String get err => utf8.decode(errBytes, allowMalformed: true);
}

Future<_OwnedResult> _owned(
  String executable,
  List<String> args,
  Duration timeout, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    args,
    environment: environment,
  );
  final out = <int>[], err = <int>[];
  final stdoutDone = Completer<void>(), stderrDone = Completer<void>();
  final stdoutSubscription = process.stdout.listen(
    out.addAll,
    onDone: stdoutDone.complete,
  );
  final stderrSubscription = process.stderr.listen(
    err.addAll,
    onDone: stderrDone.complete,
  );
  var timed = false, confirmed = true;
  final code = await process.exitCode.timeout(
    timeout,
    onTimeout: () async {
      timed = true;
      process.kill(ProcessSignal.sigkill);
      return process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          confirmed = false;
          return 124;
        },
      );
    },
  );
  try {
    await Future.wait([
      stdoutDone.future,
      stderrDone.future,
    ]).timeout(const Duration(seconds: 5));
  } on TimeoutException {
    timed = true;
  }
  await stdoutSubscription.cancel();
  await stderrSubscription.cancel();
  return _OwnedResult(code, timed, process.pid, confirmed, out, err);
}

Future<void> main(List<String> supplied) async {
  final child = supplied.isNotEmpty && supplied.first == '--child';
  var args = child ? supplied.sublist(1) : supplied;
  final expectedDisabled = args.isNotEmpty && args.first == '--expect-disabled';
  if (expectedDisabled) args = args.sublist(1);
  if (args.length != (child ? 11 : 9) ||
      !['direct', 'service', 'speech'].contains(args.first)) {
    throw ArgumentError(
      'Expected route, library/SHA, model/SHA, runtime manifest/SHA and profile-or-speech-config/SHA.',
    );
  }
  if (child) return _child(args, expectedDisabled);
  Future<String> git(List<String> arguments) async {
    final result = await Process.run('git', arguments);
    if (result.exitCode != 0) {
      throw StateError('Cannot identify qualification source.');
    }
    return '${result.stdout}'.trim();
  }

  if ((await git(['status', '--porcelain'])).isNotEmpty) {
    throw StateError('Public qualification requires clean committed source.');
  }
  final revision = await git(['rev-parse', 'HEAD']),
      tree = await git(['rev-parse', 'HEAD^{tree}']);
  Future<bool> unchanged() async =>
      (await git(['status', '--porcelain'])).isEmpty &&
      await git(['rev-parse', 'HEAD']) == revision;
  final output = await Directory.systemTemp.createTemp('litert_v1_public_');
  final executable = '${output.path}/public_qualifier';
  final compiled = await _owned(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'test/fixtures/litert_lm_v1_public_qualification.dart',
    '-o',
    executable,
  ], const Duration(minutes: 2));
  await File(
    '${output.path}/compile.log',
  ).writeAsBytes([...compiled.outBytes, 10, ...compiled.errBytes]);
  await File('${output.path}/compile-process.json').writeAsString(
    jsonEncode({
      'pid': compiled.pid,
      'exitCode': compiled.code,
      'timedOut': compiled.timedOut,
      'exitConfirmed': compiled.exitConfirmed,
    }),
  );
  if (compiled.code != 0 || compiled.timedOut || !await unchanged()) {
    throw StateError(
      'Owned public qualifier compilation failed; evidence ${output.path}.',
    );
  }
  final scratch = await Directory('${output.path}/scratch').create();
  final process = await _owned(
    executable,
    [
      '--child',
      if (expectedDisabled) '--expect-disabled',
      ...args,
      scratch.path,
      revision,
    ],
    const Duration(minutes: 4),
    environment: {
      'TMPDIR': scratch.path,
      'LLAMADART_LITERT_LM_LIB_DIR': File(args[1]).parent.path,
    },
  );
  // Persist raw process output before evaluating any aggregate receipt assertions.
  await File('${output.path}/stdout.log').writeAsBytes(process.outBytes);
  await File('${output.path}/native-stderr.log').writeAsBytes(process.errBytes);
  final events = process.out
      .split('\n')
      .where((line) => line.startsWith(publicLiteRtLmEventPrefix))
      .map(
        (line) =>
            jsonDecode(line.substring(publicLiteRtLmEventPrefix.length))
                as Map<String, dynamic>,
      )
      .toList();
  final configBytes = await File(args[7]).readAsBytes();
  final configUnchanged = sha256.convert(configBytes).toString() == args[8];
  final errors = publicLiteRtLmReceiptErrors(
    events,
    args[0],
    expectedDisabled: expectedDisabled,
    profile: args[0] == 'speech'
        ? null
        : jsonDecode(utf8.decode(configBytes)) as Map<String, dynamic>,
  );
  if (!configUnchanged) {
    errors.add('The qualification config changed before aggregate validation.');
  }
  final sourceUnchanged = await unchanged();
  final passed =
      process.code == 0 &&
      !process.timedOut &&
      sourceUnchanged &&
      errors.isEmpty;
  final receipt = {
    'passed': passed,
    'route': args[0],
    'sourceRevision': revision,
    'sourceTree': tree,
    'sourceUnchanged': sourceUnchanged,
    'executableSha256': await _digest(executable),
    'runtimeManifestSha256': args[6],
    'configSha256': args[8],
    'librarySha256': args[2],
    'modelSha256': args[4],
    'injectedRuntimeFactory': false,
    'injectedSpeechDriver': false,
    'timeoutSeconds': 240,
    'timedOut': process.timedOut,
    'exitCode': process.code,
    'ownedChildPid': process.pid,
    'exitConfirmed': process.exitConfirmed,
    'errors': errors,
    'events': events,
    'evidenceDirectory': output.path,
  };
  await File(
    '${output.path}/receipt.json',
  ).writeAsString('${jsonEncode(receipt)}\n');
  stdout.writeln(jsonEncode(receipt));
  if (!passed) exitCode = 1;
}
