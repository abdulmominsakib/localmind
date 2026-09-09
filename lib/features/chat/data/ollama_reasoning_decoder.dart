typedef OllamaTextPart = ({String text, bool isReasoning});

/// Legacy Ollama models may return a leading `<think>` block in content.
/// Native `message.thinking` takes precedence. Only a leading block is parsed,
/// so tags quoted later in an ordinary answer remain ordinary answer text.
class OllamaReasoningDecoder {
  String _pending = '';
  bool _checkedPrefix = false;
  bool _inReasoning = false;

  List<OllamaTextPart> add(String text, {required bool nativeThinking}) {
    _pending += text;
    if (nativeThinking) {
      _checkedPrefix = true;
      _inReasoning = false;
      return flush();
    }
    if (!_checkedPrefix) {
      final trimmed = _pending.trimLeft();
      const opening = '<think>';
      if (opening.startsWith(trimmed) && trimmed != opening) return [];
      _checkedPrefix = true;
      if (trimmed.startsWith(opening)) {
        _inReasoning = true;
        _pending = trimmed.substring(opening.length);
      }
    }
    if (!_inReasoning) return flush();

    const closing = '</think>';
    final end = _pending.indexOf(closing);
    if (end >= 0) {
      final reasoning = _pending.substring(0, end);
      final answer = _pending.substring(end + closing.length);
      _pending = '';
      _inReasoning = false;
      return [
        if (reasoning.isNotEmpty) (text: reasoning, isReasoning: true),
        if (answer.isNotEmpty) (text: answer, isReasoning: false),
      ];
    }
    // Keep only a possible partial closing tag across stream boundaries.
    var keep = 0;
    for (var length = 1; length < closing.length; length++) {
      if (_pending.endsWith(closing.substring(0, length))) keep = length;
    }
    final ready = _pending.substring(0, _pending.length - keep);
    _pending = _pending.substring(_pending.length - keep);
    return [if (ready.isNotEmpty) (text: ready, isReasoning: true)];
  }

  List<OllamaTextPart> flush() {
    final text = _pending;
    _pending = '';
    return [if (text.isNotEmpty) (text: text, isReasoning: _inReasoning)];
  }
}
