# foreground-downloads Specification

## Purpose
Track and drive foreground downloads of curated on-device models (LiteRT-LM via flutter_gemma and MLX via the MLX service), with persisted progress so download state survives app restarts and the UI can show speed/ETA.

## Requirements

### Requirement: Startable per-model download
The system SHALL let the user start a download for any curated model by id; starting SHALL initialize a tracked progress entry (running, 0 progress, declared total bytes) before the transfer begins.

#### Scenario: User starts a curated model download
- **WHEN** the user taps download on a curated model
- **THEN** a progress entry for that model id is created and the underlying service (gemma or MLX) begins transferring

### Requirement: MLX runtime routing
The system SHALL route downloads of models whose runtime is MLX to the MLX service and all other curated models to the flutter_gemma install path.

#### Scenario: MLX model on Apple platform
- **WHEN** the user starts a download for a curated MLX model
- **THEN** the MLX service performs the download and reports progress through the same tracking entry

### Requirement: Persisted progress with speed and ETA
The system SHALL persist each download's status (running/complete/failed), received/total bytes, bytes-per-second and ETA to local storage as it progresses, so the model manager and picker can render progress after restart.

#### Scenario: Progress visible after app restart
- **WHEN** the app is restarted while entries are persisted
- **THEN** the UI can display the last persisted status for each tracked model id

### Requirement: HF token gate
The system SHALL refuse to start a download for a model that declares `requiresHuggingFaceToken` until a Hugging Face token is configured, reporting `missing_huggingface_token` instead of starting.

#### Scenario: Gated model without token
- **WHEN** the user taps download on a token-gated model with no token configured
- **THEN** no download starts and the UI is told `missing_huggingface_token`

### Requirement: Concurrent tracked downloads without queueing
The system SHALL allow multiple curated downloads to run at the same time, each tracked independently by model id (no serialization or queue is imposed).

#### Scenario: Two models downloading together
- **WHEN** the user starts a second curated download while one is running
- **THEN** both progress entries advance independently

### Requirement: Completion and failure handling
The system SHALL mark a finished download complete (full progress, persisted), invalidate the downloaded-models provider, record a review-prompt signal, and clean up the tracking entry; on failure it SHALL persist a failed status with a friendly formatted error.

#### Scenario: Download finishes
- **WHEN** the underlying service reports the transfer finished
- **THEN** the entry is marked complete, the downloaded set refreshes, and the entry is removed from active tracking

#### Scenario: Download fails
- **WHEN** the transfer throws
- **THEN** the entry is marked failed with a formatted error and stops advancing
