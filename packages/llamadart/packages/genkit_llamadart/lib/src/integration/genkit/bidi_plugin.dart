// This isolated entrypoint intentionally consumes Genkit's experimental API.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:collection';

import 'package:genkit/experimental.dart';
import 'package:genkit/plugin.dart';
import 'package:llamadart/llamadart.dart' as llama;

import '../../api/generation_config.dart';
import '../../api/model_definition.dart';
import '../../core/runtime/engine_registry.dart';
import '../../core/runtime/llama_engine_runtime.dart';
import '../../core/runtime/llama_runtime.dart';
import 'actions/model_action.dart';

/// Experimental, bounded request/response text sessions for `generateBidi`.
///
/// Registers `llamadart-bidi/<name>` as bidi models, separately from ordinary
/// `llamaDart` actions. Each session owns its history and a fresh native runtime;
/// shared filenames do not imply shared model allocations. Only user text turns
/// and an optional initial system message/config are accepted. Tools, media,
/// arbitrary history injection, structured output and continuous audio reject.
/// Outputs are one complete chunk per turn, with `custom.turn`/`finishReason`.
///
/// Callers should await that chunk before sending another turn. Pending input,
/// total turns, history/output characters and session lifetime are bounded.
/// Genkit's transport has no awaitable output backpressure, so this plugin bounds
/// total emitted output instead. Cancelling the output subscription alone does
/// not stop Genkit's transport: close the session or use its cancellation token.
/// Abandoned sessions expire; [dispose] cancels and drains all remaining work.
class LlamaDartBidiPlugin extends GenkitPlugin {
  /// Creates a lazy native GGUF text-session plugin.
  ///
  /// All limits must be positive. Sessions accept at most [maxQueuedTurns]
  /// waiting turns and [maxTurns] total turns. [maxHistoryCharacters] includes
  /// system text, retained visible/reasoning output and pending input.
  /// [maxOutputCharacters] bounds a completed turn before publication;
  /// [maxOutputTokens] caps the generation config (default 256 tokens).
  ///
  /// [runtimeFactory] must create independently owned native contexts with
  /// fresh capability probes; reused runtime objects reject. Default engines
  /// receive [observers]. Factories own their own observer installation.
  LlamaDartBidiPlugin({
    required List<LlamaModelDefinition> models,
    this.maxSessions = 2,
    this.maxQueuedTurns = 2,
    this.maxTurns = 32,
    this.maxHistoryCharacters = 32768,
    this.maxOutputCharacters = 8192,
    this.maxOutputTokens = 512,
    this.idleTimeout = const Duration(minutes: 1),
    this.maxSessionDuration = const Duration(minutes: 10),
    LlamaDartRuntimeFactory? runtimeFactory,
    Iterable<llama.LlamaEngineObserver> observers = const [],
  }) : _models = List<LlamaModelDefinition>.unmodifiable(models) {
    if ([
          maxSessions,
          maxQueuedTurns,
          maxTurns,
          maxHistoryCharacters,
          maxOutputCharacters,
          maxOutputTokens,
        ].any((n) => n < 1) ||
        idleTimeout <= Duration.zero ||
        maxSessionDuration <= Duration.zero) {
      throw ArgumentError('Text session limits must be positive.');
    }
    if (_models.map((m) => m.name).toSet().length != _models.length) {
      throw ArgumentError('Text session model names must be unique.');
    }
    final snapshot = List<llama.LlamaEngineObserver>.unmodifiable(observers);
    _factory = runtimeFactory ?? () => LlamaEngineRuntime(observers: snapshot);
  }

  /// Maximum unsettled sessions across all registered models.
  final int maxSessions;

  /// Maximum waiting turns per session, excluding its active generation.
  final int maxQueuedTurns;

  /// Maximum accepted user turns before a session closes normally.
  final int maxTurns;

  /// Maximum retained history and pending input characters per session.
  final int maxHistoryCharacters;

  /// Maximum output characters in one complete visible/reasoning response.
  final int maxOutputCharacters;

  /// Upper bound for each turn's requested `maxTokens`.
  final int maxOutputTokens;

  /// Idle time before an otherwise unused session is cancelled and closed.
  final Duration idleTimeout;

  /// Maximum session lifetime, including time spent generating.
  final Duration maxSessionDuration;

  final List<LlamaModelDefinition> _models;
  late final LlamaDartRuntimeFactory _factory;
  final Expando<bool> _seen = Expando<bool>();
  final Set<_TextSession> _sessions = {};
  List<Action>? _actions;
  Future<void>? _closing;

  @override
  String get name => 'llamadart-bidi';

  @override
  Future<List<Action>> init() async => _actions ??= [
    for (final definition in _models)
      BidiModel<LlamaDartGenerationConfig>(
        name: '$name/${definition.name}',
        fn: (input, context) async {
          if (_closing != null || _sessions.length >= maxSessions) {
            await input.listen((_) {}).cancel();
            throw _sessionError(
              'The text session plugin is closed or full.',
              StatusCode.resourceExhausted,
            );
          }
          if (const bool.fromEnvironment('dart.library.js_interop') ||
              llama.ModelFormat.fromPath(definition.modelPath) !=
                  llama.ModelFormat.gguf) {
            await input.listen((_) {}).cancel();
            throw _sessionError(
              'Text sessions require native llama.cpp GGUF models.',
              StatusCode.unimplemented,
            );
          }
          final session = _TextSession(this, definition);
          _sessions.add(session);
          try {
            return await session.run(input, context);
          } finally {
            if (!session.cleanupFailed) _sessions.remove(session);
          }
        },
      ),
  ];

  @override
  Future<List<ActionMetadata>> list() => init();

  /// Cancels active/idle sessions and waits for native work and cleanup.
  ///
  /// Terminal and idempotent. It does not dispose a caller-owned Genkit instance.
  Future<void> dispose() => _closing ??= () async {
    await _sessions.toList().map((session) => session.stop()).wait;
  }();

  LlamaDartRuntime _allocate() {
    final runtime = _factory();
    if (_seen[runtime] == true) {
      throw _sessionError(
        'The text runtime factory must return a fresh context.',
        StatusCode.failedPrecondition,
      );
    }
    _seen[runtime] = true;
    return runtime;
  }
}

typedef _BidiContext =
    ActionFnArg<ModelResponseChunk, ModelRequest, ModelRequest>;

final class _TextSession {
  _TextSession(this.plugin, LlamaModelDefinition definition)
    : registry = EngineRegistry(
        models: [definition],
        runtimeFactory: plugin._allocate,
      ),
      definition = definition {
    settled.future.ignore();
  }

  final LlamaDartBidiPlugin plugin;
  final LlamaModelDefinition definition;
  final EngineRegistry registry;
  final CancellationController cancellation = CancellationController();
  final Queue<String> pending = Queue<String>();
  final List<Message> history = [];
  final Completer<void> done = Completer<void>();
  final Completer<void> settled = Completer<void>();
  StreamSubscription<ModelRequest>? subscription;
  Timer? idle;
  Timer? lifetime;
  late _BidiContext context;
  late Model<LlamaDartGenerationConfig> model;
  late Map<String, dynamic> config;
  bool processing = false;
  bool stopped = false;
  bool inputClosed = false;
  int accepted = 0;
  int completed = 0;
  int characters = 0;
  Object? error;
  bool cleanupFailed = false;

  Future<ModelResponse> run(
    Stream<ModelRequest> input,
    _BidiContext ctx,
  ) async {
    context = ctx;
    void Function()? unregister;
    try {
      ctx.cancel?.throwIfCancelled();
      final init = ctx.init;
      if (init != null) {
        if (init.messages.length > 1) throw _invalidTurn();
        if (init.tools?.isNotEmpty == true ||
            init.docs?.isNotEmpty == true ||
            init.output != null ||
            init.toJson().containsKey('toolChoice')) {
          throw _sessionError(
            'Text sessions do not support tools, documents or output schemas.',
            StatusCode.unimplemented,
          );
        }
        for (final message in init.messages) {
          if (message.role != Role.system) throw _invalidTurn();
          final text = _text(message);
          characters += text.length;
          history.add(
            Message(
              role: Role.system,
              content: [TextPart(text: text)],
            ),
          );
        }
      }
      if (characters > plugin.maxHistoryCharacters) throw _historyLimit();
      final parsed = LlamaDartGenerationConfig.fromJson(init?.config);
      final tokens =
          parsed.maxTokens ??
          (plugin.maxOutputTokens < 256 ? plugin.maxOutputTokens : 256);
      if (tokens < 1 || tokens > plugin.maxOutputTokens) {
        throw _sessionError(
          'The requested output token budget exceeds this text session limit.',
          StatusCode.invalidArgument,
        );
      }
      config = {...parsed.toJson(), 'maxTokens': tokens};
      model = buildModelAction(
        definition: definition,
        registry: registry,
        checkCapabilities: (capabilities) {
          if (capabilities?.isSupported != true ||
              capabilities?.runtime != llama.LlamaRuntime.llamaCpp ||
              capabilities?.supportsMultiTurnChat != true) {
            throw _sessionError(
              'Text sessions require confirmed native llama.cpp multi-turn support.',
              StatusCode.unimplemented,
            );
          }
        },
      );
      unregister = ctx.cancel?.onCancel(() => _fail(CancelledException()));
      lifetime = Timer(
        plugin.maxSessionDuration,
        () => _fail(
          _sessionError(
            'The text session lifetime expired.',
            StatusCode.deadlineExceeded,
          ),
        ),
      );
      subscription = input.listen(
        _accept,
        onError: (Object _, StackTrace _) => _fail(
          _sessionError(
            'The text session input failed.',
            StatusCode.invalidArgument,
          ),
        ),
        onDone: () {
          inputClosed = true;
          _finishIfDrained();
        },
      );
      _armIdle();
      await done.future;
      if (error != null) throw error!;
      return ModelResponse(finishReason: FinishReason.stop);
    } on FormatException {
      throw _sessionError(
        'Invalid text session generation configuration.',
        StatusCode.invalidArgument,
      );
    } finally {
      idle?.cancel();
      lifetime?.cancel();
      unregister?.call();
      subscription ??= input.listen((_) {});
      await subscription!.cancel();
      try {
        await registry.dispose();
      } catch (_) {
        cleanupFailed = true;
        final failure = _sessionError(
          'Native text-session cleanup failed. Check resources before opening replacement contexts.',
          StatusCode.internal,
        );
        settled.completeError(failure);
        throw failure;
      } finally {
        if (!settled.isCompleted) settled.complete();
      }
    }
  }

  void _accept(ModelRequest request) {
    if (stopped) return;
    try {
      if (request.toJson().keys.any((key) => key != 'messages') ||
          request.messages.length != 1 ||
          request.messages.single.role != Role.user) {
        throw _invalidTurn();
      }
      final text = _text(request.messages.single);
      if (text.isEmpty) throw _invalidTurn();
      if (accepted >= plugin.maxTurns ||
          pending.length >= plugin.maxQueuedTurns) {
        throw _sessionError(
          'The text session turn or pending-input limit was exceeded.',
          StatusCode.resourceExhausted,
        );
      }
      if (characters + text.length > plugin.maxHistoryCharacters) {
        throw _historyLimit();
      }
      characters += text.length;
      accepted++;
      pending.add(text);
      idle?.cancel();
      unawaited(_pump());
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _pump() async {
    if (processing || stopped) return;
    processing = true;
    try {
      while (pending.isNotEmpty && !stopped) {
        history.add(
          Message(
            role: Role.user,
            content: [TextPart(text: pending.removeFirst())],
          ),
        );
        final response = (await model.run(
          ModelRequest(messages: history, config: config),
          cancel: cancellation.token,
        )).result;
        if (stopped) break;
        final message = response.message;
        if (message == null ||
            message.content.any((part) => !part.isText && !part.isReasoning)) {
          throw _sessionError(
            'The runtime returned an unsupported text-session response.',
            StatusCode.dataLoss,
          );
        }
        final size = message.content.fold<int>(
          0,
          (sum, part) => sum + (part.text ?? part.reasoning ?? '').length,
        );
        if (size > plugin.maxOutputCharacters ||
            characters + size > plugin.maxHistoryCharacters) {
          throw _historyLimit();
        }
        characters += size;
        history.add(message);
        completed++;
        context.sendChunk(
          ModelResponseChunk(
            role: Role.model,
            content: message.content,
            custom: {
              'turn': completed,
              'finishReason': response.finishReason.value,
            },
            aggregated: false,
          ),
        );
        if (completed >= plugin.maxTurns) stopped = true;
      }
    } on _SessionFailure catch (failure) {
      _fail(failure);
    } on CancelledException {
      _fail(CancelledException());
    } catch (_) {
      _fail(
        _sessionError(
          'Local text generation failed or exceeded the session limits. Start a new session.',
          StatusCode.dataLoss,
        ),
      );
    } finally {
      processing = false;
      _finishIfDrained();
      _armIdle();
    }
  }

  void _finishIfDrained() {
    if (!processing &&
        (stopped || (inputClosed && pending.isEmpty)) &&
        !done.isCompleted) {
      done.complete();
    }
  }

  void _armIdle() {
    idle?.cancel();
    if (!stopped && !processing && pending.isEmpty) {
      idle = Timer(
        plugin.idleTimeout,
        () => _fail(
          _sessionError(
            'The text session expired while idle.',
            StatusCode.deadlineExceeded,
          ),
        ),
      );
    }
  }

  void _fail(Object failure) {
    if (stopped) return;
    error = failure;
    stopped = true;
    pending.clear();
    cancellation.cancel();
    _finishIfDrained();
  }

  Future<void> stop() {
    _fail(CancelledException());
    return settled.future;
  }
}

String _text(Message message) {
  if (message.content.isEmpty || message.content.any((part) => !part.isText)) {
    throw _invalidTurn();
  }
  return message.content.map((part) => part.text!).join();
}

GenkitException _invalidTurn() => _sessionError(
  'Send one nonempty user text message per turn. History, media, tools and per-turn configuration are unsupported.',
  StatusCode.invalidArgument,
);
GenkitException _historyLimit() => _sessionError(
  'The text session character budget was exceeded. Start a new session.',
  StatusCode.resourceExhausted,
);
GenkitException _sessionError(String message, StatusCode status) =>
    _SessionFailure(message, status);

final class _SessionFailure extends GenkitException {
  _SessionFailure(super.message, StatusCode status) : super(status: status);
}
