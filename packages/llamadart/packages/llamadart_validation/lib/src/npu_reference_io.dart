import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import 'manifest.dart';
import 'native_reference_request.dart';
import 'npu_evidence.dart';
import 'npu_monitor_io.dart';
import 'runner.dart';

/// Direct upstream C API control on a dedicated isolate. It intentionally
/// bypasses LlamaEngine, the public backend, its worker and conversation adapter.
class NativeNpuReferenceEngine implements ValidationEngine {
  NativeNpuReferenceEngine(this.monitor, this.probeLibrary);
  final NpuExecutionMonitor monitor;
  final String probeLibrary;
  ReceivePort? _receive;
  Isolate? _isolate;
  SendPort? _send;
  int _id = 0;
  final _pending = <int, Completer<Map<String, dynamic>>>{};

  Future<void> _start() async {
    if (_send != null) return;
    final ready = Completer<SendPort>();
    _receive = ReceivePort();
    _receive!.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is Map) {
        final pending = _pending.remove(message['id']);
        if (message['error'] != null) {
          pending?.completeError(StateError(message['error'] as String));
        } else {
          pending?.complete(
            Map<String, dynamic>.from(message['result'] as Map),
          );
        }
      }
    });
    _isolate = await Isolate.spawn(_worker, _receive!.sendPort);
    _send = await ready.future;
  }

  Future<Map<String, dynamic>> _call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    await _start();
    final id = _id++;
    final pending = Completer<Map<String, dynamic>>();
    _pending[id] = pending;
    _send!.send({'id': id, 'method': method, 'args': args});
    return pending.future;
  }

  @override
  bool get isWeb => false;

  @override
  Future<void> load(String location, ValidationProfile profile) async {
    await _call('load', {
      'model': location,
      'directory': monitor.dispatchDirectory,
      'probe': probeLibrary,
      'identity': monitor.identity,
      'context': profile.contextSize,
      'threads': profile.threads,
    });
  }

  @override
  Future<Map<String, dynamic>> generate(
    String prompt,
    ValidationProfile profile, {
    bool raw = false,
    int? maxTokens,
    int? streamBatchTokens,
    int? streamBatchBytes,
    bool cancelAfterFirst = false,
    bool cancelOnListen = false,
    int? cancelAfterMs,
    List<LlamaChatMessage>? history,
    List<String>? stopSequences,
    bool? enableThinking,
    List<ToolDefinition>? tools,
    ToolChoice? toolChoice,
    String? grammar,
  }) {
    if (enableThinking != null ||
        tools != null ||
        toolChoice != null ||
        grammar != null) {
      throw UnsupportedError(
        "Native control does not implement feature overrides",
      );
    }
    if (stopSequences != null) {
      throw LlamaUnsupportedException(
        'Native reference has no public stop filter',
      );
    }
    if (streamBatchTokens != null || streamBatchBytes != null) {
      throw LlamaUnsupportedException(
        'Direct native control has no public worker batching',
      );
    }
    if (raw || cancelAfterFirst || cancelOnListen || cancelAfterMs != null) {
      throw UnsupportedError(
        'Native reference only covers blocking text conversations',
      );
    }
    return _call('generate', {
      'prompt': prompt,
      'max_tokens': maxTokens ?? profile.maxTokens,
      'wire': nativeReferenceRequest(prompt, history: history),
      if (history != null) 'messages': history.map((m) => m.toJson()).toList(),
    });
  }

  @override
  Future<Map<String, dynamic>> generateOverlapping(
    String first,
    String second,
    ValidationProfile profile, {
    required bool raw,
    required int firstMaxTokens,
    required bool cancelFirst,
    int? secondAfterMs,
  }) => throw UnsupportedError(
    'Native reference only covers blocking text conversations',
  );

  @override
  Future<Map<String, dynamic>> diagnostics() async => {
    'backend_name': 'LiteRT-LM NPU direct C API',
    'backend_selector_only': true,
    'npu_identity': monitor.identity,
  };
  @override
  Future<void> unload() async {
    if (_send != null) await _call('unload');
  }

  @override
  Future<void> dispose() async {
    await unload();
    _isolate?.kill();
    _receive?.close();
    _send = null;
    _isolate = null;
    _receive = null;
  }

  @override
  void cancel() {} // Cancellation is tested on the public path, not this control.
  @override
  Future<List<int>> tokenize(String text) =>
      throw UnsupportedError('Not a native control case');
  @override
  Future<String> detokenize(List<int> tokens) =>
      throw UnsupportedError('Not a native control case');
}

void _worker(SendPort parent) {
  final receive = ReceivePort();
  _Capi? engine;
  parent.send(receive.sendPort);
  receive.listen((dynamic raw) {
    final message = raw as Map;
    try {
      final args = Map<String, dynamic>.from(message['args'] as Map);
      Map<String, dynamic> result = {};
      switch (message['method']) {
        case 'load':
          engine?.close();
          engine = null;
          engine = _Capi(args);
        case 'generate':
          result = engine!.generate(
            args['prompt'] as String,
            args['max_tokens'] as int,
            Map<String, dynamic>.from(args['wire'] as Map),
          );
          if (args['messages'] != null) result['messages'] = args['messages'];
        case 'unload':
          engine?.close();
          engine = null;
        default:
          throw StateError('Unknown native reference command');
      }
      parent.send({'id': message['id'], 'result': result});
    } catch (error) {
      parent.send({'id': message['id'], 'error': redactDiagnostic('$error')});
    }
  });
}

// These signatures come directly from the pinned upstream c/engine.h and
// c/conversation.h. No generated/public Dart backend bindings are imported.
class _Capi {
  _Capi(Map<String, dynamic> args)
    : library = DynamicLibrary.open(
        p.join(args['directory'] as String, 'libLiteRtLm.so'),
      ),
      monitor = AndroidNpuMonitor(
        args['directory'] as String,
        args['probe'] as String,
        Map<String, dynamic>.from(args['identity'] as Map),
      ) {
    final model = (args['model'] as String).toNativeUtf8();
    final backend = 'npu'.toNativeUtf8();
    final directory = (args['directory'] as String).toNativeUtf8();
    Pointer<Void> settings = nullptr;
    try {
      settings = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
            ),
            Pointer<Void> Function(
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Utf8>,
            )
          >(
            'litert_lm_engine_settings_create',
          )(model, backend, nullptr, nullptr);
      _required(settings, 'engine settings');
      setInt(
        'engine_settings_set_max_num_tokens',
        settings,
        args['context'] as int,
      );
      setInt(
        'engine_settings_set_num_threads',
        settings,
        args['threads'] as int,
      );
      library.lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>),
        void Function(Pointer<Void>, Pointer<Utf8>)
      >('litert_lm_engine_settings_set_litert_dispatch_lib_dir')(
        settings,
        directory,
      );
      drop('engine_settings_enable_benchmark', settings);
      handle = createFrom('engine_create', settings);
      _required(handle, 'engine');
    } finally {
      if (settings != nullptr) drop('engine_settings_delete', settings);
      calloc.free(model);
      calloc.free(backend);
      calloc.free(directory);
    }
  }
  final DynamicLibrary library;
  final AndroidNpuMonitor monitor;
  Pointer<Void> handle = nullptr;
  String _name(String suffix) => 'litert_lm_$suffix';
  Pointer<Void> create(String name) => library
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        _name(name),
      )();
  Pointer<Void> createFrom(String name, Pointer<Void> value) =>
      library.lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >(_name(name))(value);
  void drop(String name, Pointer<Void> value) =>
      library.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >(_name(name))(value);
  void setInt(String name, Pointer<Void> value, int number) =>
      library.lookupFunction<
        Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)
      >(_name(name))(value, number);
  void setPointer(String name, Pointer<Void> value, Pointer<Void> other) =>
      library.lookupFunction<
        Void Function(Pointer<Void>, Pointer<Void>),
        void Function(Pointer<Void>, Pointer<Void>)
      >(_name(name))(value, other);
  void setJson(String name, Pointer<Void> value, String? json) {
    if (json == null) return;
    final text = json.toNativeUtf8();
    try {
      library.lookupFunction<
        Void Function(Pointer<Void>, Pointer<Utf8>),
        void Function(Pointer<Void>, Pointer<Utf8>)
      >(_name(name))(value, text);
    } finally {
      calloc.free(text);
    }
  }

  double metric(String name, Pointer<Void> info) =>
      library.lookupFunction<
        Double Function(Pointer<Void>),
        double Function(Pointer<Void>)
      >(_name(name))(info);
  static void _required(Pointer<Void> value, String kind) {
    if (value == nullptr) {
      throw StateError(
        'Direct C API failed to create $kind; inspect native log',
      );
    }
  }

  void close() {
    if (handle != nullptr) {
      drop('engine_delete', handle);
      handle = nullptr;
    }
  }

  Map<String, dynamic> generate(
    String prompt,
    int maxTokens,
    Map<String, dynamic> wire,
  ) {
    Pointer<Void> session = nullptr;
    Pointer<Void> config = nullptr;
    Pointer<Void> optionalArgs = nullptr;
    Pointer<Void> conversation = nullptr;
    Pointer<Void> response = nullptr;
    Pointer<Void> benchmark = nullptr;
    final message = (wire['message_json'] as String).toNativeUtf8();
    try {
      session = create('session_config_create');
      config = create('conversation_config_create');
      _required(session, 'session config');
      _required(config, 'conversation config');
      // The public NPU runtime intentionally leaves session sampling at the
      // compiled model/runtime defaults. Apply the same per-request output cap.
      optionalArgs = create('conversation_optional_args_create');
      _required(optionalArgs, 'optional args');
      setInt(
        'conversation_optional_args_set_max_output_tokens',
        optionalArgs,
        maxTokens,
      );
      setPointer('conversation_config_set_session_config', config, session);
      setJson(
        'conversation_config_set_system_message',
        config,
        wire['system_message_json'] as String?,
      );
      setJson(
        'conversation_config_set_messages',
        config,
        wire['messages_json'] as String?,
      );
      setJson(
        'conversation_config_set_extra_context',
        config,
        wire['extra_context_json'] as String,
      );
      library.lookupFunction<
        Void Function(Pointer<Void>, Bool),
        void Function(Pointer<Void>, bool)
      >('litert_lm_conversation_config_set_enable_constrained_decoding')(
        config,
        wire['enable_constrained_decoding'] as bool,
      );
      final before = monitor.snapshot();
      final setupWatch = Stopwatch()..start();
      conversation = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Void>)
          >('litert_lm_conversation_create')(handle, config);
      _required(conversation, 'conversation');
      setupWatch.stop();
      final afterSetup = monitor.snapshot();
      final watch = Stopwatch()..start();
      response = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Void>,
            ),
            Pointer<Void> Function(
              Pointer<Void>,
              Pointer<Utf8>,
              Pointer<Utf8>,
              Pointer<Void>,
            )
          >(
            'litert_lm_conversation_send_message',
          )(conversation, message, nullptr, optionalArgs);
      watch.stop();
      final after = monitor.snapshot();
      _required(response, 'response');
      final responseText = library
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('litert_lm_json_response_get_string')(response);
      _required(responseText.cast<Void>(), 'response text');
      final text = responseText.toDartString();
      if (text.length > 65536) {
        throw StateError('Native reference exceeded output bound');
      }
      final json = jsonDecode(text) as Map;
      final content = json['content'];
      final visible = content is String
          ? content
          : (content as List)
                .whereType<Map>()
                .where((part) => part['type'] == 'text')
                .map((part) => part['text'])
                .join();
      benchmark = createFrom('conversation_get_benchmark_info', conversation);
      _required(benchmark, 'benchmark info');
      final turns = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('litert_lm_benchmark_info_get_num_decode_turns')(benchmark);
      if (turns != 1) {
        throw StateError('Expected one native reference decode turn');
      }
      final tokens = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32),
            int Function(Pointer<Void>, int)
          >('litert_lm_benchmark_info_get_decode_token_count_at')(benchmark, 0);
      final tps = library
          .lookupFunction<
            Double Function(Pointer<Void>, Int32),
            double Function(Pointer<Void>, int)
          >(
            'litert_lm_benchmark_info_get_decode_tokens_per_sec_at',
          )(benchmark, 0);
      final wall = watch.elapsedMicroseconds / 1000;
      return {
        'prompt': prompt,
        'content': visible,
        'thinking': '',
        'native_response': json,
        'native_request': wire,
        'native_conversation_create_ms': setupWatch.elapsedMicroseconds / 1000,
        'npu_after_conversation_create': afterSetup,
        'max_tokens': maxTokens,
        'execution_path': 'native_c_api',
        'npu_execution': npuGenerationEvidence(before, after),
        'metrics': {
          'wall_ms': wall,
          'ttfa_ms': null,
          'native_ttft_ms':
              metric('benchmark_info_get_time_to_first_token', benchmark) *
              1000,
          'native_decode_tokens': tokens,
          'native_decode_tps': tps.isFinite && tps > 0 ? tps : null,
          'native_decode_ms': tps.isFinite && tps > 0
              ? tokens * 1000 / tps
              : null,
          'estimated_wall_tps': wall > 0 ? tokens * 1000 / wall : null,
          'token_count_source': 'native C API decode counter',
          'native_timing_source': 'native C API per-conversation benchmark',
        },
      };
    } finally {
      if (benchmark != nullptr) drop('benchmark_info_delete', benchmark);
      if (response != nullptr) drop('json_response_delete', response);
      if (conversation != nullptr) drop('conversation_delete', conversation);
      if (config != nullptr) drop('conversation_config_delete', config);
      if (session != nullptr) drop('session_config_delete', session);
      if (optionalArgs != nullptr) {
        drop('conversation_optional_args_delete', optionalArgs);
      }
      calloc.free(message);
    }
  }
}
