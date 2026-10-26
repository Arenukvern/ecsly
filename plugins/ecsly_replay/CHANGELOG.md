# Changelog

## Unreleased

- Checkpoint restore in [ReplayPlayer] defaults to reconcile by `PersistentId`
  (`CheckpointRestoreMode.reconcile`); spawn restore is opt-in.
- Add `ReplayPlayer.seek({tick, eventKey})` convenience API.

## 0.1.0-dev.1

- Initial public prerelease: append-only replay log, checkpoints, seek by tick
  or opaque event key, and PersistentId-keyed determinism checks.
