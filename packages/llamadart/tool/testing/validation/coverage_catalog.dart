/// Planned coverage, independent of runtime execution results.
///
/// Candidate artifacts are deliberately not executable profiles. Qualification
/// remains in collected, identity-bound run reports, never in this catalog.
List<Map<String, Object?>> validationCoverage() {
  final rows = <Map<String, Object?>>[];
  const platforms = {
    'android-arm64': ['cpu', 'vulkan', 'opencl'],
    'ios-arm64': ['cpu', 'metal'],
    'macos-arm64': ['cpu', 'metal'],
    'macos-x64': ['cpu', 'metal'],
    'linux-x64': ['cpu', 'cuda', 'vulkan'],
    'linux-arm64': ['cpu', 'vulkan'],
    'windows-x64': ['cpu', 'cuda', 'vulkan'],
    'windows-arm64': ['cpu', 'vulkan'],
    'web': ['wasm', 'webgpu'],
  };
  void add(
    String platform,
    String runtime,
    String backend,
    String model,
    String useCase, {
    String status = 'NOT_RUN',
    String reason = 'Requires exact-artifact and platform execution evidence.',
    String? target,
    String? profile,
    String priority = 'primary',
  }) {
    rows.add({
      'id': '$platform/$runtime/$backend/$model/$useCase',
      'platform': platform,
      'runtime': runtime,
      'backend': backend,
      'model': model,
      'use_case': useCase,
      'status': status,
      'reason': reason,
      'target_soc': target,
      'profile':
          profile ??
          (useCase == 'chat' &&
                  status == 'NOT_RUN' &&
                  (platform != 'web' || backend == 'webgpu')
              ? _chatProfile(runtime, backend, model)
              : null),
      'priority': priority,
      'qualification': 'NO_EVIDENCE_IN_CATALOG',
    });
  }

  for (final entry in platforms.entries) {
    for (final backend in entry.value) {
      for (final model in ['gemma4-e2b', 'qwen35-08b']) {
        add(entry.key, 'gguf', backend, model, 'chat');
      }
      add(entry.key, 'gguf', backend, 'qwen3-asr', 'stt');
      add(entry.key, 'gguf', backend, 'qwen3-tts', 'tts');
      add(
        entry.key,
        'gguf',
        backend,
        entry.key == 'web' ? 'laya-q8_0' : 'laya-f16',
        'decision',
        profile: ['cpu', 'metal', 'vulkan', 'cuda', 'webgpu'].contains(backend)
            ? 'decision-gguf-$backend'
            : null,
        status: backend == 'wasm' ? 'UNSUPPORTED' : 'NOT_RUN',
        reason: backend == 'wasm'
            ? 'Decision cases on the WASM CPU exceed the case deadline '
                  '(doc/cross_platform_validation.md#decision-profiles); the '
                  'Web host runs decision profiles only on WebGPU.'
            : 'Requires exact-artifact and platform execution evidence.',
      );
    }
    final platform = entry.key;
    final available = !['windows-arm64', 'macos-x64'].contains(platform);
    final gpu = !['linux-arm64', 'windows-arm64'].contains(platform);
    for (final backend in ['cpu', 'gpu']) {
      for (final model in ['gemma4-e2b', 'qwen35-08b']) {
        final supported = available && (backend == 'cpu' || gpu);
        add(
          platform,
          'litert',
          backend,
          model,
          'chat',
          status: supported ? 'NOT_RUN' : 'UNSUPPORTED',
          reason: supported
              ? 'Lock compatible artifact; Web needs a separate Web-compatible '
                    'export. Verify actual delegate and memory capacity.'
              : 'No supported pinned artifact/backend for this target.',
        );
      }
      add(
        platform,
        'litert',
        backend,
        'dedicated-asr',
        'stt',
        status: available && platform != 'web' && backend == 'cpu'
            ? 'NOT_RUN'
            : 'UNSUPPORTED',
        reason:
            'Typed LiteRT ASR is native CPU-only; requires a matching '
            'speech model and tokenizer, independent of chat weights.',
      );
      add(
        platform,
        'litert',
        backend,
        'speech-model-unavailable',
        'tts',
        status: 'UNSUPPORTED',
        reason: 'Pinned LiteRT runtime exposes no typed TTS path.',
      );
      add(
        platform,
        'litert',
        backend,
        'decision-model-unavailable',
        'decision',
        status: 'UNSUPPORTED',
        reason:
            'DecisionEngine needs a llama.cpp GGUF encoder; LiteRT-LM '
            'reports LlamaUnsupportedException.',
      );
    }
    for (final useCase in ['chat', 'stt', 'tts']) {
      add(
        platform,
        'litert',
        'npu',
        useCase == 'chat' ? 'qwen35-08b' : 'speech-model-unavailable',
        useCase,
        status: platform == 'android-arm64' && useCase == 'chat'
            ? 'UNVERIFIED'
            : 'UNSUPPORTED',
        reason: platform == 'android-arm64' && useCase == 'chat'
            ? 'No compatible Qwen3.5 NPU artifact/runtime established.'
            : 'No exposed typed NPU path for this platform/use case.',
      );
      if (platform != 'android-arm64' && useCase == 'chat') {
        add(
          platform,
          'litert',
          'npu',
          'gemma4-e2b',
          useCase,
          status: 'UNSUPPORTED',
          reason:
              'NPU selector is Android native only; Apple and desktop '
              'NPU hardware does not establish a public runtime path.',
        );
      }
    }
  }
  for (final target in ['tensor-g5', 'qualcomm-sm8750', 'qualcomm-sm8650']) {
    add(
      'android-arm64',
      'litert',
      'npu',
      'gemma4-e2b-$target',
      'chat',
      target: target,
      status: 'UNVERIFIED',
      reason: target == 'qualcomm-sm8650'
          ? 'No matching Gemma 4 artifact established. SM8750 weights must '
                'not be used as an SM8650 substitute.'
          : 'Candidate requires immutable model lock, matching vendor kit, '
                'accessible device and actual NPU execution evidence.',
    );
  }
  for (final target in ['tensor-g5', 'qualcomm-sm8650']) {
    add(
      'android-arm64',
      'litert',
      'npu',
      'gemma3-$target',
      'chat',
      target: target,
      profile: 'npu-$target',
      priority: 'legacy-control',
      reason:
          'Existing runnable profile; historical results remain in run '
          'reports and do not qualify Gemma 4.',
    );
  }
  return rows;
}

String? _chatProfile(String runtime, String backend, String model) {
  if (runtime == 'gguf' &&
      ['cpu', 'metal', 'vulkan', 'cuda', 'webgpu'].contains(backend)) {
    if (model == 'gemma4-e2b' && backend != 'webgpu') {
      return 'gemma4-gguf-$backend';
    }
    if (model == 'qwen35-08b') return 'chat-gguf-$backend';
  }
  if (runtime == 'litert' && ['cpu', 'gpu'].contains(backend)) {
    if (model == 'gemma4-e2b') return 'gemma4-litert-$backend';
    if (model == 'qwen35-08b') return 'qwen35-litert-$backend';
  }
  return null;
}
