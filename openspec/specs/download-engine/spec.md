# download-engine Specification

## Purpose
Provide a shared download engine for Hugging Face model files that can resume interrupted transfers from the exact byte offset, pause and resume on demand, and run queued tasks with bounded concurrency across app restarts.

## Requirements

### Requirement: Range-based resume
The engine SHALL resume an interrupted transfer from the byte offset already present in the retained partial file by sending a `Range` request, and SHALL fall back to restarting from byte 0 (resetting the partial) when the server does not honor the range.

#### Scenario: Resume after interruption
- **WHEN** a task that transferred 40% is resumed and the server supports ranges
- **THEN** the transfer continues from the 40% offset into the same partial file, without re-downloading earlier bytes

#### Scenario: Server without range support
- **WHEN** a resume attempt receives a response that ignores the range
- **THEN** the engine discards the partial file and restarts the transfer from byte 0

### Requirement: Sidecar-bound partial integrity
The engine SHALL bind every partial file to a sidecar record holding the source URL, the server's ETag, the total expected size, and the recorded offset; a partial file SHALL be resumable only when the current response still matches that record, and any mismatch SHALL discard the partial and restart cleanly.

#### Scenario: Source changed between sessions
- **WHEN** the remote file's ETag or size no longer matches the sidecar at resume time
- **THEN** the stale partial is discarded and the download restarts from byte 0 instead of producing a corrupted file

### Requirement: Pause and resume states
The engine SHALL support pausing a running task (stopping the transfer while retaining the partial file and recording state `paused`) and resuming it later; pausing SHALL NOT delete any downloaded bytes.

#### Scenario: User pauses a running download
- **WHEN** the user pauses a task mid-transfer
- **THEN** the transfer stops, all received bytes are retained, and the task state is `paused`

### Requirement: Persisted task queue with bounded concurrency
The engine SHALL persist the task list (source URL, auth requirement, state, progress) across app restarts, SHALL start queued tasks in submission order with at most a bounded number running concurrently (default 2), and SHALL restore interrupted running tasks as resumable after restart.

#### Scenario: Queue survives restart
- **WHEN** the app is killed with queued and running tasks and is relaunched
- **THEN** the task list is restored with states and progress, and running tasks become resumable without re-entering URLs

#### Scenario: Concurrency cap
- **WHEN** more tasks than the concurrency bound are eligible to run
- **THEN** only that many run at once and the rest wait as `queued` in submission order

### Requirement: Dependent task scheduling
The engine SHALL let a task declare a dependency on another task; a dependent task SHALL stay `queued` until its dependency reaches `completed`. When the dependency reaches `failed` or is deleted, the engine SHALL mark dependent tasks `canceled` with the dependency's error surfaced to the UI.

#### Scenario: Projector task waits for its model
- **WHEN** a projector task is enqueued with a dependency on a still-running model task
- **THEN** the projector task remains `queued` and starts only after the model task is `completed`

#### Scenario: Dependency fails
- **WHEN** the dependency task reaches `failed`
- **THEN** dependent tasks become `canceled` carrying the dependency's failure reason, without downloading any bytes

### Requirement: Task lifecycle
The engine SHALL expose lifecycle states `queued`, `running`, `paused`, `failed`, `completed`, `canceled`, where `completed` means the byte transfer finished successfully; any post-transfer processing by consumers is their responsibility, reported back through the engine's state API. Cancel, delete and retry SHALL behave per the scenarios below.

#### Scenario: Cancel keeps bytes
- **WHEN** the user cancels a running task
- **THEN** the task state is `canceled` with its partial file retained, and the task can be resumed or deleted later

#### Scenario: Explicit delete
- **WHEN** the user deletes a task
- **THEN** the task record, partial file and sidecar are removed from the device

#### Scenario: Retry after failure
- **WHEN** the user retries a `failed` task whose sidecar still matches
- **THEN** the transfer reuses the partial file instead of restarting from byte 0

### Requirement: Per-task progress reporting
The engine SHALL report, for every active task, received bytes, total bytes, transfer speed and estimated remaining time, suitable for UI rendering.

#### Scenario: Progress during transfer
- **WHEN** a task is running
- **THEN** observers receive updated received/total bytes with speed and ETA at least on every persisted progress tick

### Requirement: Authenticated transfers
The engine SHALL attach the configured Hugging Face Bearer token to transfers whose task declares it needs authentication, and SHALL surface authentication failures as task failure with a distinct reason.

#### Scenario: Token accepted
- **WHEN** a task requires auth and a valid token is configured
- **THEN** requests carry the Bearer header and the transfer proceeds

#### Scenario: Token rejected
- **WHEN** the server responds 401 or 403 to an authenticated transfer
- **THEN** the task is marked `failed` with an auth-specific reason distinguishable from network errors

### Requirement: Engine-wide lifecycle entry points
The engine SHALL expose engine-wide operations to gracefully pause every running task (`pauseAllRunning`, recording which tasks were system-paused) and to resume exactly the system-paused set (`resumeSystemPaused`); these operations SHALL be distinguishable from user-initiated pause/resume so that user intent is never overridden by lifecycle events.

#### Scenario: System pause then selective resume
- **WHEN** `pauseAllRunning` pauses tasks A and B while the user has task C paused manually, and `resumeSystemPaused` runs afterwards
- **THEN** A and B re-enter the queue and C stays paused

### Requirement: Serialized transfer checkpoints
The engine SHALL, while a transfer runs, persist a checkpoint (flush + sidecar offset update) at a bounded byte interval through the serialized IO chain, and SHALL write an initial sidecar (offset 0) when a task with no prior sidecar enters the running state.

#### Scenario: Checkpoint cadence
- **WHEN** a transfer progresses past the checkpoint interval with the app in the foreground
- **THEN** the sidecar offset advances to the flushed byte count without pausing the transfer

### Requirement: Network-pause reason
Tasks paused by connectivity loss SHALL carry a network-specific reason in their error field (distinct from user pause and from failures), and SHALL be resumable like any paused task.

#### Scenario: Network reason recorded
- **WHEN** connectivity loss pauses a running task
- **THEN** the task state is `paused` with a network-specific reason in its error field, and a later resume proceeds from the durable offset
