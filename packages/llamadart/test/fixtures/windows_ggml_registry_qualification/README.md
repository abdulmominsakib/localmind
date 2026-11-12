# Windows native override registry qualification

This local-only fixture qualifies #1649 on one actual Windows 2022 x64 CPU
host. It preserves the reviewed original/fixed H/E/P protocol, the two alias
rows, maintained integration and typed-refusal tests, the actual ggml →
ggml-base declaration mutant and byte-exact restoration, and whole-bundle AOT
copy/run outside all sources from an empty working directory.

The passive observer records production outcome and unload before observing
modules, then resolves the code asset and reads registry getters. The durable
fixture corrects the old protocol's primary-module suffix literal to match one
Windows separator. Drive/UNC paths and suffix negatives exercise the real
selector. This is an observer correction, not a production runtime change.

## Fixed identities and staging

`inputs.json` pins the original commit, Flutter 3.47.1 / Dart 3.13.1 archive,
MinGit, matched published core/CUDA12 and Qwen2.5-1.5B Q4_K_M revision/bytes/hash.
No model/ref/command inputs exist. The candidate is the clean checkout's exact
`GITHUB_SHA`. Both sources are exported with pinned Git and every regular blob,
mode, path and SHA256 is bound to the actual Git trees. Generated consumer files
and the sole pubspec hook overlay are explicit; all tracked source/lock bytes
and external dependency identities are checked before and after use.

For disk fit, the exact hash-verified Flutter ZIP yields **every unmodified file
in `flutter/bin/cache/dart-sdk/` only**. The archived Dart subtree supplies the
same Dart executable/snapshots/libraries as full Flutter extraction; the Flutter
tool is not executed. Archive digest, entry lengths/hashes, Dart path/version and
executable digest make this equivalence reviewable. Pinned MinGit is extracted
unchanged; no hosted Git substitution occurs. Nothing deletes shared host data.

Space receipts record actual free bytes before SDK/native work and measured
expanded SDK/native/source sizes. Before downloading the model, the conservative
additional peak reserves eight expanded native copies, three source-pair copies,
two GiB Pub/build margin and the exact model bytes. Insufficient stock-runner
space fails distinctly. It never changes weights/runtime mix or selects a billed
runner. Four fresh matrix trees, one disposable mutation tree, one fresh Pub cache
and unique child TEMP/TMP/TMPDIR directories prevent warmed runtime process state.

## Run and evidence

The optional boolean on existing `ci.yml` runs this separately from required CI
and disables chat deployment for that run. Local Windows execution from a clean
checkout uses a new absolute scratch directory:

```powershell
$env:GITHUB_SHA = git rev-parse HEAD
$env:GITHUB_RUN_ID = 'local'
$env:GITHUB_RUN_ATTEMPT = '1'
$env:LLAMADART_WINDOWS_QUALIFICATION = 'C:\qualification-new'
./test/fixtures/windows_ggml_registry_qualification/qualification.ps1 -Prepare
$env:Path = "$env:LLAMADART_WINDOWS_QUALIFICATION\stage\flutter\bin\cache\dart-sdk\bin;$env:Path"
dart pub get
dart run tool/testing/run_local_e2e.dart --list
dart run tool/testing/run_local_e2e.dart --scenario windows-native-override-registry --dry-run
dart run tool/testing/run_local_e2e.dart --scenario windows-native-override-registry
./test/fixtures/windows_ggml_registry_qualification/qualification.ps1 -Seal
```

Failure/setup receipts are separate from backend outcomes. Caught errors,
timeouts, missing terminal or incomplete controls exit nonzero. All 18 outcomes
are collected before required matrix failures block subsequent shipping checks;
the original seven override outcomes remain data. CPU-only hardware/driver
preflight and zero offload do not qualify GPU execution.

The inner `evidence.zip` includes every evidence file (including hidden files),
complete hash manifest and the 65,536-byte incompressible fixture. Extraction is
locally checked byte-for-byte before immutable upload. It retains raw child
stdout/stderr, exits/timeouts and selected input environments, source/overlay/Pub
and lock receipts, model/native/SDK hashes, native asset maps and DLL identities,
mutant/restoration records, full AOT inventories and terminal/summary. As in the
reviewed protocol, this is evidence reproduction: weights, Pub cache, SDK/native
binary copies and the AOT runtime bundle are excluded. Complete AOT build/copy
inventories and provider hashes remain required; no logs are truncated to fit.

Download the unique one-day artifact by its immutable ID, check the outer Actions
artifact SHA256 independently, then retain a local copy and verify the inner ZIP:

```sh
python3 test/fixtures/windows_ggml_registry_qualification/verify_evidence.py evidence.zip \
  --head FULL_WORKFLOW_SHA --run-id RUN_ID --run-attempt RUN_ATTEMPT
```

For a failed run, add `--inventory-only` to verify complete bytes and run binding
without claiming qualification.

Successful upload or normal CI aggregate is insufficient. The actual Windows
terminal/result, complete downloaded evidence and fresh independent review remain
separate gates. Cancellation or missing/truncated evidence is incomplete.
