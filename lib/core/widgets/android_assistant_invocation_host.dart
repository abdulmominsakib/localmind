import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voice_mode/providers/voice_mode_provider.dart';
import '../../features/voice_mode/views/voice_mode_overlay.dart';
import '../services/android_assistant_service.dart';

class AndroidAssistantInvocationHost extends ConsumerStatefulWidget {
  const AndroidAssistantInvocationHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AndroidAssistantInvocationHost> createState() =>
      _AndroidAssistantInvocationHostState();
}

class _AndroidAssistantInvocationHostState
    extends ConsumerState<AndroidAssistantInvocationHost> {
  StreamSubscription<void>? _subscription;
  bool _isShowingVoiceMode = false;

  @override
  void initState() {
    super.initState();
    final service = ref.read(androidAssistantServiceProvider);
    if (!service.isSupportedPlatform) return;

    _subscription = service.invocations.listen((_) {
      unawaited(_showVoiceMode());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(service.initialize());
    });
  }

  Future<void> _showVoiceMode() async {
    if (!mounted || _isShowingVoiceMode) return;
    if (ref.read(voiceModeProvider).isActive) return;

    _isShowingVoiceMode = true;
    try {
      await VoiceModeOverlay.show(context);
    } finally {
      _isShowingVoiceMode = false;
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
