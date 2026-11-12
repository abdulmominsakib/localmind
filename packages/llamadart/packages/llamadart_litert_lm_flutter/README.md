# llamadart_litert_lm_flutter

Flutter Apple Swift Package Manager companion package for
[`llamadart`](https://pub.dev/packages/llamadart) `.litertlm` / LiteRT-LM
support.

Add the package to a Flutter iOS or macOS app so it links the prebuilt
LiteRT-LM Apple XCFrameworks through SwiftPM instead of relying on the core
package's native-assets fallback. On macOS it also links the Dawn XCFramework,
so the app bundle holds the complete runtime and a sandboxed or distributed app
loads LiteRT-LM on CPU and GPU. Every macOS XCFramework is arm64 only; a universal build prints an
`ignoring file ... required architecture 'x86_64'` linker warning for each.
`LiteRtLm` embeds LiteRT and its GPU accelerator (Metal on iOS, WebGPU on
macOS), so the package links no separate `LiteRt`, WebGPU accelerator or Metal
accelerator.

LiteRT-LM is not available on x86_64 macOS: `litert-lm-native` publishes
arm64-only macOS runtimes. A universal app still launches on an Intel Mac or
under Rosetta, where LiteRT-LM throws `LlamaUnsupportedException`. Building the
macOS app for arm64 only, for example with `EXCLUDED_ARCHS = x86_64`, just
silences the linker warnings. The core uses this macOS runtime only when it recognizes this package's
manifest; with an older companion it keeps LiteRT-LM in its hook cache and
warns.

The iOS artifacts include arm64 device and arm64 Simulator slices. Apps that
also request an x86_64 Simulator slice must exclude x86_64 for LiteRT-LM builds.

```yaml
dependencies:
  llamadart: ^0.19.7
  llamadart_litert_lm_flutter: ^0.19.7
```

This package has no runtime Dart API of its own. Import `package:llamadart`
normally from the core package and use `LlamaBackend()` / `LlamaEngine` there.

The Apple SwiftPM manifest pins `leehack/litert-lm-native@v0.19.1-4`.
That runtime loads dedicated ASR `.litertlm` containers such as Whisper tiny.

Use the companion that shares the core's `MAJOR.MINOR`: companion `0.19.x` pairs
with core `0.19.x`. Earlier pairings are in the
[changelog](https://github.com/leehack/llamadart/blob/main/CHANGELOG.md).

These iOS artifacts omit the Gemma FST constraint provider. Gemma 3/4 and
FunctionGemma conversations must use constrained decoding disabled, as the Dart
adapter already does. Enabling it through the native C API fails conversation
creation with a null handle and a build-time-disabled diagnostic. Ordinary
generation, thinking and best-effort tool formatting remain available; automatic
tool loops and strict structured output remain unsupported. On macOS,
`LiteRtLm.framework` carries its own provider.

iOS 16.4 is the declared deployment floor, not a tested one: the Swift package
requires an iOS 16.4 app target, but nothing has been run on iOS 16.4. On a
device, model load and generation have run only on an iPhone 16 Pro with
iOS 18.3.2. Device qualification is tracked in
[llamadart#514](https://github.com/leehack/llamadart/issues/514).

Apps bound for the App Store should use this package for LiteRT-LM on iOS:
its iOS frameworks carry Apple privacy manifests for the
[required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
they reference, and the dylibs the core package's native-assets fallback
bundles carry none. `LiteRtLm` declares File Timestamp (`C617.1`, `3B52.1`)
and System Boot Time (`35F9.1`), and `CLiteRTLM` no API. If the embedded
LiteRT-LM frameworks in the built app have no `PrivacyInfo.xcprivacy`, or the
app uses the fallback, declare those two categories and reasons in the app's own
`PrivacyInfo.xcprivacy`. The reasons come from the runtime owner's audit
([litert-lm-native#65](https://github.com/leehack/litert-lm-native/issues/65))
and have not been verified with an App Store Connect upload. See
[Apple privacy manifest](https://llamadart.leehack.com/docs/platforms/apple-setup#apple-privacy-manifest).

Source for this package lives in
`packages/llamadart_litert_lm_flutter` in the
[`llamadart`](https://github.com/leehack/llamadart) repository.

## Fresh macOS builds

Keep Runner's deployment target at macOS 14.0 or newer. If SwiftPM reports
that `FlutterGeneratedPluginSwiftPackage` supports only 12.0, follow the
[Flutter 3.47.1 consumer bootstrap](https://llamadart.leehack.com/docs/platforms/apple-setup#fresh-macos-swiftpm-bootstrap)
before the first build. It updates only the ignored generated manifest and
builds with `--no-pub`; keep this package's platform requirements, native
URLs and checksums intact.
