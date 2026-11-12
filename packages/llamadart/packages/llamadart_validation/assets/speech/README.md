# Speech fixtures

`jfk.wav` is the familiar excerpt from John F. Kennedy's January 20, 1961
inaugural address, distributed as the `samples/jfk.wav` fixture in whisper.cpp.
The US federal government speech is public domain. Its exact bytes and reference
words are locked in `stt.json`; the reference ignores punctuation/case only.
No personal microphone recordings are included.

The Qwen3-ASR and Qwen3-TTS model/projector locks match the maintained chat-app
catalog. Model files are downloaded separately, never included in the app or
repository. Model licenses remain with the linked upstream repositories.

The fixture reference is a transcription oracle, not proof of exact-model
qualification. A failed transcription remains a failure; do not revise the
reference or threshold to match the output of a failing run.

The `stt` pack also builds four edge fixtures in process, so no extra audio is
stored: digital silence, plus three derived from `jfk.wav` — a truncated RIFF
whose header declares more audio than the bytes carry, a stereo 44.1 kHz
re-encode, and a 33-second concatenation. Their required outcomes are measured
behavior, not aspiration, except that the truncated RIFF may equally be
rejected with a typed `LlamaAudioFormatException` should decoding start
validating the header.
`speech-results.json` records each generated fixture's SHA-256 under
`edge_fixtures`, keyed by the same id as its check.

## Cancellation and cleanup bounds

After the single-shot lifecycle checks, a run whose `load` check passes repeats
`speechCleanupCycles` (8) cancel/dispose/load/generate cycles.
`speech-results.json` reports the bounds under `bounds`, and
`immediate_cancel_latency_bound`, `cancel_latency_bound`, `peak_memory_bound`
and `leak_slope_bound` are ordinary checks that fail the run when a budget is
exceeded. The budgets are `speechImmediateCancelLatencyBudgetMs`,
`speechCancelLatencyBudgetMs`, `speechPeakFootprintGrowthBudget` and
`speechLeakCycleGrowthBytes` in `lib/src/speech_runner.dart`.

The single-shot checks and every cycle each cancel twice:

- `cancel_immediate` cancels as soon as the task is handed back, without
  yielding first; the dedicated LiteRT adapter pushes no PCM before it. The
  adapter must report `cancel_immediate`. This is the window in which `tts`
  cancellations were dropped until
  [#596](https://github.com/leehack/llamadart/pull/596).
- `cancel` cancels after a wait. The GGUF adapter used by the `stt` and `tts`
  packs waits `speechCancelInFlightLeadFraction` of its most recent completed
  generation; the dedicated LiteRT adapter pushes PCM until the first partial
  transcript arrives, or until the fixture is exhausted. The adapter must
  report `cancel_in_flight`, which is true only if it had not seen the task
  finish when it cancelled; the dedicated LiteRT adapter also requires that at
  least one PCM chunk was accepted. It cannot show that the generation had
  begun. The `tts` adapter also records where the cancel landed:
  `progress_events_before_cancel`, `ms_since_last_progress_at_cancel`,
  `reference_progress_events` and `cancel_after_reference_last_progress`. The
  worker emits no progress event for its final step, which on Metal includes
  the code2wav decode and is 18-36% of a synthesis
  ([#627](https://github.com/leehack/llamadart/issues/627)), so the last flag
  is true when the cancel came after as many events as the reference
  generation emitted. The bounds list the counts and flags per sample as
  `progress_events_before_cancel` and `after_reference_last_progress`, with
  `null` for `stt`. Journals from older runs lack these fields.

Both record the time from the start of the call to the cancellation as
`cancel_after_ms`, and the cancelled task must emit no result. Cancellation
latency is the interval from `cancel()` to the task's terminal state, timed by
the adapter that issues it. It bounds when the task becomes terminal to its
caller, not when native work stops, so a cancellation honoured only after the
generation finishes can still pass either bound.

Peak memory is the largest whole-process memory footprint sampled after the
checks between `generate` and `peak_memory_bound`, as a multiple of the
footprint sampled right after `generate`. Each of those checks contributes one
sample, covering heterogeneous phases such as `bytes_input`, both cancellations,
the edge fixtures, `reload`, the cleanup cycles and the latency bounds, so the
peak is the maximum over all of them, not over generations alone. The baseline
follows the first generation rather than load, so memory that generation first
brings in is not counted as growth.

The peak ratio is not applied on Linux CUDA, where it records `SKIP` with a
reason and `bounds.peak_footprint_bytes.applies` is `false`. There the weights
stay in device memory, so the resident set after `generate` was only about
1.13 GB. Each reload then added 0-100 MB of host memory until the total leveled
off at 1.13-1.16x, which failed 1.10x without a leak
([#686](https://github.com/leehack/llamadart/issues/686)). Every other
operating system and backend pair, including any the runner does not know, gets
the ratio. Those numbers predate the trimmed Linux footprint below: sampled
after `malloc_trim(0)`, three Linux CUDA `tts` runs and one `stt` run peaked at
1.05-1.07x ([#762](https://github.com/leehack/llamadart/issues/762)).

`leak_slope_bound` runs on every backend. It fits a least-squares line to the
footprint sampled after cycles 1-8, the last of the
`speechLeakWarmupCycles` (1) warm-up cycles and the
`speechLeakWindowCycles` (7) after it, so growth up to the end of cycle 1 does
not count. It fails if the slope exceeds `speechLeakCycleGrowthBytes` (7 MiB)
per cycle. A plateau, a one-off spike or
a steady leak of 7 MiB per cycle or less passes. A steady leak of more fails,
even when some cycles fall back. So does a single step of more than 36.75 MiB
between cycles 4 and 5, or of more than 84 MiB between cycles 1 and 2 or 7 and
8. The constants come from these measurements:

- 7 MiB is half the smallest per-cycle resident set growth of the LiteRT ASR
  leak in [#634](https://github.com/leehack/llamadart/issues/634): 14.0 MiB
  across 12 warm cycles on macOS arm64. That leak fits 14.1-17.8 MiB per
  cycle.
- Without a known leak, 10 GGUF `stt` runs on Linux x64 and arm64 CPU, three
  `tts` runs on Linux CPU and four Linux CUDA runs, all sampled after
  `malloc_trim(0)`, fit -4.1 to 1.6 MiB per cycle. Three macOS resident set
  recordings fit up to 3.5 MiB per cycle.
- `stt` runs on GCE x64 and arm64 that leaked a `malloc` block after every
  `load` fit 9.0-15.3 MiB per cycle at 12 and 16 MiB per reload, and all six
  fail. Before [#762](https://github.com/leehack/llamadart/issues/762) the
  bound failed only when every cycle grew by more than 7 MiB, and each of
  those runs had a cycle that grew less, so all six passed. At 8 MiB per
  reload, 3 of 4 runs fail; at 4 MiB, both pass. On arm64 the 16 MiB leaks
  raised the peak ratio only to 1.08-1.09x, so only the slope fails them.
- With `reload`, the warm-up cycle covers the first two reloads, which took
  the largest step in six of nine recorded Linux CUDA `tts` runs.

The slope bound alone does not catch a leak of 7 MiB or less per cycle, or
growth that arrives in one jump before the window. On Linux, the #634 LiteRT
ASR resident set growth is one jump of about 85 MiB at `cancel`, then 0.7 MiB
per cycle; only the peak ratio fails it. On Linux CUDA, where the ratio is not
applied, a leak like that would pass.

The footprint counts native and Dart allocations together. Each report names
its counter in `measurement`:

| Platform | Counter | Counts | Does not count |
| --- | --- | --- | --- |
| macOS, iOS | `task_info(TASK_VM_INFO).phys_footprint` | dirty anonymous memory, private or shared, including pages the kernel compressed or swapped out; per XNU's ledger, also IOKit-mapped memory such as graphics and Metal buffers, non-volatile purgeable memory and page tables | file-backed pages, clean or dirty |
| Linux with glibc | `RssAnon` + `RssShmem` + `VmSwap` from `/proc/self/status`, read after `malloc_trim(0)` | resident anonymous pages, resident shared memory such as `memfd` and `MAP_SHARED \| MAP_ANONYMOUS` pages, and swapped-out anonymous pages | file-backed pages, clean or dirty; shared memory the kernel swapped out; freed heap memory, which the trim first returns to the kernel |
| Android, and Linux without `malloc_trim`, such as musl | `RssAnon` + `RssShmem` + `VmSwap` from `/proc/self/status` | the same, plus freed heap memory the allocator keeps | file-backed pages, clean or dirty, and shared memory the kernel swapped out |
| Windows | `PrivateUsage` + `SharedCommitUsage` from `GetProcessMemoryInfo` `PROCESS_MEMORY_COUNTERS_EX2` | committed private memory and committed pagefile-backed shared sections, whether resident or not, including committed pages never written | file-backed sections, clean or dirty |
| Windows without `PROCESS_MEMORY_COUNTERS_EX2` | `PrivateUsage` from `GetProcessMemoryInfo` `PROCESS_MEMORY_COUNTERS_EX` | committed private memory, whether resident or not, including committed pages never written | pagefile-backed shared sections; file-backed sections, clean or dirty |

Pages written through a private file mapping become the process's own memory
and are counted; Windows counts a whole copy-on-write view from the moment it
is mapped. `/proc/self/status` reports shared memory only while it is resident,
so on Linux a leak of shared memory that the kernel swaps out stops adding to
the footprint, and shared memory swapped out before a baseline sample lowers
that baseline too. `PROCESS_MEMORY_COUNTERS_EX2` needs Windows 10 22H2 or Windows
11 22H2 with the September 2023 cumulative update. If its first call fails or
leaves `SharedCommitUsage` unset, the run samples `PrivateUsage` alone
throughout, and `measurement` says that pagefile-backed shared sections are
not counted.

The resident set the bounds used before counts pages only while they stay in
memory. Under memory pressure on macOS its sample after `generate` came out up
to 2 GB low, more than the whole `tts` model file, and the peak ratio failed at
1.11-1.49x without a leak
([#633](https://github.com/leehack/llamadart/issues/633)). On macOS arm64,
`phys_footprint` held within 0.5% while compressing 4 GiB of dirty memory cut
the process's resident set from 4277 MiB to 139 MiB, and did not move while
`msync(MS_INVALIDATE)` dropped 512 MiB of mapped file pages. Counts differ
between operating systems, so ratios and deltas compare only within one.
There is no counter without `dart:io` or on other operating systems, and a
call that fails yields no sample. If any sample taken before
`peak_memory_bound` is unavailable, both memory bounds record `SKIP` with a
reason and their `bounds` entries report `measured` as `false`; they never
pass silently.
`interrupt_memory_bound` follows the same rule for the samples before it.

## Interrupt and truncation checks

The `tts` pack adds `unload_during_synthesis`, `dispose_during_synthesis`,
`decode_cancel` and `interrupt_memory_bound` after `leak_slope_bound`; the
`stt` pack adds `max_output_tokens_truncation` and
`context_size_truncation`. Each asserts its precondition in its own row and
records its budget there, not under `bounds`:

- `unload_during_synthesis` and `dispose_during_synthesis` require a progress
  event reporting a frame, and the task unfinished, before the call. The task
  must then end cancelled with no final audio within
  `speechCancelLatencyBudgetMs` of the call, and a synthesis after the reload
  must pass.
- `decode_cancel` first cancels `speechDecodeCancelOverheadRuns` syntheses
  capped at `speechDecodeCancelFrameCap` frames as soon as each is handed
  back, and takes the largest latency among them as the fixed cost of a
  cancellation. After one uncancelled capped synthesis as an untimed
  warm-up, it times the audio decode of `speechDecodeCancelReferenceRuns`
  uncancelled capped syntheses, from the
  progress event reporting the cap to the terminal state, running half before
  and half after one more synthesis. That one is cancelled
  `speechDecodeCancelLeadFraction` of the shortest earlier decode after that
  event. The margin is `speechDecodeCancelNoiseMultiple` times the spread of
  all reference decodes, and at least `speechDecodeCancelMarginFloorFraction`
  of the shortest. Timed from that event, the cancelled synthesis must end
  more than the margin sooner than the shortest reference, or the check
  fails; it also fails if the cancelled synthesis emits a final result. It
  records `NOT_RUN` with a `not_run_reason` and the measured numbers when the
  latest normal synthesis does not exceed the cap, a probe does not end
  cancelled, the warm-up or a reference does not stop at the cap, the
  cancellation does not reach a synthesis that has reported the cap at its
  scheduled lead, or the
  shortest reference decode left after the cancellation, less the overhead,
  is within the margin. In that last case even an immediate cancellation
  could not pass. `NOT_RUN` leaves `functional_pass` false.
- `interrupt_memory_bound` divides the largest footprint sampled after the
  three checks above by the one sampled after `leak_slope_bound`, against
  `speechPeakFootprintGrowthBudget`. Each of those checks reloads the model.
  Running them after the lifecycle bounds keeps their reloads out of those
  bounds, puts the lifecycle's reloads in their baseline, and still fails
  growth they add. Like `peak_memory_bound`, it records `SKIP` with the
  `speechPeakRatioExemption` reason on Linux CUDA and keeps its numbers,
  since reload overhead there exceeds the ratio without a leak. The
  interrupt checks run once each, so they get no slope bound: on Linux CUDA
  they have no memory bound.
- `max_output_tokens_truncation` sets `maxOutputTokens` to
  `speechTruncationTokenFraction` of the reference's token count, rounded
  down, and requires the latest complete transcript to tokenize to more.
  `context_size_truncation` loads a `speechTruncationContextSize` context,
  with `maxOutputTokens` no smaller, and sends the 33-second fixture. Both
  must fail with `LlamaSpeechTranscriptTruncatedException` at that limit and a
  partial transcript that is a strict word prefix of the expected one, its
  last word possibly cut short, and the next recognition on the same engine
  must reproduce the reference.
