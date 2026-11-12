## 0.1.0 (unreleased)

- First version: `ModelStore`, a `ModelDownloadManager` that keeps a model and
  its projector as one entry, records which apps reference it, and deletes
  files only when no app does.
- A failed `ensure` no longer restores a reference that another process of
  the same app released meanwhile, and reports its own error when the store
  lock is unavailable afterwards.
