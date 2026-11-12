---
title: Examples overview
sidebar_label: Overview
description: The example apps in the llamadart repository, from Dart console apps to a Flutter chat app, a decision-model game, a CLI, a server, a coding agent and a LoRA training notebook.
---

The repository ships runnable examples under `example/`, one per integration
style.

## Example catalog

- [Basic app](./basic-app): Dart console apps for chat, embeddings, SQLite
  vector retrieval and decision models.
- [Chat app](./chat-app): Flutter chat app with a model library, runtime
  controls, multimodal input and speech.
- [Laya Tetris](./laya-tetris): Flutter game played in real time by a
  decision model.
- [Laya Command Bar](./laya-command-bar): Flutter text field that a decision
  model, an embedding model or a small LLM reshapes as you type.
- [llama.cpp-Style CLI](./llamadart-cli): terminal chat with llama.cpp-style
  arguments and parity tooling.
- [OpenAI-compatible server](./llamadart-server): OpenAI-style HTTP API over
  an on-device model.
- [TUI coding agent](./tui-coding-agent): `nocterm` terminal coding agent with
  four tools.
- [LoRA Training Notebook](https://github.com/leehack/llamadart/blob/main/example/training_notebook/lora_training.ipynb):
  a Jupyter notebook that fine-tunes a LoRA adapter for Qwen2.5 0.5B Instruct
  with Hugging Face `peft` and converts it to GGUF for
  [LoRA adapters](../guides/lora-adapters).

## Which one should I start with?

- Learn the API surface: Basic App.
- Try embeddings: Basic App embedding CLI.
- Build retrieval with a vector database: Basic App SQLite vector CLI.
- Learn decision models: Basic App decision CLI.
- Build a product UI: Chat App.
- Run decision models in a real-time app: Laya Tetris.
- Drive interactive UI from a classifier: Laya Command Bar.
- Keep a llama.cpp terminal workflow: llama.cpp-Style CLI.
- Serve tools and agents over HTTP: OpenAI-Compatible Server.
- Build an interactive coding agent in the terminal: TUI Coding Agent.
- Train your own adapter: LoRA Training Notebook.

## Global example requirements

- Dart SDK `>= 3.10.7`
- Flutter SDK `>= 3.38.0` for Flutter examples
- Flutter Apple example builds that use SwiftPM companion packages require
  deployment targets of iOS `16.4` or macOS `14.0` or newer
- Internet on first run (runtime bundle resolution)
- The Chat App enables both native runtime families, llama.cpp and LiteRT-LM,
  because it demonstrates GGUF and `.litertlm` models.
