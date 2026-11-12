---
title: Diagnose setup
description: Collect a model-free setup report with llamadart:doctor, or probe one native runtime with llamadart:doctor_native, and read their exit codes.
---

Two model-free desktop commands report what a llamadart setup looks like before
a model loads. Both run on macOS, Linux and Windows.

| Command | Reports | Exit codes |
| --- | --- | --- |
| `dart run llamadart:doctor` | [Setup snapshot](#desktop-setup-report) | `0` report produced (or `--help`), `1` no report could be produced, `64` invalid arguments |
| `dart run llamadart:doctor_native` | [Setup snapshot plus one runtime probe](#isolated-native-check) | `0` report produced (or `--help`), including a failed check; `1` no report; `64` invalid arguments |

## Desktop setup report

On macOS, Linux or Windows, collect a bounded setup snapshot before loading a
model:

```bash
dart run llamadart:doctor
dart run llamadart:doctor --json
dart run llamadart:doctor --help
```

The JSON command writes one schema-versioned document to stdout. Exit 0 means
a report was produced, **not** that a runtime works; exit 1 means no report
could be produced; invalid arguments exit 64.
The collector itself performs bounded local package-metadata reads and no
network, subprocess, native initialization, native-asset resolution, GPU probe
or model load. `dart run` can run the package build hook **before main**: it may
prepare/download native assets, print build output, or fail before a report is
produced. Capture/parse the CLI's report stdout only after a successful launch.

The public API is usable from a desktop Dart IO process, including a desktop
Flutter process:

```dart
import 'package:llamadart/llamadart.dart';

Future<void> main() async {
  final LlamaRuntimeSetupReport report =
      await collectLlamaRuntimeSetupReport();
  print(report.toText());
}
```

Schema 1 contains normalized OS/version/ABI architecture, Dart version,
llamadart's **own** package version (unknown if source metadata is unavailable),
and expected native release tags with published-bundle policy from the hook's
selectors. Unrecognized metadata becomes `unknown`; Flutter version is unknown
and is not inferred from the Dart CLI. macOS x64 LiteRT-LM and Windows arm64
LiteRT-LM/stable_diffusion are marked unavailable under current publication
policy. Unknown OS/ABI combinations stay unknown. Policy is separate from
observed native loading: custom bundles, hook settings and Apple companions can
differ. No report field proves which assets were emitted or loaded. Actual
loaded versions/backend/GPU, model capabilities and inference remain
`unknown`/`not_checked`.

Only the names `LLAMADART_NATIVE_LIB_DIR`, `LLAMADART_BACKEND_MODULE_DIR`, and
`LLAMADART_LITERT_LM_LIB_DIR` are reported as `set`/`unset` (an empty value counts
as set). Values, paths, arbitrary environment variables, exception text and
logs are excluded. Remediation uses fixed codes and hints.

Mobile/Web collection throws `LlamaUnsupportedException` with scope guidance.
A Dart CLI report does not validate an already-built Flutter app, device or
browser. `web_setup --check` remains a separate offline asset check, not a live
browser diagnosis. Native bootstrap, mobile/browser diagnostics and broader
doctor work remain in [#124](https://github.com/leehack/llamadart/issues/124).
To check a load before it runs, see
[Check a load before it runs](../guides/backend-selection#check-a-load-before-it-runs).

## Isolated native check

Opt into a separate model-free Dart desktop command for one runtime:

```bash
dart run llamadart:doctor_native --runtime llama_cpp --json
dart run llamadart:doctor_native --runtime litert_lm
dart run llamadart:doctor_native --runtime stable_diffusion
```

The command preserves the setup snapshot under `setup` and reports a separate
`native_probe`. It reads only the current ABI's supported absolute-file entries
from the local native-assets descriptor next to the active package config.
Those are local declarations, which can be stale; they do not prove the assets
compiled into a consuming app. It never guesses a release from file paths,
hashes or expected publication policy, or searches neighboring caches after a
declared target fails. Overrides are reported only as set/unset and can differ
from the checked declaration.

Each invocation starts one bounded child process, opens declared files, resolves
a small fixed symbol group, and reads compile-time llama.cpp/LiteRT ABI markers.
Stable Diffusion checks symbols only. No engine, model, device enumeration, GPU
probe or inference is started; native constructors can still run when a library
opens. Raw child output and loader errors are discarded. Only fixed result codes
and remediation text reach either renderer. The child runs no hook, network or
shell command; the outer `dart run` build hook can still prepare assets before
main. The source helper ships with the package; compiled executables, Flutter
SPM/in-process assets and app/device/browser validation are outside this check.

The coordinator starts one 30-second budget at entry, covering metadata,
manifest processing, child startup/work, pipe drains and IPC results. Forced
termination, reaping and cleanup have one additional three-second reserve.
Manifest content is read inside the timed child, so a concurrent replacement
cannot strand a parent file open. Non-regular files and manifest/IPC symlinks
are refused before opening. Parent IPC reads happen only after confirmed child
exit, using its small private files with no other writer. This assumes responsive
local filesystem operations; it does not promise interruption of arbitrary
kernel/network-filesystem stalls or protection against hostile same-user path
replacement. This is not a sandbox for malicious native code.

`SURFACE_OBSERVED` means the declared files opened and the selected symbols/ABI
markers were observed in that child. It does not prove all bindings, production
loader resolution, a loaded owner release, usable hardware or model execution.
Windows direct file loading can differ from production's sibling-DLL search;
its failure is not proof the backend is unavailable. `production_loader`,
`emitted_app_libraries`, GPU, model and inference remain unchecked, and
`loaded_release` remains unknown. Native Windows/Linux execution is not
qualified by the macOS artifact checks.

`ASSET_NOT_DECLARED` means this local descriptor has no selected runtime; check
the intended build selection. Missing/invalid descriptors, missing files,
loader failures, missing symbols, unknown ABI markers, child failures and
timeouts have separate fixed codes. A timeout or child failure has no hardware
diagnosis. Exit 0 means a report was produced, including a failed check; exit 1
means no report and exit 64 means invalid arguments. Use the codes for automation.
The default `doctor` and `collectLlamaRuntimeSetupReport()` continue to load no
native library and spawn no process. Broader diagnostics remain in
[#124](https://github.com/leehack/llamadart/issues/124).
