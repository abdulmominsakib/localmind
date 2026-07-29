import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sound + haptic feedback for the voice-to-voice overlay lifecycle.
///
/// Holds four preloaded [AudioPlayer]s (one per cue) so playback is
/// zero-latency at the moment of a phase transition. Each public method
/// plays its cue and fires the matching haptic in one call.
///
/// All playback errors are swallowed — feedback is best-effort and must
/// never break the voice pipeline.
class VoiceFeedbackService {
  final AudioPlayer _connectedPlayer = AudioPlayer();
  final AudioPlayer _disconnectedPlayer = AudioPlayer();
  final AudioPlayer _listeningPlayer = AudioPlayer();
  final AudioPlayer _generatingPlayer = AudioPlayer();

  bool _disposed = false;

  /// Preload every cue into memory so the first call has no asset-load
  /// latency. Safe to call multiple times — audioplayers reuses the
  /// existing source on subsequent `setSourceAsset` calls.
  Future<void> preload() async {
    await Future.wait([
      _load(_connectedPlayer, 'sounds/connected.mp3'),
      _load(_disconnectedPlayer, 'sounds/disconnected.mp3'),
      _load(_listeningPlayer, 'sounds/start_listening.mp3'),
      _load(_generatingPlayer, 'sounds/generating.mp3'),
    ]);
  }

  Future<void> _load(AudioPlayer player, String assetPath) async {
    if (_disposed) return;
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource(assetPath));
    } catch (_) {
      // Swallow — see class doc.
    }
  }

  Future<void> _play(AudioPlayer player) async {
    if (_disposed) return;
    try {
      await player.seek(Duration.zero);
      await player.resume();
    } catch (_) {
      // Swallow — see class doc.
    }
  }

  /// Session opened, mic is live. Confident, affirming.
  Future<void> playConnected() async {
    await _play(_connectedPlayer);
    await _safeHaptic(HapticFeedback.mediumImpact);
  }

  /// Session closed gracefully. Soft, not alarming.
  Future<void> playDisconnected() async {
    await _play(_disconnectedPlayer);
    await _safeHaptic(HapticFeedback.lightImpact);
  }

  /// Mic activated, awaiting user speech. Crisp micro-click.
  Future<void> playListening() async {
    await _play(_listeningPlayer);
    await _safeHaptic(HapticFeedback.selectionClick);
  }

  /// LLM is streaming. Single tap on first chunk only — repeated
  /// haptics during streaming feel glitchy.
  Future<void> playGenerating() async {
    await _play(_generatingPlayer);
    await _safeHaptic(HapticFeedback.lightImpact);
  }

  Future<void> _safeHaptic(Future<void> Function() haptic) async {
    if (_disposed) return;
    try {
      await haptic();
    } catch (_) {
      // Swallow — haptics unsupported on some devices / emulators.
    }
  }

  /// Release every player. Called by [voiceFeedbackProvider]'s
  /// `ref.onDispose`.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      _connectedPlayer.dispose(),
      _disconnectedPlayer.dispose(),
      _listeningPlayer.dispose(),
      _generatingPlayer.dispose(),
    ]);
  }
}

/// Singleton feedback service. Not autoDispose — preloaded sounds stay
/// warm for the whole app lifetime so the first phase transition has no
/// asset-load delay.
final voiceFeedbackProvider = Provider<VoiceFeedbackService>((ref) {
  final service = VoiceFeedbackService();
  // Fire-and-forget: callers don't block on preload.
  // ignore: discarded_futures
  service.preload();
  ref.onDispose(service.dispose);
  return service;
});