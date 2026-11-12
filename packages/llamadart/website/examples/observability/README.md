# Observability example

An application-owned OTel adapter for llamadart 0.14.0. This is not the optional
companion package tracked in [#696](https://github.com/leehack/llamadart/issues/696).
Core dependencies and runtime behavior are unchanged.

The [guide](../../docs/guides/observability.md) covers signals, setup, backend
limitations, parent context, sampling, privacy, Langfuse and Grafana.

```bash
cd website/examples/observability
dart pub get
dart analyze --fatal-infos
dart test -p vm
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf \
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:14318 \
dart run bin/observe.dart /absolute/path/to/model.gguf
```

Use the repository-pinned Flutter SDK. The CLI uses native Dart; mobile and
browser SDK/export integrations need their own qualification. The adapter
never records prompts, responses, raw errors or model paths. Its explicit
model alias and any session identifier must be approved for export by the app.

The docs build runs resolution, formatting, analysis and tests here. This
package lives under `website/` because the docs lane owns it; it is not a
published companion or part of the root/example workspace manifest. Regenerate
its lockfile with `dart pub get` after a core version bump.
