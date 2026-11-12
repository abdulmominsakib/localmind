---
title: Examples Overview
---

The repository ships multiple examples for different integration styles.

## Example catalog

- [Basic App](./basic-app): minimal Dart console usage.
- [Chat App](./chat-app): Flutter UI with settings and streaming.
- [llamadart CLI](./llamadart-cli): llama.cpp-style command-line workflow.
- [llamadart Server](./llamadart-server): OpenAI-compatible local HTTP server.

## Which one should I start with?

- Learn API surface first: start with Basic App.
- Build a product UI: start with Chat App.
- Need terminal workflow parity: start with llama CLI.
- Need HTTP integration for tools/agents: start with llamadart Server.

## Global example requirements

- Dart SDK `>= 3.10.7`
- Flutter SDK `>= 3.38.0` for Flutter examples
- Internet on first run (runtime bundle resolution)
