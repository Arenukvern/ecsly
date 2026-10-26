# Changelog

## Unreleased

- Add `WorldSnapshotRestoreMode.reconcile` and `reconcileWorldSnapshot` for
  in-place restore by `PersistentId` (component set reconciliation, despawn
  absent persisted entities, leave non-persistent entities untouched).

## 0.1.0-dev.1

- Initial public prerelease of JSON world snapshots for ecsly (resources,
  entities, and SoA component columns).
