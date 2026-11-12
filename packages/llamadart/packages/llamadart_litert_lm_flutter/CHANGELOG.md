## 0.19.7

- Refresh README installation guidance for core `0.19.7`.
- Pair with core `>=0.19.7 <0.20.0`; Apple SwiftPM stays pinned to `leehack/litert-lm-native@v0.19.1-4`.

## 0.19.6

- Refresh README installation guidance for core `0.19.6`.
- Pair with core `>=0.19.6 <0.20.0`; pin `leehack/litert-lm-native@v0.19.1-4` and drop the unused `LiteRt` and `LiteRtWebGpuAccelerator` targets: `LiteRtLm` embeds both, so macOS apps no longer embed two dylibs (about 16.9 MB) or download 6.2 MB of XCFrameworks ([#1911](https://github.com/leehack/llamadart/issues/1911)).

## 0.19.5

- Refresh README installation guidance for core `0.19.5`.
- Pair with core `>=0.19.5 <0.20.0`; pin `leehack/litert-lm-native@v0.19.1-3` and drop the unused `LiteRtMetalAccelerator` target, which saves 8.1 MB per iOS app ([#1798](https://github.com/leehack/llamadart/issues/1798)).

## 0.19.4

- Refresh README installation guidance for core `0.19.4`; Apple SwiftPM stays pinned to `leehack/litert-lm-native@v0.19.1-2`.

## 0.19.3

- Refresh README installation guidance for core `0.19.3`; Apple SwiftPM stays pinned to `leehack/litert-lm-native@v0.19.1-2`.

## 0.19.2

- Not published: pub.dev rejected the core 0.19.2 upload, so this companion release did not run. 0.19.3 ships its README refresh.

## 0.19.1

- Pair with core `>=0.19.1 <0.20.0`; update Apple SwiftPM to
  `leehack/litert-lm-native@v0.19.1-2`, which reports LiteRT linked in process.
- Raise the Flutter floor to `>=3.38.6`, the first Flutter whose Dart (3.10.7)
  satisfies `sdk: ^3.10.7`
  ([#1834](https://github.com/leehack/llamadart/issues/1834)).

## 0.19.0

- Pair with core `>=0.19.0 <0.20.0`; update Apple SwiftPM to
  `leehack/litert-lm-native@v0.19.1-1` (upstream LiteRT-LM `v0.19.1`).

## 0.18.0

- Pair with core `>=0.18.0 <0.19.0`; update Apple SwiftPM to
  `leehack/litert-lm-native@v0.19.0` for C API 1.0 and updated Apple runtime libraries.

## 0.17.3

* Refresh README installation guidance for core `0.17.5`; Apple SwiftPM stays pinned to `leehack/litert-lm-native@v0.18.1-4`.

## 0.17.2

* Refresh README installation guidance for core `0.17.4`; Apple SwiftPM stays pinned to `leehack/litert-lm-native@v0.18.1-4`.

## 0.17.1

* Release with core `0.17.1`; Apple SwiftPM stays pinned to `leehack/litert-lm-native@v0.18.1-4`, so core `0.17.0` still pairs with it. The README now shows the current pairing and privacy-manifest facts.

## 0.17.0

- Pair with core `0.17.x`; Apple SwiftPM stays pinned to
  `leehack/litert-lm-native@v0.18.1-4`.

## 0.16.2

- Update Apple SwiftPM to `leehack/litert-lm-native@v0.18.1-4`, the LiteRT-LM
  runtime of core `0.16.2`; require core `>=0.16.2 <0.17.0`.

## 0.16.1

- Update Apple SwiftPM to `leehack/litert-lm-native@v0.18.1-2`, which makes
  CPU chat and audio embeddings deterministic again on SME2 CPUs such as Apple
  M4 and restores Gemma 4 CPU decode speed; require core `>=0.16.1 <0.17.0`.

## 0.16.0

* Pair with core `0.16.x`; update Apple SwiftPM to `leehack/litert-lm-native@v0.18.1`,
  built from upstream LiteRT-LM `v0.18.1`.

## 0.15.2

- Update Apple SwiftPM to `leehack/litert-lm-native@v0.18.0-3`, which loads
  dedicated ASR `.litertlm` containers such as Whisper tiny; require core
  `>=0.15.6 <0.16.0`.

## 0.15.1

- Update core 0.15.1 examples; retain `leehack/litert-lm-native@v0.18.0-2`.

## 0.15.0

* Pair with core `0.15.x`; Apple SwiftPM stays pinned to `leehack/litert-lm-native@v0.18.0-2`.

## 0.14.0

* Pair with core `0.14.x`; Apple SwiftPM pins `leehack/litert-lm-native@v0.18.0-2`.

## 0.13.0

* Versions now share the core `MAJOR.MINOR`; this release pairs with core
  `0.13.0`.
* Depends on `llamadart` within the core minor this companion pairs with,
  so pub refuses to resolve it beside a mismatched core. The Apple SwiftPM
  native pin stays `leehack/litert-lm-native@v0.18.0-1`.

## 0.0.16

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.18.0-1`.
* Link arm64-only macOS LiteRT-LM XCFrameworks, so universal macOS apps
  launch on Intel Macs and under Rosetta
  ([litert-lm-native#72](https://github.com/leehack/litert-lm-native/issues/72)).

## 0.0.15

* Link and embed the complete macOS arm64 LiteRT-LM runtime from
  `leehack/litert-lm-native@v0.18.0`, adding the `LiteRt`, WebGPU accelerator
  and sampler, and Dawn XCFrameworks, so sandboxed and distributed Flutter
  macOS apps load LiteRT-LM from their own bundle.

## 0.0.14

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.18.0`.

## 0.0.13

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.17.0-8`.

* The pinned iOS frameworks carry Apple privacy manifests.

## 0.0.12

* Update the install example for `llamadart` 0.9.0; the LiteRT-LM runtime
  remains `leehack/litert-lm-native@v0.17.0-6`.

## 0.0.11

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.17.0-6`.

## 0.0.10

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.16.0-native.2`
  and packaged the iOS Gemma constraint provider and Metal accelerator/sampler
  plugins required by that runtime.
* Kept macOS on the complete hook-managed runtime bundle instead of linking an
  incomplete SwiftPM subset.
* Updated the install example for `llamadart` 0.8.20.

## 0.0.9

* Updated the install example for `llamadart` 0.8.19.

## 0.0.8

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.15.0-native.3`.

* Updated the install example for `llamadart` 0.8.18.

## 0.0.7

* Updated the install example for `llamadart` 0.8.17.

## 0.0.6

* Updated the install example for `llamadart` 0.8.16.

## 0.0.5

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.14.0-native.2`.

* Replaced the separate iOS Gemma provider target with the consolidated
  upstream runtime and enabled the complete macOS SwiftPM artifact set.

## 0.0.4

* Added the `GemmaModelConstraintProvider` SwiftPM binary target required by
  the pinned LiteRT-LM iOS Apple frameworks.
* Stopped linking the incomplete macOS LiteRT-LM SwiftPM artifact set; Flutter
  macOS `.litertlm` builds use the core package's native-assets fallback.

## 0.0.3

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.14.0-native.1`.

## 0.0.2

* Updated Apple SwiftPM native pin to `leehack/litert-lm-native@v0.13.1-native.1`.

## 0.0.1

* Initial Flutter Apple SwiftPM companion package for `llamadart` LiteRT-LM /
  `.litertlm` runtime linking, pinned to `leehack/litert-lm-native@v0.13.1`.
