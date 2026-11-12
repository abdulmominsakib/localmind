---
title: Decision models for typed answers
sidebar_label: Decision models
description: Answer typed choice, score, and yes/no questions about a state with Laya-style encoder decision models on llama.cpp.
---

`DecisionEngine` answers typed questions about a state with a Laya-style
decision model: a ModernBERT encoder GGUF, run by llama.cpp, plus a small
decision head stored as safetensors. Each question takes one encoder pass and
generates no text. Requests and responses follow the `system_one` format of
[Laya](https://huggingface.co/convaiinnovations/laya), so most questions
written for Laya carry over unchanged; [Laya wire format](#laya-wire-format)
and [Known limits](#known-limits) list the exceptions.

Use it for classification-style decisions where a chat model would be slow or
would need output parsing: routing a ticket, rating urgency, or checking a
yes/no condition. The
[Basic App decision example](../examples/basic-app) runs the
ticket questions below from the command line, as
[typed keys](#typed-questions), and the
[Laya Tetris example](../examples/laya-tetris) plays real-time Tetris with it
in a Flutter app.

## Current support matrix

| Runtime | `DecisionEngine` |
| --- | --- |
| Native llama.cpp / GGUF | Experimental: ModernBERT (`modern-bert`) encoder GGUF plus a Laya decision head; validated on macOS (Metal, CPU), other native platforms untested |
| WebGPU / GGUF | Experimental, with bridge assets `v0.1.47+` (apiVersion 1), which the default pin includes; checked only in headless Chromium on macOS. Older assets report unsupported. See [Web](#web) |
| Native LiteRT-LM / `.litertlm` | Unsupported: `DecisionEngine.load` throws `LlamaUnsupportedException` |
| LiteRT-LM Web | Unsupported: `DecisionEngine.load` throws `LlamaUnsupportedException` |

The head runs on CPU when the model is loaded on CPU, and on the model's GPU
when a device of its backend is available, otherwise on CPU.
`decisions.info.deviceName` names that device, such as `CPU` or `MTL0`; on Web,
the bridge reports its own device name.

## Load a decision model

The reference assets are the community GGUF conversion
[`fr0stbit3/laya-gguf`](https://huggingface.co/fr0stbit3/laya-gguf): the
`laya-Q8_0.gguf` backbone (421 MB) and the `laya-head.safetensors` head
(106 MB, F32). Load the backbone into a `LlamaEngine`, fetch the head through
the engine's model download manager (native only; on Web, pass a URL as shown
in [Web](#web)), then load the head with `DecisionEngine.load`:

```dart
final engine = LlamaEngine(LlamaBackend());
const repoId = 'fr0stbit3/laya-gguf';
const revision = 'ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c';
await engine.loadModelSource(
  ModelSource.huggingFace(
    repoId: repoId,
    revision: revision,
    filePath: 'laya-Q8_0.gguf',
  ),
  modelParams: const ModelParams(contextSize: 512),
);
final head = await engine.modelDownloadManager.ensureModel(
  ModelSource.huggingFace(
    repoId: repoId,
    revision: revision,
    filePath: 'laya-head.safetensors',
  ),
);

final decisions = await DecisionEngine.load(engine, headPath: head.filePath);
```

The head runs its own encoder context of `decisions.info.maxTokens` tokens and
does not use the engine's context, so a small `contextSize` saves memory. On
the CPU, `ModelParams.numberOfThreadsBatch` sets the threads of both the
encoder and the head (llama.cpp uses 4 when it is 0); `numberOfThreads` does
not affect decisions.

`DecisionEngine.load` checks that the model is a `modern-bert` encoder with
CLS, SEP and MASK tokens, that its hidden size matches the head, and that
every head tensor has the expected shape. Another kind of model fails with
`LlamaUnsupportedException`; a head file or config that cannot be read, is
malformed, or does not fit the encoder fails with `LlamaModelException` naming
the problem.

## Ask questions

`systemOne` answers every question about one state:

```dart
final result = await decisions.systemOne(
  state: {
    'from': 'user@acme.com',
    'subject': 'Duplicate charge on invoice #4411',
    'body': 'We were billed twice for March. Please refund the duplicate.',
  },
  questions: {
    'department': DecisionQuestion.choice(
      'Which department should handle this request?',
      criteria: {
        'billing': 'invoices, payments, refunds',
        'technical': 'bugs, outages, system errors',
        'other': null,
      },
    ),
    'urgency': DecisionQuestion.score(
      'How urgent is this request?',
      levels: ['not urgent', 'soon', 'critical'],
    ),
    'refund': DecisionQuestion.noul('Does the user request a refund?'),
  },
);

final department = result.choices['department']!;
print('${department.choice}: ${department.probabilities}');
print(result.scores['urgency']!.score);
print(result.nouls['refund']!.noul);
```

There are three question types:

| Question | Options | Answer |
| --- | --- | --- |
| `DecisionQuestion.choice` | `criteria` maps each label to a description; `null` or `''` means no description | `ChoiceAnswer.choice` is the most probable label; `probabilities` maps every label, in option order |
| `DecisionQuestion.score` | `levels` in order, level 0 first | `ScoreAnswer.score` is the expected level, the probability-weighted mean of the level indices; `legend` and `probabilities` are keyed `'0'`, `'1'`, and so on |
| `DecisionQuestion.noul` | optional `whenTrue` and `whenFalse` descriptions | `NoulAnswer.noul` is the probability that the statement is true |

Every answer also has `confidence`, from 0 to 1, and `actProbability`, Laya's
`action.act_probability`. Choice and score confidence is `1 - H(p) / ln K`,
one minus the entropy of the answer's `K` probabilities divided by its
maximum; noul confidence is `max(noul, 1 - noul)`. Values are unrounded
doubles; Laya rounds its JSON to 4 decimals.

The state is sent as text when it is a `String`, and as JSON text otherwise.
Instructions are text, or a JSON-like value sent as Laya's
`json.dumps(value, ensure_ascii=True)` text. States, criteria, levels and
descriptions must be JSON-like: `null`, `bool`, `num`, `String`, or a `List`
or `Map` with `String` keys of such values. A request needs at least one
question, question ids must be non-empty, and score levels must be non-empty.
Invalid questions throw `LlamaDecisionException` before the model runs.

## Laya wire format

`DecisionQuestion.fromJson` parses Laya's `{"type", "instructions",
"criteria"}` question format, and `DecisionResult.toJson` returns Laya's
`{model, answers, usage}` response:

```dart
final category = DecisionQuestion.fromJson({
  'type': 'choice',
  'instructions': 'Which product area is affected?',
  'criteria': ['billing', 'login', 'performance'],
});
final area = await decisions.systemOne(
  state: 'The dashboard takes a minute to load.',
  questions: {'area': category},
);
print(jsonEncode(area.toJson()));
```

A list of choice labels becomes labels without descriptions, as in Laya.
`fromJson` is stricter than Laya elsewhere: score `criteria` must be a list,
and noul `criteria` must be `null` or a map with optional `true` and `false`
descriptions.

## Batches

`systemOneBatch` answers several states in one backend call. Every request is
validated and tokenized before the model runs, and results come back in
request order:

```dart
final results = await decisions.systemOneBatch([
  DecisionRequest(
    state: 'The login page returns a 500 error.',
    questions: {
      'outage': DecisionQuestion.noul('Is a service down?'),
    },
  ),
  DecisionRequest(
    state: 'Can I get a discount for a yearly plan?',
    questions: {
      'outage': DecisionQuestion.noul('Is a service down?'),
    },
  ),
]);
for (final result in results) {
  print(result.nouls['outage']!.noul);
}
```

`usage.inputTokens` counts the encoded tokens of each request;
`usage.outputTokens` is always 0.

## Typed questions

With string ids, each read looks up an id, as in
`result.choices['department']!`, and a choice comes back as its label. A typed
key holds a question with its id, and reading an answer through the key gives
a typed value, such as an enum. Build a request's questions from keys with
`DecisionKey.questionsOf`, then read each answer with `answerOf`:

```dart
enum Department { billing, technical, other }

final department = ChoiceKey.enumOf(
  'department',
  'Which department should handle this request?',
  criteria: {
    Department.billing: 'invoices, payments, refunds',
    Department.technical: 'bugs, outages, system errors',
    Department.other: null,
  },
);
final urgency = ScoreKey.of(
  'urgency',
  'How urgent is this request?',
  levels: ['not urgent', 'soon', 'critical'],
);
final refund = NoulKey.of('refund', 'Does the user request a refund?');

final result = await decisions.systemOne(
  state: 'We were billed twice for March. Please refund the duplicate.',
  questions: DecisionKey.questionsOf([department, urgency, refund]),
);
final Department route = result.answerOf(department).value;
print('$route ${result.answerOf(urgency).score} ${result.answerOf(refund).noul}');
```

Keys build ordinary questions, so the model sees the same sequences as with
string ids, and `answers`, `choices`, `scores`, `nouls` and `toJson` still
work on the result. `questionsOf` keeps the order of the keys and throws
`LlamaDecisionException` when two keys share an id.

| Key | Built from | `answerOf` gives |
| --- | --- | --- |
| `ChoiceKey.enumOf` | enum values mapped to descriptions; the model sees `Enum.name`, or `label(value)` when given | `ChoiceOf<E>` |
| `ChoiceKey.of` | a list of any values, with `label(value, index)` and an optional `describe(value)` | `ChoiceOf<T>` |
| `ChoiceKey.labels` | labels mapped to descriptions | `ChoiceOf<String>` |
| `ChoiceKey(id, question, value: ...)` | a `ChoiceQuestion` and a function from label to value | `ChoiceOf<T>` |
| `ScoreKey.of` or `ScoreKey(id, question)` | levels, or a `ScoreQuestion` | `ScoreAnswer` |
| `NoulKey.of` or `NoulKey(id, question)` | optional true and false descriptions, or a `NoulQuestion` | `NoulAnswer` |

`ScoreAnswer.levelProbabilities` lists the level probabilities from level 0.

With values of more than one enum type, `ChoiceKey.enumOf` infers a shared
supertype such as `Enum`, with no diagnostic. Write the type argument, as in
`ChoiceKey.enumOf<Department>(...)`, to make a value of another type a compile
error.

### Choice values

`ChoiceKey.of` takes its options as a list of values of any type.
`label(value, index)` gives the text the model sees for each option, and
`describe(value)` its description. `ChoiceKey.labels` keeps the labels
themselves as the values:

```dart
final plans = [
  (name: 'Starter', seats: 5),
  (name: 'Team', seats: 50),
  (name: 'Enterprise', seats: 1000),
];
final plan = ChoiceKey.of(
  'plan',
  'Which plan fits this customer?',
  options: plans,
  label: (plan, _) => plan.name,
  describe: (plan) => 'up to ${plan.seats} seats',
);
final tone = ChoiceKey.labels(
  'tone',
  'What is the tone of the message?',
  criteria: {'positive': null, 'neutral': null, 'negative': null},
);

final result = await decisions.systemOne(
  state: 'We are 30 people and want to move the whole team over.',
  questions: DecisionKey.questionsOf([plan, tone]),
);
final chosen = result.answerOf(plan);
print('${chosen.value.seats} seats, option ${chosen.index}');
print(chosen.optionProbabilities);
final String toneLabel = result.answerOf(tone).value;
print(toneLabel);
```

`ChoiceOf` has the chosen option's `value`, `label` and `index`, its position
among the options, and `optionProbabilities` in option order. Options with
equal values stay separate, and `index` tells them apart. `ChoiceKey.of` and
`ChoiceKey.enumOf` throw `LlamaDecisionException` when two options get the same
label.

For a question parsed from JSON, pass it to a key with a value function:

```dart
final parsed = DecisionQuestion.fromJson({
  'type': 'choice',
  'instructions': 'Which department should handle this request?',
  'criteria': ['billing', 'technical', 'other'],
});
final department = ChoiceKey(
  'department',
  parsed as ChoiceQuestion,
  value: Department.values.byName,
);
```

The value function runs for every label when the key is built, so a label
that names no enum value throws `ArgumentError` before the model runs.
`ScoreKey` and `NoulKey` wrap a parsed `ScoreQuestion` or `NoulQuestion` the
same way.

### Reading answers

`answerOf` never returns `null`, and there is no `tryAnswerOf`. A result from
`DecisionEngine` answers every question of its request, so reading it with a
key that built the request always finds its answer. For a result that may
lack an answer, such as one built by hand, check
`result.answers.containsKey(key.id)` first.

Read each result with the key object that built its request. A result from
`DecisionEngine` records its questions, and `answerOf` throws
`LlamaDecisionException` when the question under the key's id is not that
key's own question object. That happens with a key whose question built
another request of a batch, a key built again (for example by a getter), a
question parsed back from JSON, and a result sent to another isolate without
its keys; send the keys and the result in one message, or read the result
before sending it. One key can build several requests of a batch and read
each of their results. Keys that wrap one shared question object read each
other's results, so give each key its own question when their values differ.
A `DecisionResult` built without `questions`, such as a typical test fake,
records none; `answerOf` then checks only that the answer exists, its kind,
and its labels or levels.

### When to keep string ids

Keys are optional, and both paths send the same sequences. String ids and
`DecisionQuestion` fit better when:

- questions and answers are only data, such as a question set read with
  `DecisionQuestion.fromJson` whose answers leave through `toJson()`, and no
  code reads a particular answer;
- code treats every answer alike, for logging or display;
- the code that reads a result has the result but not the keys that built its
  request.

A switch over the sealed answer types covers every kind:

```dart
for (final MapEntry(key: id, value: answer) in result.answers.entries) {
  final text = switch (answer) {
    ChoiceAnswer(:final choice) => choice,
    ScoreAnswer(:final score) => score.toStringAsFixed(2),
    NoulAnswer(:final noul) => noul.toStringAsFixed(2),
  };
  print('$id: $text');
}
```

## Capabilities and model info

`DecisionEngine.capabilitiesFor(engine)` reports whether a head can load on the
engine now. Probe it after the backbone is loaded: without a model, it reports
that a model must be loaded first. With a model on Web, bridge assets without
the decision API, or with another decision API version, report unsupported and
name the assets needed.

`decisions.info` describes the loaded model: `hiddenSize`, the sequence limit
`maxTokens`, the question-and-options budget `headMaxTokens`, and the
`deviceName` the head runs on.

## Lifecycle

- A `DecisionEngine` belongs to the model that was loaded when it was created.
  Unloading or replacing that model, or disposing the engine, frees the head.
  Later calls throw `LlamaStateException`, and so do calls running at the time
  unless their sequences already reached the backend; those finish on the old
  model. Load a new `DecisionEngine` after loading a model.
- `dispose()` frees the head once in-flight calls finish. It is idempotent,
  keeps the `LlamaEngine` and its model loaded, and later calls throw
  `LlamaStateException`.
- Several `DecisionEngine`s can share one model, for example the base head and
  a fine-tuned one.
- Dispose decision engines before the `LlamaEngine`:

```dart
await decisions.dispose();
await engine.dispose();
```

## Official checkpoint

The official checkpoint
[`convaiinnovations/laya`](https://huggingface.co/convaiinnovations/laya)
ships `model.safetensors` with the encoder and head together, F16 head
tensors, and no `laya.config` metadata. It works as a head file when its
`rl_agent_config.json` is passed as `configPath`; the `encoder.*` tensors are
ignored, and the backbone still comes from a GGUF such as `laya-Q8_0.gguf`:

```dart
final official = await DecisionEngine.load(
  engine,
  headPath: '/models/laya/model.safetensors',
  configPath: '/models/laya/rl_agent_config.json',
);
```

## Web

On Web, `DecisionEngine` runs through the decision API (apiVersion 1) of the
llama.cpp WebGPU bridge, which `llama-web-bridge-assets` `v0.1.47+` and the
default pin include. With older assets, `capabilitiesFor` reports unsupported
and `DecisionEngine.load` throws `LlamaUnsupportedException`. LiteRT-LM Web
models report unsupported too.

- `headPath` and `configPath` are URLs, resolved against the document base
  URL, so a `<base href>` applies. The engine's model download manager is not
  available on Web; pass the head's URL instead:

  ```dart
  final head = ModelSource.huggingFace(
    repoId: 'fr0stbit3/laya-gguf',
    revision: 'ce2afdc0a8766af56a29a22dcf4a781e1f5c7d3c',
    filePath: 'laya-head.safetensors',
  );
  final decisions = await DecisionEngine.load(
    engine,
    headPath: head.resolvedUri!.toString(),
  );
  ```

- The bridge downloads the head into its in-memory file system, so peak memory
  includes the whole head file. The page fetches `configPath` and passes its
  text to the bridge; a config that cannot be fetched throws
  `LlamaModelException`.
- The head runs on WebGPU when the model loaded with GPU layers and on the
  bridge CPU otherwise.
- Web numbers cannot tell `30.0` from `30`. In a state, instructions, criteria,
  levels or descriptions that are not a `String`, an integral `double` is
  written as an `int`: `{'seats': 30.0}` becomes `{"seats": 30}`, where native
  and Laya write `{"seats": 30.0}`. The model reads different tokens, so
  answers can differ from native. When that matters, pass the value as a
  `String` you encode yourself.
- A bridge that restarts its runtime, for example when its worker fails during
  a call, frees its heads. Calls then throw `LlamaStateException`; load the
  `DecisionEngine` again.
- On the bridge CPU (no GPU layers), `laya-Q8_0.gguf` misses the parity
  tolerances on one of Laya's 24 fixture questions, with the same top option;
  the drift comes from the bridge's WASM CPU Q8_0 path. An F16 backbone, or GPU
  layers with either backbone, stays within them. The design doc's
  [Web check](https://github.com/leehack/llamadart/blob/main/doc/decision_engine.md#web-check)
  has the numbers.

## Accuracy and speed

Use an F32 backbone, or F16 on Metal, when answers must match Laya:
`laya-Q8_0.gguf` can change decisions, including clear ones. Timings and
parity measured on an Apple M4 Max are in the design doc's
[Measured](https://github.com/leehack/llamadart/blob/main/doc/decision_engine.md#measured)
section; other native platforms and GPU backends have not been measured.

## Known limits

- **512-token sequences.** Each question is encoded as
  `[CLS] question [SEP] options [SEP] state [SEP]`, cut to the head's
  `max_len` (512 for Laya). The state fills the remaining tokens and is
  truncated without an error.
- **Option budget.** The question text and options share `head_max_len` (192
  for Laya) tokens. Each option keeps up to 48 tokens after its marker; when
  the options leave fewer than 16 tokens, every option is cut to
  `max(4, (head_max_len - 16) ~/ K)` tokens. A question whose option markers
  still do not fit in the sequence throws `LlamaDecisionException`; use fewer
  options.
- **One encoder pass per question.** The state is re-encoded for every
  question, so cost grows with the number of questions.
- **No cancellation.** A `systemOne` or `systemOneBatch` call runs to
  completion.
- **Unicode normalization.** Input is not normalized. The Hugging Face
  tokenizer applies NFC, so NFD text, such as a decomposed `é`, can tokenize
  differently. Pass NFC text.
- **English only.** Parity is validated only for the English Laya checkpoint.
  Other ModernBERT-family checkpoints load if the checks pass, but have no
  parity evidence.
- **Quantization.** See [Accuracy and speed](#accuracy-and-speed). The
  published `laya-F16.gguf` matches a local F16 conversion on Laya's fixture
  but was not measured on the broader random set.
- **No U+0000.** A state, question or option text that contains U+0000 throws
  `LlamaDecisionException` on every backend, because Web bridge tokenization
  cuts the text there. A state that is not a `String` is sent as JSON, which
  escapes it.
- **Web numbers.** Web writes some numbers differently from native and Laya;
  see [Web](#web).
