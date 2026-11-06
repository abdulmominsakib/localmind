import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/inference/local_inference.dart';
import '../../../core/providers/storage_providers.dart';
import '../../../core/utils/async_operation_queue.dart';
import '../data/local_api_background.dart';
import '../data/local_api_configuration.dart';
import '../data/local_api_server.dart';

enum LocalApiPhase { stopped, starting, running, stopping, rotating }

enum LocalApiFailure {
  modelRequired,
  invalidPort,
  unavailable,
  portUnavailable,
  key,
}

class LocalApiState {
  const LocalApiState({
    required this.config,
    this.phase = LocalApiPhase.stopped,
    this.failure,
    this.key,
    this.lanUrls = const [],
  });

  final LocalApiConfiguration config;
  final LocalApiPhase phase;
  final LocalApiFailure? failure;
  final String? key;
  final List<String> lanUrls;

  bool get running =>
      phase == LocalApiPhase.running || phase == LocalApiPhase.rotating;
  bool get busy =>
      phase != LocalApiPhase.stopped && phase != LocalApiPhase.running;
  String get url => 'http://127.0.0.1:${config.port}/v1';
}

final localApiConfigurationProvider = Provider<LocalApiConfigurationRepository>(
  (ref) =>
      LocalApiConfigurationRepository(ref.watch(sharedPreferencesProvider)),
);
final localApiBackgroundProvider = Provider<LocalApiBackground>(
  (ref) => LocalApiBackground(),
);
final localApiProvider = NotifierProvider<LocalApiNotifier, LocalApiState>(
  LocalApiNotifier.new,
);

class LocalApiNotifier extends Notifier<LocalApiState> {
  final _operations = AsyncOperationQueue();
  LocalApiServer? _server;
  Timer? _networkTimer;

  @override
  LocalApiState build() {
    final repo = ref.read(localApiConfigurationProvider);
    final background = ref.read(localApiBackgroundProvider);
    background.listen(stop);
    ref.onDispose(() {
      background.dispose();
      _networkTimer?.cancel();
      final server = _server;
      _server = null;
      if (server != null) {
        unawaited(_shutdown(server, background));
      }
    });
    return LocalApiState(config: repo.read());
  }

  Future<void> start({
    required String port,
    required bool lan,
    required String notification,
    required String stopLabel,
  }) => _operations.run(() async {
    if (!ref.mounted || state.running) return;
    final value = int.tryParse(port.trim());
    if (value == null || value < 1024 || value > 65535) {
      state = LocalApiState(
        config: state.config,
        key: state.key,
        failure: LocalApiFailure.invalidPort,
      );
      return;
    }
    final inference = ref.read(localInferenceProvider);
    if (inference == null || inference.model == null) {
      state = LocalApiState(
        config: state.config,
        key: state.key,
        failure: LocalApiFailure.modelRequired,
      );
      return;
    }
    final coordinator = ref.read(inferenceCoordinatorProvider);
    final repo = ref.read(localApiConfigurationProvider);
    final background = ref.read(localApiBackgroundProvider);
    final config = LocalApiConfiguration(port: value, lan: lan);
    var key = state.key;
    state = LocalApiState(
      config: config,
      key: key,
      phase: LocalApiPhase.starting,
    );
    LocalApiServer? server;
    var failure = LocalApiFailure.key;
    var requestedBackground = false;
    try {
      key ??= await repo.key();
      if (!ref.mounted) return;
      failure = LocalApiFailure.unavailable;
      requestedBackground = true;
      await background
          .start(text: notification, stop: stopLabel)
          .timeout(const Duration(seconds: 8));
      if (!ref.mounted) {
        await background.stop();
        return;
      }
      failure = LocalApiFailure.portUnavailable;
      server = LocalApiServer(
        inference: inference,
        coordinator: coordinator,
        apiKey: key,
      );
      await server.start(port: config.port, lan: config.lan);
      failure = LocalApiFailure.unavailable;
      await repo.save(config);
      if (!ref.mounted) {
        await _shutdown(server, background);
        return;
      }
      _server = server;
      state = LocalApiState(
        config: config,
        key: key,
        phase: LocalApiPhase.running,
      );
      if (config.lan) {
        unawaited(_updateAddresses(server, config));
        _networkTimer = Timer.periodic(const Duration(seconds: 3), (_) {
          unawaited(_updateAddresses(server!, config));
        });
      }
    } catch (_) {
      await _shutdown(server, requestedBackground ? background : null);
      if (ref.mounted) {
        state = LocalApiState(config: config, key: key, failure: failure);
      }
    }
  });

  Future<void> stop() => _operations.run(() async {
    final server = _server;
    if (!ref.mounted || server == null) return;
    _server = null;
    _networkTimer?.cancel();
    _networkTimer = null;
    final config = state.config;
    final key = state.key;
    final background = ref.read(localApiBackgroundProvider);
    state = LocalApiState(
      config: config,
      key: key,
      phase: LocalApiPhase.stopping,
    );
    await _shutdown(server, background);
    if (ref.mounted) state = LocalApiState(config: config, key: key);
  });

  Future<void> rotateKey() => _operations.run(() async {
    if (!ref.mounted) return;
    final previous = state;
    state = LocalApiState(
      config: previous.config,
      key: previous.key,
      phase: LocalApiPhase.rotating,
      lanUrls: previous.lanUrls,
    );
    try {
      final key = await ref.read(localApiConfigurationProvider).rotateKey();
      if (!ref.mounted) return;
      _server?.rotateKey(key);
      state = LocalApiState(
        config: previous.config,
        key: key,
        phase: previous.phase,
        lanUrls: previous.lanUrls,
      );
    } catch (_) {
      if (ref.mounted) {
        state = LocalApiState(
          config: previous.config,
          key: previous.key,
          phase: previous.phase,
          lanUrls: previous.lanUrls,
          failure: LocalApiFailure.key,
        );
      }
    }
  });

  Future<void> _updateAddresses(
    LocalApiServer server,
    LocalApiConfiguration config,
  ) async {
    List<String> urls;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      urls = {
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (LocalApiServer.isLanAddress(address))
              'http://${address.address}:${config.port}/v1',
      }.toList()..sort();
    } on SocketException {
      urls = const [];
    }
    if (!ref.mounted || !identical(server, _server) || state.busy) return;
    state = LocalApiState(
      config: config,
      key: state.key,
      phase: state.phase,
      lanUrls: urls,
      failure: state.failure,
    );
  }

  static Future<void> _shutdown(
    LocalApiServer? server,
    LocalApiBackground? background,
  ) async {
    try {
      await server?.stop();
    } catch (_) {
      // The listener may have been closed by Android.
    }
    try {
      await background?.stop();
    } catch (_) {
      // The native service may already have stopped.
    }
  }
}
