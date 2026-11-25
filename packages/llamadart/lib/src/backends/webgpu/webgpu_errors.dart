import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../core/exceptions.dart';
import 'interop.dart';
import 'webgpu_decision.dart';

/// Preserves argument validation as a typed backend failure.
T webGpuValidateArguments<T>(T Function() call) {
  try {
    return call();
  } on ArgumentError catch (error) {
    throw LlamaArgumentException(
      webGpuBridgeErrorText(error),
      name: error.name,
      invalidValue: error.invalidValue,
    );
  }
}

// Only the pinned bridge's TypeError/RangeError validator messages establish
// argument provenance. Worker transport can erase their names; direct runtime
// failures can share those names. Keep both paths on the same allowlist.
// Source emissions and routing: doc/webgpu_bridge.md, "Request errors".
final RegExp _bridgeArgument = RegExp(
  r'^(?:CompletionOptions\.(?:presencePenalty|minP) must be a finite number|'
  r'CompletionOptions\.thinkingBudget(?: must be an object\.|'
  r'\.(?:startTag|endTag) must be a non-empty string\.|'
  r'\.forcedMessage must be a string\.|'
  r'\.maxTokens must be an integer from )|'
  r'CompletionOptions\.(?:grammar(?:Root)? contains U\+0000, which the core cannot read\.|'
  r'grammarRoot must be a non-empty string\.|'
  r'grammarLazy must be a boolean;|'
  r'(?:grammarLazy|grammarRoot) needs a non-empty CompletionOptions\.grammar\.|'
  r'grammarLazy needs at least one CompletionOptions\.grammarTriggers entry\.|'
  r'grammarTriggers(?: must be an array\.|\[\d+\](?: must be an object\.|'
  r'\.type must be one of |\.token must be an integer from |'
  r'\.value must be a non-empty string\.|'
  r'\.value contains U\+0000, which the core cannot read\.)))|'
  r'CompletionOptions\.speculativeDecoding(?: must be an object\.|'
  r'\.strategies (?:must be a non-empty array\.|has an unknown strategy )|'
  r'\.(?:draftTokenMax|draftTokenMin|ngramSizeN|ngramSizeM|ngramMinHits|'
  r'ngramMatch|ngramTokenMin|ngramTokenMax) must be an integer from |'
  r'\.(?:ngramTokenMin|draftTokenMin) \([^)]*\) must not exceed |'
  r'\.(?:minProbability|draftSplitProbability) must be a number from 0 to 1;|'
  r'\.(?:ngramCacheStatic|ngramCacheDynamic) (?:is empty\.|'
  r'must be a URL string, an ArrayBuffer or a typed array\.))|'
  r'LoRA adapter (?:handle must be a positive integer, got |'
  r'scale (?:must be a finite number, got |[^ ]+ is outside the 32-bit float range\.)|'
  r'source must be a URL string, an ArrayBuffer or a typed array\.)|'
  r'Next-token (?:candidates(?: must be an array or typed array of token ids\.|'
  r'\[\d+\] is .*; expected a 32-bit integer\.)|'
  r'scoring prompt must be a string\.|topK is .*; expected a 32-bit integer\.))',
);

final RegExp _bridgeUnsupportedCompletion = RegExp(
  r'^The loaded WebGPU core does not support CompletionOptions\.'
  r'(?:presencePenalty|minP|thinkingBudget\.(?:pauseGrammar|naturalEndTags)|thinkingBudget|grammarLazy|grammarRoot|penaltyPromptTokensWithGrammar|speculativeDecoding)'
  r'(?: or CompletionOptions\.'
  r'(?:presencePenalty|minP|thinkingBudget\.(?:pauseGrammar|naturalEndTags)|thinkingBudget|grammarLazy|grammarRoot|penaltyPromptTokensWithGrammar|speculativeDecoding))*\.$',
);

/// Required core capability for template-derived thinking-budget ends.
const String webGpuThinkingBudgetMultiEndRequired =
    'WebGPU template-derived thinking-budget ends require bridge assets '
    'v0.1.87+ whose core reports thinkingBudgetMultiEnd.';

/// Maps the bridge's stable post-abort state error on either runtime.
LlamaModelUnloadedException? webGpuModelUnloadedError(Object error) {
  if (error is LlamaModelUnloadedException) return error;
  try {
    final object = error as JSObject;
    final code = object.getProperty<JSAny?>('code'.toJS);
    if (code.isA<JSString>() &&
        (code as JSString).toDart == 'MODEL_UNLOADED_AFTER_CORE_ABORT') {
      return LlamaModelUnloadedException();
    }
  } catch (_) {
    // Primitive rejections carry no bridge error code.
  }
  return null;
}

/// Preserves direct core retirement when a capability preflight would mask it.
void webGpuThrowIfModelUnloaded(LlamaWebGpuBridge bridge) {
  final bool unloaded;
  try {
    final metadata = bridge.getModelMetadata();
    if (metadata == null ||
        metadata
                .getProperty<JSString?>('llamadart.webgpu.execution'.toJS)
                ?.toDart !=
            'main-thread' ||
        metadata
                .getProperty<JSString?>('llamadart.webgpu.model_bytes'.toJS)
                ?.toDart !=
            '0') {
      return;
    }
    // The bridge publishes core_retired on the direct runtime snapshot. The
    // model byte count distinguishes retirement from notes retained after load.
    final notes = metadata
        .getProperty<JSString?>('llamadart.webgpu.runtime_notes'.toJS)
        ?.toDart;
    unloaded = notes?.split(';').contains('core_retired') ?? false;
  } catch (_) {
    return;
  }
  if (unloaded) throw LlamaModelUnloadedException();
}

/// Classifies request rejections without reclassifying unknown runtime errors.
///
/// General request validators expose JS RangeError/TypeError. Media embedding
/// stable codes are handled separately by the embedding operation fallback.
LlamaException? webGpuBridgeRequestError(
  Object error, {
  Iterable<String> sourceUrls = const <String>[],
}) {
  if (error is LlamaException) return error;
  final unloaded = webGpuModelUnloadedError(error);
  if (unloaded != null) return unloaded;
  String? name;
  try {
    final value = (error as JSObject).getProperty<JSAny?>('name'.toJS);
    if (value.isA<JSString>()) name = (value as JSString).toDart;
  } catch (_) {
    // Dart errors and primitive JS rejections have no JS error name.
  }
  final message = webGpuBridgeErrorText(error, sourceUrls: sourceUrls);
  if (name == 'Error' &&
      (message.contains('CompletionOptions.grammar') ||
          message.contains('CompletionOptions.thinkingBudget') ||
          message.contains(
            'CompletionOptions.penaltyPromptTokensWithGrammar',
          )) &&
      _bridgeUnsupportedCompletion.hasMatch(message)) {
    return LlamaUnsupportedException(
      message.contains('CompletionOptions.thinkingBudget.naturalEndTags')
          ? '$message $webGpuThinkingBudgetMultiEndRequired'
          : message,
    );
  }
  if (name == 'Error' &&
      (message ==
              'Failed to start generation: Failed to initialize sampler chain '
                  '(invalid grammar)' ||
          message ==
              'Generation step failed: The lazy grammar rejected the text '
                  'that triggered it')) {
    return LlamaInferenceException(
      'WebGPU grammar generation failed.',
      message,
    );
  }
  if ((name == 'RangeError' || name == 'TypeError' || name == 'Error') &&
      _bridgeArgument.hasMatch(message)) {
    return LlamaArgumentException(message);
  }
  return null;
}

/// The bridge's `CrossOriginIsolationError` code, which the worker path keeps
/// on the error it rebuilds in the page.
const String _crossOriginIsolationRequiredCode =
    'CROSS_ORIGIN_ISOLATION_REQUIRED';

/// Returns [LlamaUnsupportedException] when [error] is the bridge's
/// `CrossOriginIsolationError` (assets `v0.1.85+`), otherwise null.
LlamaUnsupportedException? webGpuCrossOriginIsolationError(Object error) {
  if (error is LlamaException) return null;
  try {
    final object = error as JSObject;
    final code = object.getProperty<JSAny?>('code'.toJS);
    final name = object.getProperty<JSAny?>('name'.toJS);
    final isIsolationError =
        (code.isA<JSString>() &&
            (code as JSString).toDart == _crossOriginIsolationRequiredCode) ||
        (name.isA<JSString>() &&
            (name as JSString).toDart == 'CrossOriginIsolationError');
    if (!isIsolationError) return null;
  } catch (_) {
    return null;
  }
  return webGpuCrossOriginIsolationRequired();
}

/// Reports the headers required for the threaded Web core.
LlamaUnsupportedException webGpuCrossOriginIsolationRequired() =>
    LlamaUnsupportedException(
      'The Web runtime needs cross-origin isolation (COOP/COEP) for shared '
      'memory, which this page does not have. Serve the page with '
      '"Cross-Origin-Opener-Policy: same-origin" and '
      '"Cross-Origin-Embedder-Policy: require-corp". '
      '"credentialless" does not isolate Safari.',
    );

/// The stable fields carried by a bridge core-asset error on either runtime.
({String code, String? asset})? webGpuCoreAssetError(Object error) {
  try {
    final object = error as JSObject;
    String? string(String key) {
      final value = object[key];
      return value.isA<JSString>() ? (value as JSString).toDart : null;
    }

    final code = string('code');
    if (string('name') == 'CoreAssetError' && code != null) {
      return (code: code, asset: string('asset'));
    }
  } catch (_) {
    // Primitive rejections carry no bridge error code.
  }
  return null;
}

/// Required bridge capability for an explicit JS-backed staging request.
const String webGpuJsBackedStagingRequired =
    'JS-backed model staging (ModelParams.jsBackedModelStaging) requires '
    'llama-web-bridge-assets v0.1.92+ exposing '
    'LlamaWebGpuBridge.supportsJsBackedModelStaging with a staging-capable '
    'worker and Wasm core (ABI v3+). Run dart run llamadart:web_setup to '
    'update bridge assets, or omit or disable jsBackedModelStaging.';

/// The bridge worker or Wasm core cannot apply JS-backed staging.
class WebGpuJsBackedStagingUnsupported extends LlamaUnsupportedException {
  /// Creates the pre-transfer capability diagnostic.
  WebGpuJsBackedStagingUnsupported()
    : super('MODEL_STAGING_UNSUPPORTED: $webGpuJsBackedStagingRequired');
}

final RegExp _stagingErrorPath = RegExp(
  r'''(?:[a-zA-Z][a-zA-Z0-9+.-]*:)?[/\\][^\s'"<>),;]+''',
);

const String _modelTransferLengthErrorCode = 'MODEL_TRANSFER_LENGTH_ERROR';

final RegExp _legacyModelTransferLengthMessage = RegExp(
  r'^Model response (?:did not match its declared decoded size|'
  r'ended before its declared byte length|exceeded its declared byte length|'
  r'reported conflicting Content-Range and X-Linked-Size totals|'
  r'staged \d+ bytes, expected (?:at least )?\d+)\.$',
);

/// Maps terminal staging and length failures by the bridge's wire identifiers.
LlamaException? webGpuModelStagingError(
  Object error, {
  Iterable<String> sourceUrls = const <String>[],
}) {
  final String name;
  final String code;
  try {
    final object = error as JSObject;
    final rawName = object['name'];
    final rawCode = object['code'];
    if (!rawName.isA<JSString>()) return null;
    name = (rawName as JSString).toDart;
    if (rawCode.isA<JSString>()) {
      code = (rawCode as JSString).toDart;
    } else {
      // Legacy bridges expose the name and message without a code.
      if (rawCode != null || name != 'ModelTransferLengthError') return null;
      final rawMessage = object['message'];
      if (!rawMessage.isA<JSString>() ||
          !_legacyModelTransferLengthMessage.hasMatch(
            (rawMessage as JSString).toDart,
          )) {
        return null;
      }
      code = _modelTransferLengthErrorCode;
    }
  } catch (_) {
    return null;
  }

  if (name == 'ModelStagingError') {
    switch (code) {
      case 'MODEL_STAGING_UNSUPPORTED':
        return WebGpuJsBackedStagingUnsupported();
      case 'MODEL_TENSOR_SIZE_LIMIT_EXCEEDED':
        return LlamaUnsupportedException(
          '$code: Model tensors, individually or in total, exceed the wasm32 '
          '4 GiB limit. '
          'Use ModelParams(preferMemory64: true) with a memory64-capable browser.',
        );
    }
  }

  final message = switch ((name, code)) {
    ('ModelStagingError', 'MODEL_STAGING_ALLOCATION_FAILED') =>
      'JS-backed model staging could not allocate JavaScript memory',
    ('ModelStagingError', 'MODEL_STAGING_MOUNT_FAILED') =>
      'JS-backed model staging could not mount or retain its private filesystem',
    ('ModelTransferLengthError', _modelTransferLengthErrorCode) =>
      'Web model transfer length did not match the declared response size',
    _ => null,
  };
  if (message == null) return null;
  return LlamaModelException(
    '$message ($code).',
    webGpuBridgeErrorText(
      error,
      sourceUrls: sourceUrls,
    ).replaceAll(_stagingErrorPath, '<path>'),
  );
}

final RegExp _gpuUnavailableNote = RegExp(r'(?:^|;)gpu_unavailable:([^;]+)');

/// Why the bridge ran without GPU layers, from its `gpu_unavailable:<reason>`
/// runtime note (assets `v0.1.85+`), or an empty string.
String webGpuUnavailableDetail(String runtimeNotes) {
  final reason = _gpuUnavailableNote.firstMatch(runtimeNotes)?.group(1);
  return switch (reason) {
    null => '',
    'no_webgpu' => ' The browser exposes no WebGPU.',
    'no_adapter' => ' The browser granted no WebGPU adapter.',
    'adapter_missing_shader_f16' =>
      ' WebGPU needs the shader-f16 feature, which this adapter does not '
          'expose. On Linux with an NVIDIA GPU, Chrome exposes it only with '
          'driver 615.71 or newer.',
    _ => ' The bridge reported gpu_unavailable:$reason.',
  };
}
