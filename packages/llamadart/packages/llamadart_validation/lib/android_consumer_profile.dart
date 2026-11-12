import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';

import 'src/android_qualification.dart';

/// Release smoke contract for the real Android consumer hook configuration.
class AndroidConsumerProfilePlan {
  /// Freezes one separately built full/compact consumer configuration.
  AndroidConsumerProfilePlan(this.profile) {
    if (!const ['full', 'compact'].contains(profile)) {
      throw const FormatException('Expected full or compact CPU profile');
    }
  }

  /// Hook CPU variant profile, independent of Flutter's build mode.
  final String profile;

  /// Same immutable small model as the maintained A35 diagnostic.
  final AndroidQualificationPlan fixture = const AndroidQualificationPlan(
    AndroidQualificationScenario.a35,
  );

  /// Exact consumer hook defines: default backend policy, no path override.
  Map<String, Object?> get hookDefines => {
    'llamadart_native_runtimes': 'llama_cpp',
    'llamadart_native_tag': 'v0.9.0',
    'llamadart_native_backends': {
      'platforms': {
        'android-arm64': {'cpu_profile': profile},
      },
    },
  };

  /// A public CPU request without any service, factory or library substitution.
  ModelParams get params => fixture.params('cpu');

  /// Two complete serialized engine lifetimes exercise reload after disposal.
  List<String> get caseIds => [
    'consumer.public.cpu.first',
    'consumer.public.cpu.reload',
  ];

  /// Prospective request only; no device or qualification result is inferred.
  Map<String, Object?> get wire => {
    'schema': 1,
    'scenario': 'consumer-cpu',
    'cpu_profile': profile,
    'flutter_build_mode': 'release',
    'instrumentation_plugin': {
      'package': 'integration_test',
      'sdk': 'flutter',
      'dependency': 'main',
      'keep_android_classes': true,
    },
    'hook_defines': hookDefines,
    'model': fixture.model,
    'prompt': fixture.prompts.single,
    'configuration': {
      'context': 1024,
      'batch': 512,
      'microbatch': 512,
      'threads': 4,
      'threads_batch': 4,
      'gpu_layers': 0,
      'max_tokens': 24,
      'temperature': 0,
      'seed': 1,
      'repeat_penalty': 1,
      'reuse_prompt_prefix': false,
    },
    'oracle': 'nonempty output containing Paris; exact repeat after reload',
    'cases': caseIds,
  };

  /// Binds the compiled profile to the admitted source and runtime inventory.
  String get hash => sha256.convert(utf8.encode(jsonEncode(wire))).toString();
}

/// Enforces the frozen semantic fixture rather than accepting any generated text.
bool androidConsumerOutputPasses(String output) =>
    RegExp(r'\bParis\b').hasMatch(output) && !output.contains('\uFFFD');
