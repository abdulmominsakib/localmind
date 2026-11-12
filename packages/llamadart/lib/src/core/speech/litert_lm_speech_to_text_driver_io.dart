import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../backends/litert_lm/litert_lm_runtime.dart';
import '../../backends/litert_lm/litert_lm_runtime_client_contract.dart';
import '../exceptions.dart';
import '../models/model_source.dart';
import 'litert_lm_speech_to_text_driver.dart';

const String _incompleteBpeSequenceDetails =
    'The set of token IDs passed to the tokenizer is part of a BPE sequence '
    'and needs more tokens to be decoded.';

/// Processes one ASR window while tolerating an incomplete trailing BPE token.
///
/// Independent-window models can end a window in the middle of a UTF-8 BPE
/// sequence. LiteRT-LM reports that recoverable suffix as data loss even though
/// the overlapping next window remains usable. Unrelated failures propagate.
LiteRtLmAsrProcessResult? processLiteRtLmSpeechWindow(
  LiteRtLmAsrRuntimeSession session,
) {
  try {
    return session.processNext();
  } on LlamaSpeechException catch (error) {
    if (error.message ==
            'LiteRT-LM ASR inference failed with native status 9.' &&
        error.details == _incompleteBpeSequenceDetails) {
      return null;
    }
    rethrow;
  }
}

/// Creates the native LiteRT-LM speech driver.
LiteRtLmSpeechToTextDriver createLiteRtLmSpeechToTextDriver() =>
    const _IoLiteRtLmSpeechToTextDriver();

/// Prepares an explicitly selected native ABI for the speech probe and worker.
/// [runtimeClientFactory] must be isolate-sendable and construct native owners
/// inside the receiving isolate; it must not capture a loaded native client.
LiteRtLmSpeechToTextDriver createLiteRtLmSpeechToTextDriverWithRuntime(
  LiteRtLmRuntimeClientContract Function(String? libraryPath)
  runtimeClientFactory,
) => _IoLiteRtLmSpeechToTextDriver(runtimeClientFactory);

LiteRtLmRuntimeClientContract _createSelectedSpeechClient(
  String? libraryPath,
) => createLiteRtLmSelectedServiceClient(libraryPath: libraryPath, eager: true);

class _IoLiteRtLmSpeechToTextDriver implements LiteRtLmSpeechToTextDriver {
  const _IoLiteRtLmSpeechToTextDriver([
    this._runtimeClientFactory = _createSelectedSpeechClient,
  ]);

  final LiteRtLmRuntimeClientContract Function(String?) _runtimeClientFactory;

  @override
  Future<LiteRtLmSpeechToTextSupport> probeSupport({
    String? libraryPath,
  }) async {
    if (libraryPath == null || libraryPath.trim().isEmpty) {
      final unsupported = liteRtLmUnsupportedAbiException(liteRtLmGateAbi());
      if (unsupported != null) {
        return LiteRtLmSpeechToTextSupport(
          isSupported: false,
          unsupportedReason: unsupported.message,
        );
      }
    }
    LiteRtLmRuntimeClientContract? runtime;
    try {
      runtime = _runtimeClientFactory(libraryPath);
      if (runtime.supportsAsrBridge) {
        return const LiteRtLmSpeechToTextSupport(isSupported: true);
      }
      return const LiteRtLmSpeechToTextSupport(
        isSupported: false,
        unsupportedReason:
            'The packaged LiteRT-LM runtime does not expose the v0.16+ ASR ABI.',
      );
    } catch (error) {
      return LiteRtLmSpeechToTextSupport(
        isSupported: false,
        unsupportedReason: 'The LiteRT-LM ASR capability probe failed: $error',
      );
    } finally {
      runtime?.dispose();
    }
  }

  @override
  Future<LiteRtLmSpeechToTextWorker> start(
    LiteRtLmAsrRuntimeConfig config, {
    String? libraryPath,
  }) => _LiteRtLmSpeechWorkerClient.create(
    config,
    libraryPath: libraryPath,
    runtimeClientFactory: _runtimeClientFactory,
  );
}

class _LiteRtLmSpeechWorkerClient implements LiteRtLmSpeechToTextWorker {
  final Isolate _isolate;
  final ReceivePort _messages;
  final ReceivePort _errors;
  final ReceivePort _exits;
  final StreamController<LiteRtLmSpeechToTextUpdate> _updates =
      StreamController<LiteRtLmSpeechToTextUpdate>();
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Completer<SendPort> _commandPort = Completer<SendPort>();

  int _nextRequestId = 0;
  bool _disposing = false;
  bool _disposed = false;

  _LiteRtLmSpeechWorkerClient._(
    this._isolate,
    this._messages,
    this._errors,
    this._exits,
  ) {
    _messages.listen(_handleMessage);
    _errors.listen((dynamic message) {
      final summary = message is List && message.isNotEmpty
          ? message.first
          : message;
      _failPending(
        LlamaSpeechException('LiteRT-LM ASR worker failed.', summary),
      );
    });
    _exits.listen((dynamic _) {
      if (!_disposing && !_disposed) {
        _failPending(
          LlamaSpeechException('LiteRT-LM ASR worker exited unexpectedly.'),
        );
      }
    });
  }

  static Future<_LiteRtLmSpeechWorkerClient> create(
    LiteRtLmAsrRuntimeConfig config, {
    String? libraryPath,
    required LiteRtLmRuntimeClientContract Function(String?)
    runtimeClientFactory,
  }) async {
    final messages = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final isolate = await Isolate.spawn<SendPort>(
      _liteRtLmSpeechWorkerMain,
      messages.sendPort,
      errorsAreFatal: true,
      onError: errors.sendPort,
      onExit: exits.sendPort,
      debugName: 'llamadart-litert-asr',
    );
    final client = _LiteRtLmSpeechWorkerClient._(
      isolate,
      messages,
      errors,
      exits,
    );
    try {
      await client._request('initialize', <String, Object>{
        'modelPath': config.modelPath,
        'tokenizerPath': config.tokenizerPath,
        'modelPreset': config.modelPreset.index,
        'backend': config.backend.index,
        'numberOfThreads': config.numberOfThreads,
        'maxBufferedAudioMilliseconds': config.maxBufferedAudio.inMilliseconds,
        'overlapRatio': config.overlapRatio,
        'libraryPath': ?libraryPath,
        'runtimeClientFactory': runtimeClientFactory,
      });
      return client;
    } catch (_) {
      await client.dispose();
      rethrow;
    }
  }

  @override
  Stream<LiteRtLmSpeechToTextUpdate> get updates => _updates.stream;

  @override
  Future<int> pushAudio(Float32List samples) async {
    final bytes = Uint8List.view(
      samples.buffer,
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
    final result = await _request(
      'push',
      TransferableTypedData.fromList(<Uint8List>[bytes]),
    );
    return result as int;
  }

  @override
  Future<String> finish() async => (await _request('finish', null)) as String;

  @override
  Future<void> cancel() async {
    if (_disposed) {
      return;
    }
    try {
      await _request('cancel', null);
    } catch (_) {
      // Cooperative cancellation remains best effort during worker teardown.
    }
  }

  Future<Object?> _request(String command, Object? payload) async {
    if (_disposed) {
      throw LlamaStateException('LiteRT-LM ASR worker is disposed.');
    }
    final port = await _commandPort.future;
    final id = ++_nextRequestId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send(<String, Object?>{
      'id': id,
      'command': command,
      'payload': payload,
    });
    return completer.future;
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) {
      return;
    }
    final kind = message['kind'];
    if (kind == 'ready') {
      final port = message['port'];
      if (port is SendPort && !_commandPort.isCompleted) {
        _commandPort.complete(port);
      }
      return;
    }
    if (kind == 'update') {
      if (!_updates.isClosed) {
        _updates.add(
          LiteRtLmSpeechToTextUpdate(
            confirmedText: message['confirmedText'] as String? ?? '',
            pendingText: message['pendingText'] as String? ?? '',
            isFinal: message['isFinal'] as bool? ?? false,
            acceptedSamples: message['acceptedSamples'] as int? ?? 0,
          ),
        );
      }
      return;
    }
    if (kind != 'response') {
      return;
    }
    final id = message['id'];
    if (id is! int) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null) {
      return;
    }
    final error = message['error'];
    if (error != null) {
      completer.completeError(
        LlamaSpeechException('LiteRT-LM speech recognition failed.', error),
      );
    } else {
      completer.complete(message['result']);
    }
  }

  void _failPending(Object error) {
    if (!_commandPort.isCompleted) {
      _commandPort.completeError(error);
    }
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
    if (!_updates.isClosed) {
      _updates.addError(error);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposing || _disposed) {
      return;
    }
    _disposing = true;
    try {
      await _request('dispose', null);
    } catch (_) {
      // The isolate may already have exited after an error.
    }
    _disposed = true;
    _isolate.kill(priority: Isolate.immediate);
    _messages.close();
    _errors.close();
    _exits.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          LlamaStateException('LiteRT-LM ASR worker is disposed.'),
        );
      }
    }
    _pending.clear();
    if (!_updates.isClosed) {
      // Stream delivery must not hold worker cleanup hostage to an absent
      // or paused listener, especially when initialization failed.
      unawaited(_updates.close());
    }
  }
}

void _liteRtLmSpeechWorkerMain(SendPort mainPort) {
  final commands = ReceivePort();
  mainPort.send(<String, Object>{'kind': 'ready', 'port': commands.sendPort});
  LiteRtLmRuntimeClientContract? runtime;
  LiteRtLmAsrRuntimeSession? session;
  final confirmed = <String>[];
  var acceptedSamples = 0;

  void sendUpdate(LiteRtLmAsrProcessResult result) {
    final value = result.confirmedText.trim();
    if (value.isNotEmpty) {
      confirmed.add(value);
    }
    mainPort.send(<String, Object>{
      'kind': 'update',
      'confirmedText': confirmed.join(' ').trim(),
      'pendingText': result.unconfirmedText,
      'isFinal': result.isFinal,
      'acceptedSamples': acceptedSamples,
    });
  }

  LiteRtLmAsrProcessState processAvailable() {
    final activeSession = session;
    if (activeSession == null) {
      throw StateError('LiteRT-LM ASR session is not initialized.');
    }
    for (var attempt = 0; attempt < 10000; attempt++) {
      final result = processLiteRtLmSpeechWindow(activeSession);
      if (result == null) {
        return LiteRtLmAsrProcessState.needsMoreAudio;
      }
      if (result.state != LiteRtLmAsrProcessState.update) {
        return result.state;
      }
      sendUpdate(result);
      if (result.isFinal) {
        return LiteRtLmAsrProcessState.endOfStream;
      }
    }
    throw StateError('LiteRT-LM ASR processing did not quiesce.');
  }

  commands.listen((dynamic raw) {
    if (raw is! Map) {
      return;
    }
    final id = raw['id'];
    final command = raw['command'];
    if (id is! int || command is! String) {
      return;
    }
    try {
      Object? result;
      switch (command) {
        case 'initialize':
          final payload = raw['payload'] as Map;
          final factory =
              payload['runtimeClientFactory']
                  as LiteRtLmRuntimeClientContract Function(String?);
          runtime = factory(payload['libraryPath'] as String?);
          if (!runtime!.supportsAsrBridge) {
            throw StateError(
              'The installed LiteRT-LM runtime does not expose the v0.16+ ASR ABI.',
            );
          }
          session = runtime!.createAsrSession(
            LiteRtLmAsrRuntimeConfig.source(
              model: ModelSource.path(payload['modelPath'] as String),
              tokenizer: ModelSource.path(payload['tokenizerPath'] as String),
              modelPreset:
                  LiteRtLmAsrModelPreset.values[payload['modelPreset'] as int],
              backend: LiteRtLmAsrBackend.values[payload['backend'] as int],
              numberOfThreads: payload['numberOfThreads'] as int,
              maxBufferedAudio: Duration(
                milliseconds: payload['maxBufferedAudioMilliseconds'] as int,
              ),
              overlapRatio: payload['overlapRatio'] as double,
            ),
          );
        case 'push':
          final transfer = raw['payload'] as TransferableTypedData;
          final bytes = transfer.materialize().asUint8List();
          if (bytes.lengthInBytes % Float32List.bytesPerElement != 0) {
            throw StateError('Float PCM payload is not sample-aligned.');
          }
          final samples = Float32List.view(
            bytes.buffer,
            bytes.offsetInBytes,
            bytes.lengthInBytes ~/ Float32List.bytesPerElement,
          );
          final activeSession = session;
          if (activeSession == null) {
            throw StateError('LiteRT-LM ASR session is not initialized.');
          }
          var offset = 0;
          while (offset < samples.length) {
            final push = activeSession.pushAudio(
              Float32List.sublistView(samples, offset),
            );
            if (push.acceptedSamples == 0 && !push.wouldBlock) {
              throw StateError(
                'LiteRT-LM ASR accepted no audio without backpressure.',
              );
            }
            offset += push.acceptedSamples;
            acceptedSamples += push.acceptedSamples;
            final state = processAvailable();
            if (push.wouldBlock &&
                push.acceptedSamples == 0 &&
                state == LiteRtLmAsrProcessState.needsMoreAudio) {
              throw StateError(
                'LiteRT-LM ASR reported backpressure without processing a window.',
              );
            }
            if (state == LiteRtLmAsrProcessState.endOfStream) {
              break;
            }
          }
          result = offset;
        case 'finish':
          final activeSession = session;
          if (activeSession == null) {
            throw StateError('LiteRT-LM ASR session is not initialized.');
          }
          activeSession.finishAudio();
          var finalized = false;
          for (var attempt = 0; attempt < 10000; attempt++) {
            final update = processLiteRtLmSpeechWindow(activeSession);
            if (update == null) {
              continue;
            }
            if (update.state == LiteRtLmAsrProcessState.endOfStream) {
              finalized = true;
              break;
            }
            if (update.state == LiteRtLmAsrProcessState.needsMoreAudio) {
              throw StateError(
                'LiteRT-LM ASR requested audio after finalization.',
              );
            }
            sendUpdate(update);
            if (update.isFinal) {
              finalized = true;
              break;
            }
          }
          if (!finalized) {
            throw StateError('LiteRT-LM ASR did not produce a final result.');
          }
          result = confirmed.join(' ').trim();
        case 'cancel':
          session?.cancel();
        case 'dispose':
          session?.dispose();
          session = null;
          runtime?.dispose();
          runtime = null;
        default:
          throw StateError('Unknown LiteRT-LM ASR command: $command');
      }
      mainPort.send(<String, Object?>{
        'kind': 'response',
        'id': id,
        'result': result,
      });
      if (command == 'dispose') {
        commands.close();
      }
    } catch (error) {
      mainPort.send(<String, Object?>{
        'kind': 'response',
        'id': id,
        'error': error.toString(),
      });
    }
  });
}
