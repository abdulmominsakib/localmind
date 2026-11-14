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
The system SHALL download the GGUF (and optional projector) through the download engine into a retained `.part` temp file, honoring an optional Hugging Face Bearer token and redirects; the engine validates resume consistency via its sidecar record. After download completes, the system SHALL validate the file is a non-empty GGUF and atomically rename it to its final name before persisting import metadata.

#### Scenario: Successful import
- **WHEN** the download completes and passes GGUF validation
- **THEN** the `.part` file is renamed to the final model file, import metadata (id, name, path, size, source URL) is persisted, and the model appears in the imported list

#### Scenario: Network failure mid-download
- **WHEN** the connection fails or the app is killed before completion
- **THEN** the task becomes resumable with the partial file and sidecar retained, and a later resume continues from the recorded offset instead of restarting from byte 0

### Requirement: Vision projector pairing
The importer SHALL accept an optional projector (mmproj) GGUF URL, download and validate it the same way, pair it with the model in persisted metadata, and expose it to the engine as the model's multimodal projector.

#### Scenario: Import with projector
- **WHEN** the user fills both the model URL and a projector URL and both downloads succeed
- **THEN** the saved metadata carries both paths and the model is listed as vision-capable

### Requirement: Queued resumable import
GGUF imports SHALL run as tasks of the download engine instead of a modal single-flight transfer: submitting an import SHALL enqueue it (with its optional projector as a dependent follow-up task of the same import), multiple imports SHALL queue with bounded concurrency, and the user SHALL be able to pause, resume, cancel (retaining downloaded bytes) or delete each import task from a download list without re-entering URLs. The engine task's `completed` state means the byte transfer finished; the import itself is published only after the transferred file passes GGUF validation and is renamed into place, at which point import metadata is persisted. A validation failure after transfer SHALL mark the engine task `failed` with the partial retained for retry, SHALL cancel dependent tasks of the same import with that reason, and SHALL NOT persist import metadata.

#### Scenario: Import queued behind another
- **WHEN** the user submits a second GGUF import while one is downloading
- **THEN** the second import joins the queue as `queued` and starts automatically when a slot frees, without blocking the UI

#### Scenario: User pauses and resumes mid-download
- **WHEN** the user pauses a running import and resumes it later
- **THEN** the transfer continues from the recorded offset with the partial file retained, and the model is published exactly once after validation

#### Scenario: User cancels mid-download
- **WHEN** the user cancels a running import
- **THEN** the task state is `canceled` with downloaded bytes retained, and no metadata is saved unless the import later completes

#### Scenario: Validation fails after transfer
- **WHEN** the transferred file does not pass GGUF validation
- **THEN** the task is marked `failed` with the partial retained for retry, dependent tasks of the same import become `canceled` with that reason, and no import metadata is persisted

### Requirement: Optional HF token entry
The system SHALL allow the user to supply a Hugging Face access token in settings and SHALL send it as a Bearer header on HF downloads when present.

#### Scenario: Gated repo with token configured
- **WHEN** a download requires auth and a token is configured
- **THEN** the request includes `Authorization: Bearer <token>` and the download proceeds
