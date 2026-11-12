# LiteRT-LM C API 1.0 consumer preparation

The public lazy client, default services and speech worker now select legacy
runtimes or admitted C API 1.0.x through shared discovery. Unknown, malformed or
future C API versions are refused before engine calls. Owner pins and the
companion select published v0.19.1-2; C API 1 first shipped in core and
companions `0.18.0` (#1677).
[Current adoption coverage and gates](litert_lm_v1_adoption.md) describe the
selected implementation; [the migration guide](../MIGRATION.md) covers upgrades.

## Historical preparation snapshots

The remainder records earlier adapter slices and their evidence. Statements
about missing families, public refusal or unselected dispatch describe those
snapshots, not the current public client or release qualification.

The first adapter targets exact owner candidate `94db8c5` with upstream
`771b06e1` (`v0.19.0`). It binds only explicit status-return/output-parameter
signatures from that candidate's `c/engine.h`, checks version 1.0.x and required
exports before operations, and reads thread-local errors synchronously before
cleanup. It preserves typed diagnostics and path redaction. C API 1.0 must
never pass through the legacy typedefs or callback proxy.

| Family | Preparation status | Adoption gate |
| --- | --- | --- |
| Version/status errors | Explicit 1.0.x probe; older/future/missing exports refuse | Both directions of artifact skew |
| Settings/engine | CPU, bounded context/threads, explicit isolated cache, owned engine | More settings/backends and platform evidence |
| Session/raw text | Fresh greedy synchronous session, explicitly no template application; UTF-8 copy, response and partial-failure cleanup | Production worker dispatch and cancellation transport |
| Conversations/history/tools | Internal one-at-a-time text conversation with native history; no tool API | Production dispatch, history/tool policy and broader models |
| Callback streaming/termination | Internal owner-proxy ABI 2 copied JSON, final+drain ownership, cancel/delete/recreate | Production worker transport and full-family/platform qualification |
| ASR | Public compatibility refusal remains | ABI-v1 bridge routing, model-family and lifecycle controls |
| Embeddings/schema | Public compatibility refusal remains | Regenerated/audited signatures, capabilities and model regressions |
| Hook/SPM/inventory | No changes | Qualified owner publication, TopK removal, bidirectional companion checks |

Raw text generation blocks its owning isolate. It exposes no cancellation or
cross-isolate handles. Every request owns and deletes its own session; engine
reload retains the previous engine if candidate creation fails. Disposal is
final and idempotent. This bounded preparation API cannot establish an app
feature, tool-loop safety, exact usage, async cancellation or broad GPU support.

Tests compile a versioned fixture with live-object counters and inject failures
at each creation/status/output stage. The existing public ABI guard and its
legacy tests remain separate. Any real-model receipt must identify the exact
candidate/model hashes and actual backend; fixture success is not inference
qualification. Source stays draft until remaining families are migrated.

## Initial macOS arm64 evidence

Candidate owner `94db8c5`, library SHA-256
`6ae8a0038f4fa71a9403ccdb91bf4bf71cd792beb44191f2bcc187e6ef70d31d`,
with Qwen3-0.6B SHA-256
`555579ff2f4fd13379abe69c1c3ab5200f7338bc92471557f1d6614a6e5ab0b4`:
CPU engine creation and two fresh raw-text sessions execute through this
adapter. A direct native C API reference emits identical text (`2`) for the
recorded arithmetic prompt; this is ABI/lifetime parity, not arithmetic
correctness or public backend qualification. The candidate rejects the declared
Greedy sampler enum with UNIMPLEMENTED; use TopP with top-k 1 and temperature 0,
as the owner qualification tools do. The original unsuccessful probes are
retained separately from passing parity receipts.

## Internal conversation preparation

The next slice targets upstream `83ce6067f2e2a3fb697556928f93936693ded971`
and the owner `bf4e1188e1135152a8ce4e7dc057c13041cf18a1` candidate (PR92's
source-equivalent main tree). It adds an unexported conversation implementation
without changing public dispatch, shipped pins, legacy bindings or companions.
It requires the version-checked 1.0 runtime plus owner `stream_proxy_*` exports
and callback ABI **2**, rejecting old, missing or unknown proxy ABIs before
allocating a conversation. It never registers a Dart listener for upstream's
borrowed opaque chunks. The owner proxy copies each string before the native
callback returns; Dart copies those owned strings and frees both text and error.

`openConversation` owns one child of the loaded CPU engine. `sendText` accepts
only text and returns a turn whose `chunks` stream contains raw native message
JSON. `done` carries the authoritative finish reason or error; it can be awaited
without a chunks subscription. Finish-reason ABI 1 is optional: missing or
unknown versions yield `unknown`, never a guessed cause. This slice provides no
media, tools, schema, ASR, embeddings, single-threaded execution or raw-session
asynchronous generation.

A turn keeps its input, native proxy and `NativeCallable.listener` alive until
the final callback is received **and** `conversation_wait_until_done` succeeds.
A nonfinal error does not release callbacks. Status failures read thread-local
errors synchronously on the calling thread; stream failures use the copied
callback error, with existing path and URL redaction. Canonical CANCELLED text
is treated as normal cancellation only when the native finish-reason extension
independently reports cancellation.

Cancellation requests do not wait. Further copied chunks are freed and
suppressed while native work finishes. The child is deleted after final+drain;
its handle is never reused, even if the cancellation request failed. Create a
new conversation for another turn. A normal completed conversation can accept
another turn, preserving native history. Repeated closing of an old child
cannot detach a newer child from its parent. Engine reload, direct raw-session
generation and disposal refuse while any child exists. Close an idle child or
cancel and await an active one first.

No timer closes a callback. A missing final callback retains its resources.
Failed native drain quarantines the entire child/parent family and refuses
reuse, close, reload and disposal, since callback quiescence is unproved. This
conservative failure can retain native resources and keep its isolate alive;
production worker-exit/recovery policy remains an adoption gate. The current
owner proxy also cannot distinguish absent text from allocation failure, so
this preparation does not establish lossless behavior under native OOM.

Model-free tests use foreign-thread callbacks that overwrite borrowed chunk
storage immediately, lifecycle counters, setup/start/cancel/drain failures and
postcancel callbacks. The failed-drain control runs in its own process so it
can verify retained callbacks and then exit without pretending they are safe to
free. Optional candidate tests live in
`test/integration/litert_lm_v1_candidate_test.dart` (`local-only`); set
`LLAMADART_LITERT_V1_LIBRARY`, `LLAMADART_LITERT_V1_MODEL` and the corresponding
`_SHA256` variables. They check normal history reuse, cancellation and fresh
conversation creation with CPU two-thread decoding. Their output is lifecycle
evidence, not model-semantic, leak-freedom or public-runtime qualification.
