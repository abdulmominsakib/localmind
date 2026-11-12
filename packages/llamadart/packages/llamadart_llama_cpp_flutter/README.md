# llamadart_llama_cpp_flutter

Flutter Apple Swift Package Manager companion package for
[`llamadart`](https://pub.dev/packages/llamadart) GGUF / llama.cpp support.

Add this package to a Flutter iOS/macOS app when the app should link the
prebuilt llama.cpp Apple XCFramework through SwiftPM instead of relying on the
core package's native-assets fallback.

Use the companion that shares the core's `MAJOR.MINOR`: companion `0.19.x` pairs
with core `0.19.x`. Upgrade both together. Earlier pairings are in the
[changelog](https://github.com/leehack/llamadart/blob/main/CHANGELOG.md).

```yaml
dependencies:
  llamadart: ^0.19.7
  llamadart_llama_cpp_flutter: ^0.19.7
```

This package has no runtime Dart API of its own. Import `package:llamadart`
normally from the core package and use `LlamaBackend()` / `LlamaEngine` there.

The Apple SwiftPM manifest pins `leehack/llamadart-native@v0.9.0`.

Apps bound for the App Store should use this package: the Apple privacy
manifest for the llama.cpp runtime ships inside this XCFramework, never in the
dylibs the core package's native-assets fallback bundles. It declares
`NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1`. If the
embedded `llama.framework` in the built app has no `PrivacyInfo.xcprivacy`, or
the app uses the fallback, declare that category and reason in the app's own
`PrivacyInfo.xcprivacy`. See
[Apple privacy manifest](https://llamadart.leehack.com/docs/platforms/apple-setup#apple-privacy-manifest).

Source for this package lives in
`packages/llamadart_llama_cpp_flutter` in the
[`llamadart`](https://github.com/leehack/llamadart) repository.

## Fresh macOS builds

Keep Runner's deployment target at macOS 14.0 or newer. If SwiftPM reports
that `FlutterGeneratedPluginSwiftPackage` supports only 12.0, follow the
[Flutter 3.47.1 consumer bootstrap](https://llamadart.leehack.com/docs/platforms/apple-setup#fresh-macos-swiftpm-bootstrap)
before the first build. It updates only the ignored generated manifest and
builds with `--no-pub`; keep this package's platform requirements, native
URLs and checksums intact.
