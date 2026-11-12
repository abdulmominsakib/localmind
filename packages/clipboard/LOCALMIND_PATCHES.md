# LocalMind dependency patch

Baseline: clipboard 3.0.14, published pub.dev archive
(https://pub.dev/packages/clipboard). Original LICENSE retained.

Local changes:

1. Removed the dead `DWORD headerSize = ...` local in
   `windows/clipboard_plugin.cpp` (computed, never read). The plugin builds
   with `/W4 /WX`, so the unused variable raised C4189 → C2220 and broke every
   Windows desktop build. No behaviour change; DIB → GDI+ conversion uses
   `pBih->biSize` directly.

2. Disabled the `windows:` platform declaration in `pubspec.yaml`. Upstream's
   Windows CMake expects `<clipboard/clipboard_plugin.h>` to resolve from the
   plugin root, but ships the header under `windows/`, so Flutter's generated
   `generated_plugin_registrant.cc` include never resolves and the runner
   cannot compile. LocalMind does not use this plugin on desktop anyway: the
   app copies via Flutter's built-in `Clipboard` API, and only
   syntax_highlight's `CodeEditor` (unused here) calls this plugin.

Windows note: without the plugin registration, a Windows user tapping
`CodeEditor`'s copy would hit a `MissingPluginException`; the app does not
embed that widget.

3. Removed the redundant `library clipboard;` directive (app lint
   `unnecessary_library_name`).

Do not patch the global pub cache. Drop the override once upstream ships a
release whose Windows plugin builds.
