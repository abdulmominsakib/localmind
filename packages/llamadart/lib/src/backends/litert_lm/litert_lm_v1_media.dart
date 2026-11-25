part of 'litert_lm_v1_runtime.dart';

final class _V1MediaSupport {
  const _V1MediaSupport(this.image, this.audio, this.visualBudget);
  final bool image, audio, visualBudget;
}

extension _V1MediaAdmission on LiteRtLmV1Runtime {
  _V1MediaSupport _inspectMediaSupport() {
    _requireLive();
    if (nativeSettlement != LiteRtLmNativeSettlement.settled) {
      throw LlamaStateException('Settle native work before inspecting media.');
    }
    final cached = _mediaSupport;
    if (cached != null) return cached;
    const unsupported = _V1MediaSupport(false, false, false);
    final path = _engineModelPath, options = _engineOptions;
    if (path == null ||
        options == null ||
        (options.visionBackend == null && options.audioBackend == null)) {
      return _mediaSupport = unsupported;
    }
    final processor = readLiteRtLmBundleMediaProcessor(path);
    if (processor == null) return _mediaSupport = unsupported;
    try {
      final declarations = bundleCapabilities(path);
      var family = processor.family;
      if (family == 0) {
        // Match upstream InferLlmModelType, including its legacy Gemma route.
        if (detokenize([105]) != '<start_of_turn>') {
          return _mediaSupport = unsupported;
        }
        final audioTokens = tokenize('<start_of_audio>', addSpecial: false);
        family = audioTokens.length == 1 && audioTokens.single == 256000
            ? 2
            : 4;
      }
      final imageProcessor =
          const {2, 4, 8, 9, 11, 12, 13}.contains(family) ||
          family == 1 && processor.genericImage;
      final audioProcessor =
          const {2, 4, 8}.contains(family) ||
          family == 1 && processor.genericAudio;
      final image =
          options.visionBackend != null &&
          declarations.vision &&
          imageProcessor;
      final audio =
          options.audioBackend != null && declarations.audio && audioProcessor;
      return _mediaSupport = _V1MediaSupport(
        image,
        audio,
        image &&
            family == 8 &&
            _library.providesSymbol(
              'litert_lm_conversation_optional_args_set_visual_token_budget',
            ),
      );
    } on LlamaUnsupportedException {
      return _mediaSupport = unsupported;
    } on LlamaModelException {
      return _mediaSupport = unsupported;
    }
  }

  void _validateMediaMessages(List messages) {
    var image = false, audio = false;
    for (final message in messages) {
      final content = (message as Map)['content'];
      final parts = content is Map ? [content] : content;
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is! Map) continue;
        image |= part['type'] == 'image';
        audio |= part['type'] == 'audio';
      }
    }
    if (!image && !audio) return;
    final support = _inspectMediaSupport();
    if (image && !support.image || audio && !support.audio) {
      throw LlamaUnsupportedException(
        'C API 1.0 media requires a configured encoder, a loaded-core modality declaration and a supported model processor; this model/runtime does not admit the requested image or audio input.',
      );
    }
  }
}

void _validateV1MediaPart(Map part, Object? role) {
  if (role != 'user' && role != 'assistant') {
    throw LlamaUnsupportedException(
      'C API 1.0 image/audio content requires a user or assistant message.',
    );
  }
  LiteRtLmV1ConversationSettings._keys(part, {'type', 'path', 'blob'});
  if (part.containsKey('path') == part.containsKey('blob')) {
    throw LlamaArgumentException(
      'Media requires exactly one encoded local path or base64 blob.',
    );
  }
  if (part.containsKey('path')) {
    final path = part['path'];
    if (path is! String || path.isEmpty || path.contains('\u0000')) {
      throw LlamaArgumentException(
        'Media local path must be nonempty without NUL.',
      );
    }
    final scheme = Uri.tryParse(path)?.scheme.toLowerCase();
    if (scheme != null &&
        scheme.isNotEmpty &&
        !(Platform.isWindows && scheme.length == 1)) {
      throw LlamaUnsupportedException(
        'C API 1.0 media requires a local file path; remote URLs and URI payloads are unsupported.',
      );
    }
    if (!File(path).existsSync()) {
      throw LlamaArgumentException('Media local file does not exist.');
    }
  } else {
    final blob = part['blob'];
    if (blob is! String ||
        blob.isEmpty ||
        !RegExp(
          r'^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$',
        ).hasMatch(blob)) {
      throw LlamaArgumentException(
        'Media blob must be nonempty standard base64 encoded file bytes.',
      );
    }
    try {
      if (base64Decode(blob).isEmpty) throw const FormatException();
    } on FormatException {
      throw LlamaArgumentException(
        'Media blob must encode nonempty file bytes.',
      );
    }
  }
}
