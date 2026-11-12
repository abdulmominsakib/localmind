# Experimental bounded text sessions

Import `package:genkit_llamadart/experimental.dart` and register
`LlamaDartBidiPlugin`. This registers `llamadart-bidi/<name>` under Genkit's
experimental `bidiModel` action type. Ordinary `llamaDart` model registration and
generation are unchanged.

```dart
// ignore_for_file: experimental_member_use
import 'dart:async';
import 'package:genkit/experimental.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_llamadart/experimental.dart';
import 'package:genkit_llamadart/genkit_llamadart.dart';

Future<void> main() async {
  final plugin = LlamaDartBidiPlugin(
    models: const [LlamaModelDefinition(name: 'chat', modelPath: '/models/chat.gguf')],
    maxSessions: 1, maxTurns: 2,
  );
  final ai = Genkit(plugins: [plugin], isDevEnv: false);
  try {
    final session = await ai.generateBidi(model: 'llamadart-bidi/chat');
    final chunks = StreamIterator(session.stream);
    try {
      for (final prompt in ['Say hello.', 'What did I ask you to say?']) {
        session.send(prompt);
        if (!await chunks.moveNext()) break;
        print(chunks.current.text);
      }
      await session.close();
      while (await chunks.moveNext()) {}
    } finally {
      await session.close();
      await chunks.cancel();
    }
  } finally {
    await plugin.dispose();
    await ai.shutdown();
  }
}
```

## Contract and bounds

Each session owns a fresh runtime and complete history. There is no shared model
registry context or KV persistence between sessions. Supply one nonempty user
text message per turn, or a string through `session.send`. An optional initial
system message and generation config apply for the whole session. Caller-supplied
history, per-turn config, tools, documents, media and structured output reject.
Only confirmed native llama.cpp multi-turn runtimes are supported; Web, LiteRT-LM
and unverified custom runtimes reject explicitly.

The adapter reuses ordinary chat generation. It buffers each turn and publishes
one complete chunk containing visible text and any reasoning, with `custom.turn`
and `custom.finishReason`. Length-limited answers remain explicitly marked
`length`; they are not exact completed-conversation checkpoints. Historical
reasoning follows the [normal omission policy](reasoning-history.md).

| Limit | Default |
| --- | --- |
| Active/opening/closing sessions | 2 across registered models |
| Waiting turns | 2 per session, excluding the active turn |
| Total accepted turns | 32; normal closure after the final completed turn |
| History and pending input | 32,768 characters, including reasoning output |
| Output per turn | 8,192 characters and a requested token cap of 512 |
| Requested output tokens when omitted | 256, reduced to the configured cap |
| Idle lifetime | 1 minute when no active/queued work exists |
| Total lifetime | 10 minutes, including active generation |

Exceeding a bound fails the session and discards queued/unpublished output.
Genkit 1.0's input transport and output callbacks have no credit-based or
awaitable backpressure. The adapter continuously drains inputs into its bounded
queue and fails on overflow; total emitted output is bounded by the turn and
character budgets. **Await one response before sending another turn.** This does
not bound memory allocated by a caller that floods Genkit's transport before
yielding, nor can it police caller-owned stream buffers.

Closing input drains accepted turns. Await stream completion to know native
cleanup has settled. A cancellation token, lifetime expiration or plugin disposal
cancels that session's generation and waits for its resources; other sessions are
unchanged. Cancelling only the output subscription does not cancel Genkit's input
transport. Explicitly close/cancel abandoned sessions; idle/lifetime limits are
the fallback. No continuous real-time audio, session resume, automatic eviction
or persistent conversation storage is provided.

## Dependency and qualification policy

This entry point intentionally uses the published Genkit Dart 1.0.0 experimental
API. Genkit allows that API to change in minor releases; applications should pin
and qualify their compatible Genkit release. The stable entry point does not
export the experimental plugin. Both the minimum SDK/dependency lane and current
dependency lane analyze and exercise the registration path.

Deterministic tests cover real `generateBidi` lookup, two independent sessions,
multi-turn history, unsupported input/capabilities, admission and queue/output
bounds, cancellation, idle/lifetime expiration, reused factories and disposal.
The bounded real smoke uses checksum-pinned SmolLM2-135M Q2_K, llamadart 0.13.0,
native `v0.6.0-3` on macOS arm64 CPU. It verifies two actual native chat calls with
the first answer present in the second call. This is protocol/lifecycle evidence,
not a model-quality claim or Web/mobile/GPU qualification.

The same bounded proof passed again on 2026-10-18 with published llamadart
0.15.0/native `v0.7.0-1` on macOS arm64 CPU. This retains the original fixture
and scope; it does not extend qualification to other devices or backends.

```bash
LLAMADART_RUN_BIDI_PROOF=1 LLAMADART_AUTO_DOWNLOAD_TEST_MODELS=1 \
dart test test/integration/genkit/runtime/real_model_bidi_test.dart -j 1
dart run example/genkit_llamadart_bidi_example.dart
```
