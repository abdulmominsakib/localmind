# on-device-gguf-import Specification

## Purpose
Let the user bring arbitrary GGUF models (optionally with a vision projector) onto the device from Hugging Face so they can be run by the on-device llama.cpp engine (llamadart), without leaving the app.

## Requirements

### Requirement: Official Hugging Face GGUF URL validation
The importer SHALL accept only HTTPS URLs pointing at a `.gguf` file hosted on `huggingface.co` / `hf.co` under an official resolve path, and SHALL reject other hosts, non-file URLs, and empty input with a localized error.

#### Scenario: Direct resolve URL accepted
- **WHEN** the user submits `https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF/resolve/main/LFM3-1.7B-Q4_K_M.gguf`
- **THEN** the import starts and the file name is derived from the URL

#### Scenario: Non-HF host rejected
- **WHEN** the user submits a URL whose host is not huggingface.co/hf.co
- **THEN** the import is rejected with the "only official Hugging Face GGUF URLs" error and nothing is downloaded

#### Scenario: Shorthand repo path accepted
- **WHEN** the user submits an owner/repo/file path without a scheme (e.g. `LiquidAI/LFM3-1.7B-GGUF/resolve/main/LFM3-1.7B-Q4_K_M.gguf`)
- **THEN** it is normalized to `https://huggingface.co/…` and treated like an explicit HTTPS URL

### Requirement: Authenticated download to temp file with atomic publish
The system SHALL download the GGUF (and optional projector) over a single HTTP connection into a `<target>.part` temp file, honoring an optional Hugging Face Bearer token and redirects, then validate the file is a non-empty GGUF and atomically rename it to its final name before persisting import metadata.

#### Scenario: Successful import
- **WHEN** the download completes and passes GGUF validation
- **THEN** the `.part` file is renamed to the final model file, import metadata (id, name, path, size, source URL) is persisted, and the model appears in the imported list

#### Scenario: Network failure mid-download
- **WHEN** the connection fails or times out before completion
- **THEN** the `.part` file is deleted, no metadata is persisted, and a friendly error is shown (the next attempt restarts the download from byte 0)

### Requirement: Vision projector pairing
The importer SHALL accept an optional projector (mmproj) GGUF URL, download and validate it the same way, pair it with the model in persisted metadata, and expose it to the engine as the model's multimodal projector.

#### Scenario: Import with projector
- **WHEN** the user fills both the model URL and a projector URL and both downloads succeed
- **THEN** the saved metadata carries both paths and the model is listed as vision-capable

### Requirement: Cancellable single-flight import
The system SHALL run at most one Hugging Face GGUF import at a time from the modal import dialog, SHALL stream received/total byte progress to the dialog, and SHALL let the user cancel; cancelling or closing the dialog aborts the transfer via a cancellation token and discards the partial file.

#### Scenario: User cancels mid-download
- **WHEN** the user taps "cancel import" while downloading
- **THEN** the transfer aborts, the partial `.part` file is deleted, a "canceled" message is shown, and no metadata is saved

### Requirement: Optional HF token entry
The system SHALL allow the user to supply a Hugging Face access token in settings and SHALL send it as a Bearer header on HF downloads when present.

#### Scenario: Gated repo with token configured
- **WHEN** a download requires auth and a token is configured
- **THEN** the request includes `Authorization: Bearer <token>` and the download proceeds
