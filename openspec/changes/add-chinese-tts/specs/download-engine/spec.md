# download-engine Specification (Delta)

## ADDED Requirements

### Requirement: TTS bundle task kind with post-transfer extraction
The engine SHALL accept tasks of kind `ttsBundle` whose payload is a compressed archive downloaded to the engine's work directory; the task SHALL reach `completed` only after the consumer's post-transfer processing (archive extraction into the TTS model directory, bundle validation, archive cleanup) succeeds, and SHALL be marked `failed` with partial extraction cleaned up when that processing errors.

#### Scenario: Extraction failure fails the task cleanly
- **WHEN** a `ttsBundle` transfer completes but archive extraction raises
- **THEN** the task is marked `failed` with the extraction error, no bundle is registered as installed, and partial extraction output is removed

#### Scenario: Archive cleanup on success
- **WHEN** a `ttsBundle` task completes its post-transfer extraction and validation
- **THEN** the downloaded archive is deleted and only the extracted bundle files remain
