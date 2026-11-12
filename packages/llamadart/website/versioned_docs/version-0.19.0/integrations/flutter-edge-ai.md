---
title: Flutter Edge AI with GGUF
sidebar_label: Flutter Edge AI
description: Where the upstream flutter_edge_ai_llama connector stands and which llamadart version it requires.
---

Flutter Edge AI owns installation, active-model selection and app chat lifecycle.
Its optional [`flutter_edge_ai_llama`](https://pub.dev/packages/flutter_edge_ai_llama)
provider uses llamadart for GGUF generation. The connector lives in
[DenisovAV/flutter_edge_ai](https://github.com/DenisovAV/flutter_edge_ai/tree/main/packages/flutter_edge_ai_llama)
and is not part of this repository.

## Version boundary

`flutter_edge_ai_llama 0.1.0` is on pub.dev (checked 2026-11-08). It depends on
`flutter_edge_ai ^2.6.0` and requires exactly `llamadart >=0.17.5 <0.17.6`, so
it does not resolve alongside llamadart 0.18.
For the connector, follow its
[README](https://github.com/DenisovAV/flutter_edge_ai/blob/main/packages/flutter_edge_ai_llama/README.md)
and [platform guide](https://github.com/DenisovAV/flutter_edge_ai/blob/main/packages/flutter_edge_ai_llama/doc/platforms.md),
including its llamadart-specific setup; llamadart's build hook settings belong in
the application root.

To use llamadart 0.18 features, call llamadart directly or through
[Genkit](./genkit) until the connector widens its constraint.

## Combining with LiteRT-LM

Select `llamadart_native_runtimes: [llama_cpp]` when `flutter_edge_ai_litertlm`
is also in the app. Loading llamadart's LiteRT-LM distribution alongside it can
cause native symbol and library collisions. See
[Alongside Flutter Edge AI](../platforms/native-build-hooks#alongside-flutter-edge-ai).
