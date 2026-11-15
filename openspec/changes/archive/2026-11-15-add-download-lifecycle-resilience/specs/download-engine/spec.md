# Spec Delta

## ADDED Requirements

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
