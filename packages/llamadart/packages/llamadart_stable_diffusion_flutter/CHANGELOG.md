## 0.19.7

- Refresh README installation guidance for core `0.19.7`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-3`.

## 0.19.6

- Refresh README installation guidance for core `0.19.6`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-3`.

## 0.19.5

- Refresh README installation guidance for core `0.19.5`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-3`.

## 0.19.4

- Refresh README installation guidance for core `0.19.4`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-3`.

## 0.19.3

- Refresh README installation guidance for core `0.19.3`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-3`.

## 0.19.2

- Not published: pub.dev rejected the core 0.19.2 upload, so this companion release did not run. 0.19.3 ships its README refresh.

## 0.19.1

- Raise the Flutter floor to `>=3.38.6`, the first Flutter whose Dart (3.10.7)
  satisfies `sdk: ^3.10.7`
  ([#1834](https://github.com/leehack/llamadart/issues/1834)); Apple SwiftPM stays
  pinned to `leehack/stable-diffusion-native@v0.3.0-3`.

## 0.19.0

- Pair with core `>=0.19.0 <0.20.0`; Apple SwiftPM stays pinned to
  `leehack/stable-diffusion-native@v0.3.0-3`.

## 0.18.0

- Pair with core `>=0.18.0 <0.19.0`; update Apple SwiftPM to
  `leehack/stable-diffusion-native@v0.3.0-3` for original SD checkpoint container loading.

## 0.17.3

* Refresh README installation guidance for core `0.17.5`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-1`.

## 0.17.2

* Refresh README installation guidance for core `0.17.4`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-1`.

## 0.17.1

* Release with core `0.17.1`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.3.0-1`, so core `0.17.0` still pairs with it. The README now shows the current pairing and privacy-manifest facts.

## 0.17.0

* Pair with core `0.17.x`; update Apple SwiftPM to `leehack/stable-diffusion-native@v0.3.0-1`, which loads FP8 image weights as F16 on Metal.

## 0.16.0

* Pair with core `0.16.x`; update Apple SwiftPM to `leehack/stable-diffusion-native@v0.3.0`, which loads legacy
  checkpoints above 2 GiB.

## 0.15.2

- Update Apple SwiftPM to `leehack/stable-diffusion-native@v0.2.0-4`, which
  propagates Metal failures; require core `>=0.15.2 <0.16.0`.

## 0.15.1

- Update core 0.15.1 examples; retain `leehack/stable-diffusion-native@v0.2.0-3`.

## 0.15.0

* Pair with core `0.15.x`; Apple SwiftPM stays pinned to `leehack/stable-diffusion-native@v0.2.0-3`.

## 0.14.0

* Pair with core `0.14.x`; Apple SwiftPM pins `leehack/stable-diffusion-native@v0.2.0-3`.

## 0.13.0

* Versions now share the core `MAJOR.MINOR`; this release pairs with core
  `0.13.0`.
* Depends on `llamadart` within the core minor this companion pairs with,
  so pub refuses to resolve it beside a mismatched core. The Apple SwiftPM
  native pin stays `leehack/stable-diffusion-native@v0.2.0-3`.

## 0.0.3

* Updated Apple SwiftPM native pin to `leehack/stable-diffusion-native@v0.2.0-3`.

## 0.0.2

* Updated Apple SwiftPM native pin to `leehack/stable-diffusion-native@v0.2.0-1`,
  whose XCFramework carries an Apple privacy manifest and frees image models
  still allocated at process exit.

## 0.0.1

* Initial Flutter Apple SwiftPM companion package for `llamadart`
  stable-diffusion.cpp image generation.
* Updated Apple SwiftPM native pin to `leehack/stable-diffusion-native@v0.2.0`.
