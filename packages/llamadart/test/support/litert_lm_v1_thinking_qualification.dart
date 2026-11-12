import 'dart:convert';

const thinkingModelSha256 =
    '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c';
const thinkingOutputCap = 1536;
const thinkingModelBytes = 2588147712;
const thinkingPrompt =
    'A train leaves at 9:40 and arrives at 13:05. How long is the trip? '
    'Think it through carefully before answering.';
const thinkingStart = '<|channel>thought\n';
const thinkingEnd = '<channel|>';
const thinkingEventPrefix = 'LITERT_V1_THINKING_EVENT ';

/// Exact input from the preserved legacy 768-token control, admitted prospectively.
const thinkingLegacyBaselineRender =
    '<|turn>system\n<|think|><turn|>\n<|turn>user\n'
    '$thinkingPrompt<turn|>\n<|turn>model\n';
const thinkingLegacyBaselineRenderSha256 =
    '0dc049145d2fc0987d1e5a637bb428eab3fa72f46517f785453e8207fed97ce2';

void requireThinkingBaselineInput(Map<String, Object?> input) {
  final expectedHex = utf8
      .encode(thinkingLegacyBaselineRender)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  if (input['rendered_prompt'] != thinkingLegacyBaselineRender ||
      input['rendered_prompt_utf8_hex'] != expectedHex ||
      input['rendered_prompt_sha256'] != thinkingLegacyBaselineRenderSha256) {
    throw StateError(
      'First baseline native rendering differs from the admitted legacy input; no generation is permitted.',
    );
  }
}

/// Checks the unchanged thinking-control E2E oracle, not arithmetic accuracy.
void requireThinkingResult({
  required int reasoningTokens,
  required String finalContent,
  required String? finish,
  required String settlement,
  int? budget,
}) {
  if (settlement != 'settled' ||
      finish != 'stop' ||
      finalContent.trim().isEmpty) {
    throw StateError(
      'Thinking generation must stop with final content and settled native work.',
    );
  }
  if (budget == null ? reasoningTokens <= 24 : reasoningTokens > budget + 2) {
    throw StateError(
      'Thinking token count failed the fixed unbounded/bounded oracle.',
    );
  }
}

/// Splits the service's existing channel assembly without trimming reasoning.
({String reasoning, String content}) splitThinkingOutput(String text) {
  final start = text.indexOf(thinkingStart);
  if (start < 0) return (reasoning: '', content: text);
  final end = text.indexOf(thinkingEnd, start + thinkingStart.length);
  if (end < 0 || text.indexOf(thinkingStart, end) >= 0) {
    throw StateError('Expected one complete assembled reasoning channel.');
  }
  return (
    reasoning: text.substring(start + thinkingStart.length, end),
    content:
        text.substring(0, start) + text.substring(end + thinkingEnd.length),
  );
}

void requireThinkingReuse(String baseline, String actual) {
  if (actual != baseline) {
    throw StateError(
      'No-budget reasoning/final bytes changed after a bounded turn or reload.',
    );
  }
}

void requireThinkingCancelled({
  required bool requested,
  required int receivedBytes,
  required String? finish,
  required String settlement,
}) {
  if (!requested ||
      receivedBytes == 0 ||
      finish != 'cancelled' ||
      settlement != 'settled') {
    throw StateError(
      'Cancellation must follow actual output and settle with the native cancelled cause.',
    );
  }
}

/// Strict local manifest entries; payload paths cannot escape the core folder.
List<({String name, int bytes, String sha256})> thinkingRuntimeManifest(
  String json,
) {
  final decoded = jsonDecode(json);
  if (decoded is! List || decoded.isEmpty) {
    throw const FormatException(
      'Runtime payload manifest must be a nonempty array.',
    );
  }
  final names = <String>{};
  return decoded
      .map((entry) {
        if (entry is! Map ||
            entry['name'] is! String ||
            !RegExp(
              r'^[A-Za-z0-9_.-]+\.dylib$',
            ).hasMatch(entry['name'] as String) ||
            (entry['name'] as String).contains('..') ||
            !names.add(entry['name'] as String) ||
            entry['bytes'] is! int ||
            (entry['bytes'] as int) <= 0 ||
            entry['sha256'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(entry['sha256'] as String)) {
          throw const FormatException(
            'Invalid, duplicate or unsafe runtime payload identity.',
          );
        }
        return (
          name: entry['name'] as String,
          bytes: entry['bytes'] as int,
          sha256: entry['sha256'] as String,
        );
      })
      .toList(growable: false);
}

const thinkingSuccessStages = [
  'identity',
  'loaded_contract',
  'boundaries',
  'loaded_before_generation',
  'unbounded_baseline_input',
  'unbounded_baseline_raw',
  'unbounded_baseline',
  'bounded_12_input',
  'bounded_12_raw',
  'bounded_12',
  'after_bounded_input',
  'after_bounded_raw',
  'after_bounded',
  'cancel_input',
  'cancel_raw',
  'cancel',
  'after_cancel_input',
  'after_cancel_raw',
  'after_cancel',
  'reload_unbounded_input',
  'reload_unbounded_raw',
  'reload_unbounded',
  'reload_bounded_12_input',
  'reload_bounded_12_raw',
  'reload_bounded_12',
  'disabled_context',
  'direct_reuse_prompt',
  'direct_reuse_raw',
  'direct_reuse_bounded_12',
  'loaded_after_generation',
  'input_recheck',
  'cleanup',
  'run_end',
];
