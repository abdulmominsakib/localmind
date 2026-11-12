import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:llamadart/llamadart.dart';

import 'decision/triage_flow.dart';

/// Runs a native CPU decision flow, reusing cached Hugging Face model files.
///
/// Set `GENKIT_DECISION_ENCODER` and `GENKIT_DECISION_HEAD` to use local files.
/// Otherwise the first run downloads a pinned 272 MB encoder and 106 MB head.
/// Pass a ticket as the first argument to replace the sample ticket.
Future<void> main(List<String> args) async {
  const revision = 'ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c';
  final decisions = await DecisionEngine.load(
    DecisionModel(
      encoder: ModelSource.parse(
        Platform.environment['GENKIT_DECISION_ENCODER'] ??
            'hf://fr0stbit3/laya-gguf/laya-Q4_K_M.gguf?revision=$revision',
      ),
      head: ModelSource.parse(
        Platform.environment['GENKIT_DECISION_HEAD'] ??
            'hf://fr0stbit3/laya-gguf/laya-head.safetensors?revision=$revision',
      ),
    ),
    params: const DecisionModelParams(device: ComputeDevice.cpu, threads: 4),
  );
  final ai = Genkit(isDevEnv: false);
  try {
    final triage = defineDecisionTriageFlow(ai, decisions);
    final result = await triage(
      args.isEmpty
          ? 'We were billed twice for March. Please refund the duplicate today.'
          : args.first,
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } finally {
    try {
      await decisions.dispose();
    } finally {
      await ai.shutdown();
    }
  }
}
