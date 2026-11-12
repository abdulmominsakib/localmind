# Retained Dart transport fixtures

These are unchanged source-only, model-free outputs from the actual
`test/support/serialize_s24_transport.dart` serializer and Dart capture codec,
retained from the physical-LF framing investigation on 2026-11-04. The source
serializer and codec are pinned by this repository revision. They are synthetic
transport data, never device, runtime, semantic or GPU qualification evidence.

The source evidence directory was
`litert019-s24-framing-fix-evidence/causal-journals-r2`; its causal report recorded
106 complete records and 20 producer PASS statuses for each output. Each Unicode
directory contains original LF/CRLF, compact/base64 journal bytes and independently
retained child stdout/stderr. `manifest.json` seals every original copied file.
The tests verify hashes and decode these bytes directly without invoking Dart.

Regenerate only as an explicitly authorized fixture update by passing the rows
from `s24_decoder_fixtures.valid` and the metadata-only binding to the serializer
for codepoints 133, 8232 and 8233, both encodings and both line endings. Preserve
binary framing and update the manifest; never promote these fixtures to a
hardware result.
