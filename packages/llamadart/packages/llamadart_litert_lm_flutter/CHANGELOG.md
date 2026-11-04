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
