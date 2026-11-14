# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: Cancellable single-flight import`
- TO: `### Requirement: Queued resumable import`

## MODIFIED Requirements

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

### Requirement: Authenticated download to temp file with atomic publish
The system SHALL download the GGUF (and optional projector) through the download engine into a retained `.part` temp file, honoring an optional Hugging Face Bearer token and redirects; the engine validates resume consistency via its sidecar record. After download completes, the system SHALL validate the file is a non-empty GGUF and atomically rename it to its final name before persisting import metadata.

#### Scenario: Successful import
- **WHEN** the download completes and passes GGUF validation
- **THEN** the `.part` file is renamed to the final model file, import metadata (id, name, path, size, source URL) is persisted, and the model appears in the imported list

#### Scenario: Network failure mid-download
- **WHEN** the connection fails or the app is killed before completion
- **THEN** the task becomes resumable with the partial file and sidecar retained, and a later resume continues from the recorded offset instead of restarting from byte 0
