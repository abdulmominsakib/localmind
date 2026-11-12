# Ordinary default-native consumer and distributed AOT qualification

This fixture qualifies one reviewed core SHA on **macOS arm64 or Windows x64**.
It is separate from the historical native1 Windows registry matrix and the
native owner's candidate-selector campaigns. Track acceptance in
[#1762](https://github.com/leehack/llamadart/issues/1762); a native2 infrastructure
baseline does not close that issue or qualify native3.

Run the maintained `native-default-consumer-aot` local scenario with `--dry-run`
first. The direct interface is:

```sh
python3 test/fixtures/native_default_consumer_qualification/qualify.py \
  --core-root /absolute/reviewed/checkout \
  --expected-core-sha FULL_REVIEWED_SHA \
  --expected-native-tag v0.8.0-2 \
  --model /absolute/qwen2.5-1.5b-instruct-q4_k_m.gguf \
  --output /absolute/fresh-output --dry-run
```

Remove `--dry-run` only for an explicitly authorized heavy qualification. It
requires a clean exact-SHA checkout, pinned Flutter 3.47.1 / Dart 3.13.1,
a fresh output path outside the checkout, and the fixed 1,117,320,736-byte
Qwen2.5-1.5B fixture with SHA-256
`6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e`.
Dry-run reads source/arguments and prints a plan; it does not execute children,
read the model or SDK, or create output. Loader/runtime override environment
names are refused, including empty values. Supply a canonical path without
symlink/reparse ancestors; `/private/tmp` is the canonical macOS temp root.
`HOME` is preserved, never repurposed. Only owned temp and pub-cache paths change.

`--expected-native-tag` verifies the committed `llamaCppTag`; it never enters
hook configuration. The generated consumer config contains only the documented
`llamadart_native_runtimes: [llama_cpp]` filter. Native2 reports
`pipelineOnly: true` and `finalNative3Qualified: false`. Native3 can report
success only after all same-platform gates pass; independent acceptance and the
other platform's qualification remain separate. Owner publication must precede
native3 consumer pin work.

The driver exports every tracked source file to a fresh package tree, checks
its inventory against reviewed H, and uses a fresh public-hook acquisition.
It executes the public CPU0 baseline, active N4/M8/minHits1 ngram generation,
unload/reload, same-engine reuse and disposal in JIT and AOT. Both require the
128-token bound, full text parity and positive attempt/draft/accept counts.
The entire SDK `build/default/bundle` is copied, including hidden and nested
entries, outside all source/app roots. AOT runs from a distinct initially empty
CWD with a system-only PATH. Complete source/bundle inventories and child logs
are retained. POSIX children own a process group; Windows children are suspended
until attached to a kill-on-close job, then resumed. Cleanup waits for the
job to have no active processes. Timeouts terminate/reap the owned tree.
SIGINT/SIGTERM and Windows SIGBREAK use restored,
record-only local handlers. They never raise asynchronously, including at
cleanup entry. A final recorded-signal check follows restoration of all
previous handlers, so signals recorded during restoration also invalidate
the receipt. Signals after restoration and uncatchable termination are outside
that observation interval. Cancellation uses explicit safe checkpoints, and
child waits poll at most every 100 ms against one absolute deadline. No child
execution is retried. The Popen object is registered before its constructor
can spawn. Git preflight
uses the same bounded owned runner. Cancellation retains a failure receipt and
never qualifies the campaign. Uncatchable process termination cannot write a
receipt. Background-thread callers are refused before child creation.

Observers run after the public outcome. Windows reuses the maintained passive
module/IAT observer with pinned-SDK formatting only; macOS requires the reviewed consolidated single-image layout. It enumerates
dyld images, records their actual base/hash, and resolves self-owned registry,
model-loader, wrapper-loader and retained-query exports with `dladdr`. The
registry probe uses the emitted `package:llamadart/llamadart` asset, and the
generated wrapper-model binding's actual code-asset address must match its
resident self-export. This consolidated relation does not manufacture an
import row; split or mixed Apple runtime layouts fail closed. Code-asset resolution/getters
are explicitly labeled as potentially loading or initializing, after the first
passive snapshot. Query probing uses only an already-observed resident wrapper.
The retained `nextn(null)` must be false; the legacy query must exist for native2
and be absent for native3. Runtime modules and actual native symbol owners must
remain within the copied bundle for AOT, with no foreign native fallback.

The macOS archive must have exactly one regular root runtime member,
`libllamadart.dylib`, as verified for native2 and native3. Extra, missing, split
or nested raw members fail; Windows retains its split-module/IAT contract.
Checksums bind hook-cache archives to committed release pins; loaded Windows
DLLs must match their verified raw members exactly. macOS preserves each actual
whole-file hash. When whole-file bytes differ, the copied maintained comparator
requires complete ordered section metadata/bytes and UUID identity, equal
non-signature referenced payloads and dependency commands, and only the reviewed
self-ID/signature/LINKEDIT command differences. Its result deliberately makes
**no full-image identity, signature-validity, runtime-identity or transformation
cause claim**. Unsupported Mach-O formats/changes fail closed; the comparator
supports thin little-endian arm64 MH_DYLIB only.

The comparator and its 20 synthetic controls were copied unchanged from the
previous independently reviewed scoped identity parser. Their original hashes
are respectively `5fc55a616d82f381d7294379013604cf0437d5467898a842afc3a611828cd333`
and `1d9da55e961ebef8c4b212a3a3c0d2fb58a75e971210d703120ce7d338cf0bc5`.

Model-free source checks:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s test/fixtures/native_default_consumer_qualification -p 'test_*.py'
```

Synthetic controls establish driver/refusal behavior only. Real SDK analysis,
compilation, macOS and Windows pipelines, exact final-native3 runs and an
independent adversarial review are required before acceptance. A partial run
retains `completed: false`; it cannot qualify either platform.
