import 'dart:convert';

import 'package:llamadart/llamadart.dart';
import 'package:llamadart/src/backends/backend.dart';
import 'package:llamadart/src/backends/native/native_backend.dart';

/// Records bytes before the public completion parser consumes them.
class Lfm2RecordingBackend extends NativeAutoBackend {
  Lfm2RecordingBackend({super.llamaCppFactory, super.liteRtLmFactory});

  final List<int> bytes = [];
  final List<List<int>> _byteChunks = [];

  List<List<int>> get byteChunks => [
    for (final chunk in _byteChunks) List<int>.of(chunk),
  ];
  bool limitQueried = false;
  bool usageQueried = false;
  BackendGenerationLimit? reportedLimit;
  LlamaGenerationUsage? reportedUsage;

  Map<String, dynamic> get capturedOutcome => {
    'limit_queried': limitQueried,
    'limit': reportedLimit?.name,
    'usage_queried': usageQueried,
    'usage': reportedUsage?.toJson(),
  };
  GenerationParams? lastParams;
  String? lastPrompt;
  bool countedPromptPenalties = false;
  final Map<Stream<List<int>>, Stream<List<int>>> _sources = {};

  String get raw => utf8.decode(bytes);

  void resetCapture() {
    bytes.clear();
    _byteChunks.clear();
    limitQueried = false;
    usageQueried = false;
    reportedLimit = null;
    reportedUsage = null;
    lastParams = null;
    lastPrompt = null;
    countedPromptPenalties = false;
    _sources.clear();
  }

  Stream<List<int>> _record(
    Stream<List<int>> source,
    String prompt,
    GenerationParams params, {
    bool promptPenalties = false,
  }) {
    lastPrompt = prompt;
    lastParams = params;
    countedPromptPenalties = promptPenalties;
    final captured = source.map((chunk) {
      _byteChunks.add(List<int>.of(chunk));
      bytes.addAll(chunk);
      return chunk;
    });
    _sources[captured] = source;
    return captured;
  }

  @override
  Stream<List<int>> generate(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    List<LlamaContentPart>? parts,
  }) => _record(
    super.generate(contextHandle, prompt, params, parts: parts),
    prompt,
    params,
  );

  @override
  Stream<List<int>> generateChatPrompt(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    required String mediaMarker,
    List<LlamaContentPart>? parts,
  }) => _record(
    super.generateChatPrompt(
      contextHandle,
      prompt,
      params,
      mediaMarker: mediaMarker,
      parts: parts,
    ),
    prompt,
    params,
  );

  @override
  Stream<List<int>> generateWithPromptPenalties(
    int contextHandle,
    String prompt,
    GenerationParams params, {
    String? mediaMarker,
    List<LlamaContentPart>? parts,
  }) => _record(
    super.generateWithPromptPenalties(
      contextHandle,
      prompt,
      params,
      mediaMarker: mediaMarker,
      parts: parts,
    ),
    prompt,
    params,
    promptPenalties: true,
  );

  @override
  BackendGenerationLimit? generationLimitOf(Stream<List<int>> generation) {
    limitQueried = true;
    return reportedLimit = super.generationLimitOf(
      _sources[generation] ?? generation,
    );
  }

  @override
  LlamaGenerationUsage? generationUsageOf(Stream<List<int>> generation) {
    usageQueried = true;
    return reportedUsage = super.generationUsageOf(
      _sources[generation] ?? generation,
    );
  }
}
