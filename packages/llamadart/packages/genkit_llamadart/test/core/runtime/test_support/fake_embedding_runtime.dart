import 'dart:async';

import 'package:genkit_llamadart/genkit_llamadart.dart';

import 'fake_runtime.dart';

class FakeEmbeddingRuntime extends FakeRuntime
    implements LlamaRuntimeEmbeddingProvider {
  LlamaEmbeddingCapabilities embeddingSnapshot =
      const LlamaEmbeddingCapabilities(text: true, image: true, audio: true);
  Object? probeError;
  int embeddingProbeCount = 0;
  int contentCalls = 0;
  List<LlamaEmbeddingInput>? inputs;
  bool blockEmbedding = false;
  bool blockProbe = false;
  final started = Completer<void>();
  final release = Completer<void>();
  final probing = Completer<void>();
  final probeRelease = Completer<void>();

  @override
  Future<LlamaEmbeddingCapabilities> get embeddingCapabilities async {
    embeddingProbeCount++;
    if (!probing.isCompleted) probing.complete();
    if (blockProbe) await probeRelease.future;
    if (probeError != null) throw probeError!;
    return embeddingSnapshot;
  }

  @override
  Future<List<List<double>>> embedContentBatch(
    List<LlamaEmbeddingInput> inputs, {
    bool normalize = true,
  }) async {
    contentCalls++;
    this.inputs = inputs;
    lastNormalize = normalize;
    if (!started.isCompleted) started.complete();
    if (blockEmbedding) await release.future;
    return embeddings;
  }

  void releaseAll() {
    if (!probeRelease.isCompleted) probeRelease.complete();
    if (!release.isCompleted) release.complete();
  }
}
