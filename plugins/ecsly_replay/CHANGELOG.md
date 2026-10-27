# Changelog

## Unreleased

- Checkpoint restore in [ReplayPlayer] defaults to reconcile by `PersistentId`
  (`CheckpointRestoreMode.reconcile`); spawn restore is opt-in.
- Add `ReplayPlayer.seek({tick, eventKey})` convenience API.
- `TransientPolicy` (`keep` default, `despawn` on seek) for non-persistent
  entities; `verifyDeterminism` requires `despawn`.
- Seeking before the first checkpoint reconciles from `initialBaseline` (or an
  empty persisted set); missing checkpoint payload throws instead of no-op.
- `TransientPolicy.despawn` runs before and after forward replay; `verifyDeterminism`
  uses `createColdWorld` (fresh worlds) plus `replayColdCapture` /
  `persistedCapturesMatch`.

## [0.1.0-dev.2](https://github.com/Arenukvern/ecsly/compare/ecsly_replay-v0.1.0-dev.1...ecsly_replay-v0.1.0-dev.2) (2026-10-27)


### Features

* **ecsly_replay:** add replay log, checkpoints, and reconcile restore ([57be21e](https://github.com/Arenukvern/ecsly/commit/57be21ece4ae367c22a7f64fd4ef8d21e138eaf6))
* **ecsly_replay:** transient policy and seek baseline fixes ([6f14a28](https://github.com/Arenukvern/ecsly/commit/6f14a280ff013ad3bfffc414b37320eaab3413a4))
* **ecsly_replay:** world replay log, checkpoints, and seek ([5976a5f](https://github.com/Arenukvern/ecsly/commit/5976a5f782fc87de431dd7b24f34e8c9c9badedf))


### Bug Fixes

* **ecsly_replay:** despawn clean room and isolated cold worlds ([6727859](https://github.com/Arenukvern/ecsly/commit/6727859ab0ae59017af00309e9cdc699689f45e5))
* **ecsly_replay:** reconcile checkpoint restore by default ([3661282](https://github.com/Arenukvern/ecsly/commit/3661282c5861c873e0750094b3ef7710228fa5e6))
* **ecsly_replay:** reconcile checkpoint restore by default ([9f3ed4f](https://github.com/Arenukvern/ecsly/commit/9f3ed4fb07d0f90cc3744c6f9e30c24c024fbe2d))
* **ecsly_replay:** reject createColdWorld returning live world ([5e2d9ee](https://github.com/Arenukvern/ecsly/commit/5e2d9ee56f3387214d24d81a57e7efa3194420c0))

## 0.1.0-dev.1

- Initial public prerelease: append-only replay log, checkpoints, seek by tick
  or opaque event key, and PersistentId-keyed determinism checks.
