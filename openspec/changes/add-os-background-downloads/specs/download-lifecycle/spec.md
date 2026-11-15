# Spec Delta

## MODIFIED Requirements

### Requirement: Background pause
When the app leaves the foreground (lifecycle inactive/hidden/paused) or is detached, the system SHALL gracefully pause every running download task that executes on the in-app path (drain the IO chain, close the sink, land the sidecar at the durable offset before the state is set to `paused`); tasks handed off to the OS downloader SHALL be exempt and continue downloading in the background.

#### Scenario: iOS app backgrounded mid-download
- **WHEN** the app moves to the background while an in-app task is running
- **THEN** the task reaches `paused` with its partial file and sidecar consistent at the durable offset

#### Scenario: OS-managed task keeps downloading
- **WHEN** the app moves to the background while an OS-managed task runs
- **THEN** the task stays `running` and the OS continues the transfer
