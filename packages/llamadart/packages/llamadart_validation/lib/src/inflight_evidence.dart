/// Evidence predicates shared by execution and catalog-6 journal import.
/// Timer delivery alone never proves that native decoding was interrupted.
bool cancellationObserved(Map evidence, {bool allowAbort = false}) {
  final control = evidence['uncancelled_control'];
  if (control is! Map) return false;
  final content = evidence['content'];
  final fullContent = control['content'];
  if (content is! String ||
      fullContent is! String ||
      !fullContent.startsWith(content)) {
    return false;
  }
  final controlMetrics = control['metrics'];
  final metrics = evidence['metrics'];
  final full = controlMetrics is Map
      ? controlMetrics['native_decode_tokens']
      : null;
  final cancelled = metrics is Map ? metrics['native_decode_tokens'] : null;
  final nativeInterruption =
      full is num &&
      full.isFinite &&
      cancelled is num &&
      cancelled.isFinite &&
      cancelled > 0 &&
      cancelled < full;
  // EOF-gated output may be empty after real decoding. Zero decoded tokens,
  // a cancelled timer or a shortened wall duration cannot qualify that case.
  return nativeInterruption ||
      allowAbort &&
          content.isNotEmpty &&
          evidence['cancel_abort_observed'] == true;
}

bool _cleanEnd(Object? value, {bool requireText = false}) =>
    value is Map &&
    value['error_type'] == null &&
    value['stream_completed'] == true &&
    value['completion_order_valid'] == true &&
    value['content'] is String &&
    (!requireText || (value['content'] as String).trim().isNotEmpty) &&
    value['tool_call_deltas'] is List &&
    (value['tool_call_deltas'] as List).isEmpty;

/// The second request must be issued and settle before the first stream ends.
bool overlapWindowObserved(Map evidence) {
  final timeline = evidence['timeline_ms'];
  if (timeline is! Map) return false;
  final issued = timeline['second_issued'];
  final ended = timeline['second_ended'];
  final firstEnded = timeline['first_ended'];
  return evidence['second_issued'] == true &&
      evidence['first_ended_before_second_issued'] == false &&
      evidence['first_cancelled_before_second_issued'] == false &&
      issued is num &&
      issued.isFinite &&
      issued >= 0 &&
      ended is num &&
      ended.isFinite &&
      ended >= issued &&
      firstEnded is num &&
      firstEnded.isFinite &&
      ended <= firstEnded;
}

/// Rejects unsupported success claims without reinterpreting older catalogs.
bool validInflightEvidence(
  String id,
  Map evidence, {
  required num deadlineMs,
  bool allowAbort = false,
}) {
  final recovery = evidence['recovery'];
  if (!_cleanEnd(recovery, requireText: true) ||
      (recovery as Map)['cancel_requested'] != false) {
    return false;
  }
  if (id == 'C08.cancel') {
    final duration = evidence['cancel_to_done_ms'];
    return evidence['cancel_requested'] == true &&
        cancellationObserved(evidence, allowAbort: allowAbort) &&
        _cleanEnd(evidence['uncancelled_control'], requireText: true) &&
        (evidence['uncancelled_control'] as Map)['cancel_requested'] == false &&
        (_cleanEnd(evidence) ||
            allowAbort && evidence['cancel_abort_observed'] == true) &&
        duration is num &&
        duration.isFinite &&
        duration >= 0 &&
        duration <= deadlineMs;
  }
  if (id == 'C08.overlap') {
    final second = evidence['second'];
    final deltas = evidence['first_deltas_after_second_ended'];
    return overlapWindowObserved(evidence) &&
        second is Map &&
        second['state_exception'] == true &&
        second['error_type'] == 'LlamaStateException' &&
        second['content'] == '' &&
        second['stream_completed'] == false &&
        deltas is int &&
        deltas >= 1 &&
        _cleanEnd(evidence['first']);
  }
  return false;
}
