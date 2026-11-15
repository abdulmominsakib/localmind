# download-lifecycle Specification

## Purpose
Make in-flight downloads resilient to app lifecycle events and network loss: backgrounding or losing connectivity pauses transfers gracefully with their progress durable, and returning to the foreground (or regaining connectivity) resumes them automatically when the user opts in.

## Requirements

### Requirement: Background pause
When the app leaves the foreground (lifecycle inactive/hidden/paused) or is detached, the system SHALL gracefully pause every running download task: the transfer stops, all received bytes are retained, and the sidecar lands at the durable offset before the state is set to `paused`.

#### Scenario: iOS app backgrounded mid-download
- **WHEN** the app moves to the background while a task is running
- **THEN** the task reaches `paused` with its partial file and sidecar consistent at the durable offset

### Requirement: Connectivity-loss pause
When the device loses network connectivity, running download tasks SHALL pause automatically with a network-specific reason instead of failing.

#### Scenario: Wi-Fi drops mid-download
- **WHEN** connectivity is lost while a task is running
- **THEN** the task pauses with a network-specific marker rather than entering `failed`

### Requirement: Auto-resume on return
When the app returns to the foreground (or connectivity is restored) and auto-resume is enabled in settings, tasks paused by the system (backgrounding, detachment, connectivity loss) SHALL resume automatically; user-paused and failed tasks SHALL NOT auto-resume. With auto-resume disabled, those tasks stay paused for manual resume.

#### Scenario: Return to foreground with auto-resume on
- **WHEN** the app returns to the foreground with auto-resume enabled and system-paused tasks exist
- **THEN** those tasks re-enter the queue and continue from their recorded offsets; user-paused tasks remain paused

#### Scenario: Auto-resume disabled
- **WHEN** auto-resume is disabled and the app returns to the foreground
- **THEN** system-paused tasks remain paused until the user resumes them manually

### Requirement: Periodic crash-level checkpoints
During a running transfer the engine SHALL persist a checkpoint (sidecar offset advanced to flushed bytes) at a bounded interval (default 8 MB, configurable) through the serialized IO chain, and SHALL write an initial sidecar at enqueue time (offset 0). A hard process kill therefore loses at most one checkpoint interval of progress.

#### Scenario: Hard kill between checkpoints
- **WHEN** the process is killed mid-transfer with the last checkpoint at 16 MB
- **THEN** a later resume continues from at most 8 MB before the highest received byte, never from an inconsistent offset

### Requirement: Network return resume
When connectivity is restored and auto-resume is enabled, tasks that were paused by connectivity loss SHALL resume automatically; with auto-resume disabled they remain paused.

#### Scenario: Connectivity restored with auto-resume on
- **WHEN** connectivity returns while network-paused tasks exist and auto-resume is enabled
- **THEN** those tasks re-enter the queue automatically
