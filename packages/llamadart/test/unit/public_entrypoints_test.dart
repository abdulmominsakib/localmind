@TestOn('vm')
library;

import 'dart:io';
import 'dart:mirrors';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:llamadart/backend.dart';
import 'package:llamadart/llamadart.dart';
import 'package:test/test.dart';

const _appUri = 'package:llamadart/llamadart.dart';
const _backendUri = 'package:llamadart/backend.dart';
const _bindingsUri = 'package:llamadart/llama_cpp_bindings.dart';

const _engineHooks = <String>{
  'backendDecisionCapabilities',
  'backendTextToSpeechCapabilities',
  'cancelTextToSpeechBackend',
  'contextHandle',
  'freeDecisionHeadBackend',
  'loadDecisionHeadBackend',
  'modelHandle',
  'runDecisionBackend',
  'synthesizeTextToSpeechBackend',
};

/// Every top-level name `package:llamadart/llamadart.dart` exports. Adding or
/// removing an app-facing name is a public API change; update this list on
/// purpose.
const _appNames = <String>{
  'liteRtLmQwen3ChatTemplate',
  'BackendPerfContextData',
  'BackendTextToSpeechModel',
  'ChatFormat',
  'ChatGenerationTask',
  'ChatGenerationCompletion',
  'ChatParseResult',
  'ChatSession',
  'ChatterboxTtsAdapter',
  'ChatSessionCompletionExtension',
  'ChatSessionToolLoopExtension',
  'ChatTemplateEngine',
  'ChatTemplateHandler',
  'ChoiceAnswer',
  'ChoiceKey',
  'ChoiceOf',
  'ChoiceQuestion',
  'ComputeDevice',
  'ControlNetImageGenerationRequest',
  'DecisionAnswer',
  'DecisionCapabilities',
  'DecisionCompletion',
  'DecisionCompletionState',
  'DecisionTask',
  'DecisionEngine',
  'DecisionKey',
  'DecisionModel',
  'DecisionModelInfo',
  'DecisionModelParams',
  'DecisionQuestion',
  'DecisionQuestionType',
  'DecisionRequest',
  'DecisionResult',
  'DecisionResultKeys',
  'DecisionUsage',
  'DefaultModelDownloadManager',
  'DefaultModelResolver',
  'EngineCapabilities',
  'FlashAttention',
  'GeneratedImage',
  'GenerationGrammarTrigger',
  'GenerationParams',
  'GenerationTaskState',
  'GpuBackend',
  'GpuDeviceInfo',
  'GpuDeviceType',
  'GrammarTrigger',
  'GrammarTriggerType',
  'HiresFixImageGenerationRequest',
  'ImageConditioningCacheParams',
  'ImageControlNetCondition',
  'ImageEditingPixels',
  'ImageEditingRequest',
  'ImageGenerationCapabilities',
  'ImageGenerationCompletion',
  'ImageGenerationCompletionState',
  'ImageGenerationEngine',
  'ImageGenerationEvent',
  'ImageGenerationFinalEvent',
  'ImageGenerationModel',
  'ImageGenerationPhase',
  'ImageGenerationProgressEvent',
  'ImageGenerationRequest',
  'SeamlessImageGenerationRequest',
  'ImageGenerationResult',
  'ImageGenerationSampler',
  'ImageGenerationScheduler',
  'ImageGenerationTask',
  'ImageHiresFix',
  'ImageHiresUpscaler',
  'ImageModelComponent',
  'ImageModelParams',
  'ImageModelPlacement',
  'ImageModelRole',
  'ImageReferenceEditingRecipe',
  'ImageVaeTiling',
  'TiledImageGenerationRequest',
  'KvCacheType',
  'Lfm3AudioTtsAdapter',
  'LiteRtLmActivationDataType',
  'LiteRtLmAsrAdapter',
  'LiteRtLmAsrBackend',
  'LiteRtLmAsrModelPreset',
  'LiteRtLmAsrRuntimeConfig',
  'LiteRtLmBackendPreference',
  'LiteRtLmModelParams',
  'LlamaArgumentException',
  'LlamaAudioContent',
  'LlamaAudioFormatException',
  'LlamaBackend',
  'LlamaBackendInitializationException',
  'LlamaChatMessage',
  'LlamaChatOperation',
  'LlamaChatRole',
  'LlamaChatTemplateResult',
  'LlamaCompletion',
  'LlamaCompletionChunk',
  'LlamaCompletionChunkChoice',
  'LlamaCompletionChunkDelta',
  'LlamaCompletionChunkExtension',
  'LlamaCompletionChunkFunction',
  'LlamaCompletionChunkToolCall',
  'LlamaCompletionStreamExtension',
  'LlamaContentPart',
  'LlamaContextException',
  'LlamaCppModelParams',
  'LlamaDecisionException',
  'LlamaEmbeddingCapabilities',
  'LlamaEmbeddingInput',
  'LlamaEmbeddingModality',
  'LlamaEmbeddingProfile',
  'LlamaEmbeddingTask',
  'LlamaEmbeddingText',
  'LlamaEmbeddingsOperation',
  'LlamaEngine',
  'LlamaTextEmbedder',
  'LlamaEngineCapabilities',
  'LlamaEngineCompletionExtension',
  'LlamaEngineObserver',
  'LlamaException',
  'LlamaFinishReason',
  'LlamaGenerationUsage',
  'LlamaImageContent',
  'LlamaImageGenerationException',
  'LlamaInferenceException',
  'LlamaEmbeddingInputTooLongException',
  'LlamaLoadCheckReport',
  'LlamaLoadCheckStatus',
  'LlamaLogLevel',
  'LlamaLogRecord',
  'LlamaLogger',
  'LlamaLogging',
  'LlamaModel',
  'LlamaModelException',
  'LlamaModelFormatException',
  'LlamaModelLoadOperation',
  'LlamaNextTokenScores',
  'LlamaOperation',
  'LlamaOperationObserver',
  'LlamaOperationResult',
  'LlamaReranker',
  'LlamaRerankResult',
  'LlamaRerankingCapabilities',
  'LlamaRuntime',
  'LlamaRuntimeSetupReport',
  'LlamaRuntimeSetupRuntime',
  'collectLlamaRuntimeSetupReport',
  'LlamaSpeechException',
  'LlamaSpeechTranscriptLimit',
  'LlamaSpeechTranscriptTruncatedException',
  'LlamaStateException',
  'LlamaStateIdentity',
  'LlamaStructuredOutput',
  'LlamaStructuredOutputStreamExtension',
  'LlamaTextCompletionOperation',
  'LlamaTextContent',
  'LlamaTextToSpeechException',
  'LlamaThinkingContent',
  'LlamaTokenLogprob',
  'LlamaToolCallContent',
  'LlamaToolLoopResult',
  'LlamaToolLoopStopReason',
  'LlamaToolOutput',
  'LlamaToolResultContent',
  'LlamaToolResultMedia',
  'LlamaUnsupportedException',
  'LlamaVideoContent',
  'LlamadartEngine',
  'LocalModelFile',
  'LoraAdapterConfig',
  'ModelCacheEntry',
  'ModelCacheEntryInUseException',
  'ModelCachePlatform',
  'ModelCachePolicy',
  'ModelDownloadCancelToken',
  'ModelDownloadController',
  'ModelDownloadManager',
  'ModelDownloadProgress',
  'ModelDownloadTaskSnapshot',
  'ModelDownloadTaskStage',
  'ModelFileStore',
  'ModelFileType',
  'ModelFormat',
  'ModelLoadOptions',
  'ModelLoadTarget',
  'ModelParams',
  'ModelResolveRequest',
  'ModelResolver',
  'ModelSource',
  'ModelSourceKind',
  'ModelSplitMode',
  'NoulAnswer',
  'NoulKey',
  'NoulQuestion',
  'PocketTtsAdapter',
  'Qwen3AsrAdapter',
  'Qwen3TtsAdapter',
  'SopranoTtsAdapter',
  'ReferenceImageEditingRequest',
  'RemoteModelUrl',
  'ScoreAnswer',
  'ScoreKey',
  'ScoreQuestion',
  'SpeculativeDecodingConfig',
  'SpeculativeDecodingStrategy',
  'SpeechAudioBytesInput',
  'SpeechAudioFileInput',
  'SpeechAudioFormat',
  'SpeechAudioInput',
  'SpeechAudioInputKind',
  'SpeechAudioPcmInput',
  'SpeechToTextAdapter',
  'SpeechToTextCapabilities',
  'SpeechToTextCompletion',
  'SpeechToTextCompletionState',
  'SpeechToTextEngine',
  'SpeechToTextEvent',
  'SpeechToTextFinalEvent',
  'SpeechToTextImplementation',
  'SpeechToTextModel',
  'SpeechToTextModelProfile',
  'SpeechToTextPartialEvent',
  'SpeechToTextPromptAdapter',
  'SpeechToTextRequest',
  'SpeechToTextResult',
  'SpeechToTextStreamingSession',
  'SpeechToTextTask',
  'SpeechToTextTranscript',
  'StateLoadResult',
  'TemplateTimeChatSession',
  'TemplateToolCallSerialization',
  'TextToSpeechAdapter',
  'TextToSpeechCapabilities',
  'TextToSpeechCompletion',
  'TextToSpeechCompletionState',
  'TextToSpeechEngine',
  'TextToSpeechEvent',
  'TextToSpeechFinalEvent',
  'TextToSpeechImplementation',
  'TextToSpeechModel',
  'TextToSpeechModelProfile',
  'TextToSpeechProgressEvent',
  'TextToSpeechProgressPhase',
  'TextToSpeechRequest',
  'TextToSpeechResult',
  'TextToSpeechTask',
  'TextGenerationTask',
  'TextGenerationCompletion',
  'ThinkingBudget',
  'ThrowingModelDownloadManager',
  'ToolChoice',
  'ToolDefinition',
  'ToolParam',
  'ToolParams',
  'TranscriptSegment',
  'TranscriptWord',
  'hasPersistentCacheSensitiveUrlParts',
  'resolveModelContextBatchSizes',
};

void main() {
  test('exports a stable LiteRT-LM Qwen3 template accessor', () async {
    expect(
      _exportedNames(await _load(_appUri)),
      contains('liteRtLmQwen3ChatTemplate'),
    );
  });

  late LibraryMirror backendLibrary;
  late Set<String> app;
  late Set<String> backend;
  late Set<String> ffi;

  setUpAll(() async {
    backendLibrary = await _load(_backendUri);
    app = _exportedNames(await _load(_appUri));
    backend = _exportedNames(backendLibrary);
    ffi = _exportedNames(await _load(_bindingsUri));
  });

  test('the app entrypoint exports exactly the pinned names', () {
    expect(app, _appNames);
  });

  test('the app entrypoint exports no ffigen bindings', () {
    expect(ffi, containsAll(['llama_decode', 'llama_batch', 'ggml_type']));
    expect(app.intersection(ffi), isEmpty);
  });

  test('the app entrypoint keeps only the app-facing backend types', () {
    expect(app.where((name) => name.startsWith('Backend')).toSet(), {
      'BackendPerfContextData',
      'BackendTextToSpeechModel',
    });
    expect(app, containsAll(['LlamaBackend', 'StateLoadResult']));
    expect(
      app,
      containsAll([
        'LiteRtLmAsrBackend',
        'LiteRtLmAsrModelPreset',
        'LiteRtLmAsrRuntimeConfig',
        'TemplateTimeChatSession',
        'TemplateToolCallSerialization',
      ]),
    );
    expect(app.where((name) => name.startsWith('LiteRtLmBenchmark')), isEmpty);
    expect(app.intersection(backend), {
      'LlamaBackend',
      'BackendPerfContextData',
      'BackendTextToSpeechModel',
      'StateLoadResult',
    });
  });

  test('the backend entrypoint exports the backend SPI', () {
    expect(backend, {
      'LlamaBackend',
      'BackendAvailability',
      'BackendBatchEmbeddings',
      'BackendChatPromptGeneration',
      'BackendChatScope',
      'BackendDartLogLevel',
      'BackendDecision',
      'BackendDecisionCapabilities',
      'BackendDecisionHeadInfo',
      'BackendDecisionOutput',
      'BackendDecisionSequence',
      'BackendDeferredEngineCreation',
      'BackendDirectMediaInput',
      'BackendEmbeddings',
      'BackendEmbeddingsSupport',
      'BackendMultimodalEmbeddings',
      'BackendGenerationCapabilities',
      'BackendGenerationCapabilitiesSupport',
      'BackendGenerationLimitSupport',
      'BackendGpuEnumeration',
      'BackendGrammarConstraintsSupport',
      'BackendJsonSchemaChatGeneration',
      'BackendJsonSchemaThinkingChatGeneration',
      'BackendLazyGrammarSupport',
      'BackendPromptPenaltyGeneration',
      'BackendLoadCheck',
      'BackendLoraSupport',
      'BackendModelFileTypeDiagnostics',
      'BackendModelFormatRouting',
      'BackendMultimodalSupport',
      'BackendNativeChatGeneration',
      'BackendNextTokenScoring',
      'BackendNextTokenScoringSupport',
      'BackendPerfContextData',
      'BackendPerformanceDiagnostics',
      'BackendReranking',
      'BackendRerankingOutput',
      'BackendPromptSpeechToTextSupport',
      'BackendRuntimeDiagnostics',
      'BackendRuntimeIdentity',
      'BackendStateIdentity',
      'BackendStatePersistence',
      'BackendStatePersistenceSupport',
      'BackendTextToSpeech',
      'BackendTextToSpeechCapabilities',
      'BackendTextToSpeechModel',
      'BackendTextToSpeechModelSupport',
      'BackendTextToSpeechPhase',
      'BackendTextToSpeechProgress',
      'BackendTextToSpeechRequest',
      'BackendTextToSpeechResult',
      'BackendToolResultMedia',
      'StateLoadResult',
      'LlamaEngineBackendHooks',
      'LiteRtLmBackend',
      'LiteRtLmFinishReason',
      'LiteRtLmNativeSettlement',
      'LiteRtLmRuntimeClient',
      'LiteRtLmRuntimeMetrics',
      'LiteRtLmRuntimeResult',
      'LiteRtLmAsrProcessResult',
      'LiteRtLmAsrProcessState',
      'LiteRtLmAsrPushResult',
      'LiteRtLmAsrRuntimeSession',
    });
  });

  test('exported classes implement only exported llamadart types', () async {
    final exported = <String, DeclarationMirror>{
      ..._exportedDeclarations(await _load(_appUri)),
      ..._exportedDeclarations(backendLibrary),
    };
    final unexported = <String>{
      for (final MapEntry(:key, :value) in exported.entries)
        if (value is ClassMirror)
          for (final supertype in _supertypes(value))
            if (_isPackageType(supertype) &&
                !exported.containsKey(_typeName(supertype)))
              '$key -> ${_typeName(supertype)}',
    };

    expect(unexported, isEmpty);
  });

  test('every platform variant of a backend export implements only exported '
      'types', () {
    final exported = app.union(backend);
    final variants = <String>{};
    final unexported = <String>{};
    for (final directive in _parse(
      'lib/backend.dart',
    ).directives.whereType<ExportDirective>()) {
      if (directive.configurations.isEmpty) continue;
      final shown = {
        for (final combinator
            in directive.combinators.whereType<ShowCombinator>())
          for (final name in combinator.shownNames) name.name,
      };
      for (final uri in [
        directive.uri.stringValue!,
        for (final configuration in directive.configurations)
          configuration.uri.stringValue!,
      ]) {
        for (final declaration in _parse(
          'lib/$uri',
        ).declarations.whereType<ClassDeclaration>()) {
          // The token after `class` is the name in every supported analyzer.
          final name = declaration.classKeyword.next!.lexeme;
          if (!shown.contains(name)) continue;
          variants.add('$uri $name');
          for (final supertype in [
            ?declaration.extendsClause?.superclass,
            ...?declaration.withClause?.mixinTypes,
            ...?declaration.implementsClause?.interfaces,
          ]) {
            final supertypeName = supertype.toSource().split('<').first;
            if (!exported.contains(supertypeName)) {
              unexported.add('$uri $name -> $supertypeName');
            }
          }
        }
      }
    }

    expect(
      variants,
      contains(
        'src/backends/litert_lm/litert_lm_backend_web.dart '
        'LiteRtLmBackend',
      ),
    );
    expect(unexported, isEmpty);
  });

  test('examples use the app API, not the raw llama.cpp bindings', () {
    expect([
      for (final file in _dartSources(Directory('example')))
        if (file.readAsStringSync().contains(_bindingsUri)) file.path,
    ], isEmpty);
  });

  test('the engine hooks are extension members a subclass cannot override', () {
    final instanceMembers = reflectClass(
      LlamaEngine,
    ).instanceMembers.keys.map(MirrorSystem.getName).toSet();
    final hookMembers = _exportedMembers(
      backendLibrary,
      'LlamaEngineBackendHooks',
    );

    expect(hookMembers, _engineHooks);
    expect(instanceMembers.intersection(_engineHooks), isEmpty);
  });

  test('LiteRtLmRuntimeClient no longer has the removed members', () {
    final members = reflectClass(
      LiteRtLmRuntimeClient,
    ).instanceMembers.keys.map(MirrorSystem.getName).toSet();

    expect(members, contains('createConversation'));
    expect(
      members.intersection({
        'conversationTokenCount',
        'replaceConversationWithClone',
      }),
      isEmpty,
    );
  });
}

Future<LibraryMirror> _load(String uri) =>
    currentMirrorSystem().isolate.loadUri(Uri.parse(uri));

/// The Dart files under [directory], skipping hidden and `build` directories
/// that hold generated and third-party code.
Iterable<File> _dartSources(Directory directory) sync* {
  for (final entity in directory.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is Directory) {
      if (name.startsWith('.') || name == 'build') continue;
      yield* _dartSources(entity);
    } else if (entity is File && name.endsWith('.dart')) {
      yield entity;
    }
  }
}

CompilationUnit _parse(String path) =>
    parseString(content: File(path).readAsStringSync(), path: path).unit;

/// The top-level names [library] exports. The VM mirror system lists an
/// extension as one `Extension.member` entry per member, so those collapse to
/// the extension's name.
Set<String> _exportedNames(LibraryMirror library) => _exportedDeclarations(
  library,
).keys.map((name) => name.split('.').first).toSet();

Set<String> _exportedMembers(LibraryMirror library, String extension) => {
  for (final name in _exportedDeclarations(library).keys)
    if (name.startsWith('$extension.')) name.substring(extension.length + 1),
};

/// Follows export directives. The VM splits `show A, B` into one combinator
/// per name, so the shown and hidden names of a directive are unioned.
Map<String, DeclarationMirror> _exportedDeclarations(LibraryMirror library) {
  final declarations = <String, DeclarationMirror>{
    for (final MapEntry(:key, :value) in library.declarations.entries)
      if (!value.isPrivate) MirrorSystem.getName(key): value,
  };
  for (final dependency in library.libraryDependencies) {
    if (!dependency.isExport) continue;
    final shown = <String>{};
    final hidden = <String>{};
    for (final combinator in dependency.combinators) {
      (combinator.isShow ? shown : hidden).addAll(
        combinator.identifiers.map(MirrorSystem.getName),
      );
    }
    for (final MapEntry(:key, :value) in _exportedDeclarations(
      dependency.targetLibrary!,
    ).entries) {
      final topLevel = key.split('.').first;
      if ((shown.isEmpty || shown.contains(topLevel)) &&
          !hidden.contains(topLevel)) {
        declarations[key] = value;
      }
    }
  }
  return declarations;
}

/// The declared supertypes of [type], looking through the anonymous
/// `S with M` classes that mixins create.
Iterable<ClassMirror> _supertypes(ClassMirror type) sync* {
  yield* type.superinterfaces;
  final superclass = type.superclass;
  if (superclass == null) return;
  if (superclass.mixin != superclass) {
    yield superclass.mixin;
    yield* _supertypes(superclass);
  } else {
    yield superclass;
  }
}

bool _isPackageType(ClassMirror type) {
  final owner = type.originalDeclaration.owner;
  return owner is LibraryMirror &&
      owner.uri.toString().startsWith('package:llamadart/');
}

String _typeName(ClassMirror type) =>
    MirrorSystem.getName(type.originalDeclaration.simpleName);
