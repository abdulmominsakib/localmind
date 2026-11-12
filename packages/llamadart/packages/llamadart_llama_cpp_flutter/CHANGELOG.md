## 0.19.7

- Refresh README installation guidance for core `0.19.7`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.9.0`.

## 0.19.6

- Refresh README installation guidance for core `0.19.6`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.9.0`.

## 0.19.5

- Refresh README installation guidance for core `0.19.5`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.9.0`.

## 0.19.4

- Refresh README installation guidance for core `0.19.4`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.9.0`.

## 0.19.3

- Refresh README installation guidance for core `0.19.3`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.9.0`.

## 0.19.2

- Not published: pub.dev rejected the core 0.19.2 upload, so this companion release did not run. 0.19.3 ships its README refresh.

## 0.19.1

- Raise the Flutter floor to `>=3.38.6`, the first Flutter whose Dart (3.10.7)
  satisfies `sdk: ^3.10.7`
  ([#1834](https://github.com/leehack/llamadart/issues/1834)); Apple SwiftPM stays
  pinned to `leehack/llamadart-native@v0.9.0`.

## 0.19.0

- Pair with core `>=0.19.0 <0.20.0`; update Apple SwiftPM to
  `leehack/llamadart-native@v0.9.0` for the ARM64 F16 overflow fix and the
  Chatterbox and Pocket TTS runtime.

## 0.18.0

- Pair with core `>=0.18.0 <0.19.0`; update Apple SwiftPM to
  `leehack/llamadart-native@v0.8.0-3` for speculative rollback and model-creation ownership fixes and retirement of the unused embedding query; retain the genuine nextn query.

## 0.17.3

* Refresh README installation guidance for core `0.17.5`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.8.0-1`.

## 0.17.2

* Refresh README installation guidance for core `0.17.4`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.8.0-1`.

## 0.17.1

* Update Apple SwiftPM to `leehack/llamadart-native@v0.8.0-1`, the llama.cpp runtime of core `0.17.1`; require core `>=0.17.1 <0.18.0`.

## 0.17.0

* Pair with core `0.17.x`; update Apple SwiftPM to `leehack/llamadart-native@v0.7.0-3`, the runtime `LlamaEngine.stateIdentity()` needs.

## 0.16.0

* Pair with core `0.16.x`; Apple SwiftPM stays pinned to `leehack/llamadart-native@v0.7.0-2`.

## 0.15.2

- Update Apple SwiftPM to `leehack/llamadart-native@v0.7.0-2`, which seeds
  every Qwen3-TTS codebook from the request; require core `>=0.15.6 <0.16.0`.

## 0.15.1

- Update core 0.15.1 examples; retain `leehack/llamadart-native@v0.7.0-1`.

## 0.15.0

* Pair with core `0.15.x`; Apple SwiftPM pins `leehack/llamadart-native@v0.7.0-1`.

## 0.14.0

* Pair with core `0.14.x`; Apple SwiftPM pins `leehack/llamadart-native@v0.7.0`.

## 0.13.0

* Versions now share the core `MAJOR.MINOR`; this release pairs with core
  `0.13.0`.
* Depends on `llamadart` within the core minor this companion pairs with,
  so pub refuses to resolve it beside a mismatched core. The Apple SwiftPM
  native pin stays `leehack/llamadart-native@v0.6.0-3`.

## 0.0.23

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@v0.6.0-3`.

## 0.0.22

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@v0.6.0-2`.

## 0.0.21

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@v0.5.0-2`,
  whose XCFramework carries an Apple privacy manifest and frees llama.cpp
  objects still allocated at process exit.

## 0.0.20

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@v0.5.0`.

## 0.0.19

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@v0.4.1`.

## 0.0.18

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@v0.4.0`.

## 0.0.17

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@v0.3.0`.

## 0.0.16

* Updated Apple SwiftPM native pin to the immutable
  `leehack/llamadart-native@v0.2.0-1` release, built from llama.cpp `v0.2.0`.

## 0.0.15

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b10545`.

## 0.0.14

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b10514`.

## 0.0.13

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b10333`.

## 0.0.12

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b10276`.

## 0.0.11

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b10075`.

## 0.0.10

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9982`.

## 0.0.9

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9935`.

## 0.0.8

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9860`.

## 0.0.7

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9829`.

## 0.0.6

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9803`.

## 0.0.5

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9776`.

## 0.0.4

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9744`.

## 0.0.3

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9694`.

## 0.0.2

* Updated Apple SwiftPM native pin to `leehack/llamadart-native@b9587`.

## 0.0.1

* Initial Flutter Apple SwiftPM companion package for `llamadart` llama.cpp /
  GGUF runtime linking, pinned to `leehack/llamadart-native@b9547`.
