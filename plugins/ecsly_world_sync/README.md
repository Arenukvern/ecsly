# ecsly_world_sync

World-sync plugin for [ecsly](https://pub.dev/packages/ecsly) worlds:
converts world event-channel events and component deltas into
convergence-kernel ops, and folds remote ops back into a world-state
projection.

Merge semantics are **not implemented here**. This package consumes
[`universal_storage_convergence`](https://github.com/xsoulspace/universal_storage_sync)
(ADR 0011): the kernel owns ordering, hybrid logical clocks, version vectors,
dedupe, and fold rules; this plugin only chooses the strategy (LWW map by
default), the key mapping, and the compaction policy. The kernel never learns
about worlds. See [ADR 0001](../../docs/decisions/0001_world_sync_over_convergence_kernel.md).

## What it does

- `WorldSync` — one replica of a world over one kernel `ConvergenceDoc`:
  - `applyDelta` / `applyEvent` → one kernel op per keyed piece of state;
  - `removeDelta` / `removeEvent` → kernel tombstones;
  - `applyRemote` → folds remote ops (kernel dedupe + HLC ordering);
  - `projection` → read-only world state (tombstones excluded);
  - `opsFor(vv)` / `snapshotFor` / `adoptSnapshot` / `compact` → dual-mode
    anti-entropy, all executed by the kernel.
- `FakeTransport` — in-memory, test-only transport. **No real networking**;
  sockets, presence, rollback/re-simulation, and host integration are later
  phases (ADR 0001 non-claims).

## Identity model

Keys name state by stable identity —
`<entityKey>/<component>/<field>` and `event/<name>/<key>` — matching the
`ecsly_serialization` rule: runtime `Entity` handles are world-local and
never travel.

## Bootstrap dependency

The kernel is not on pub.dev yet; the pubspec resolves it through a local
path override into the sibling `storage_problem` repo. Remove the override
once the kernel publishes (ADR 0001 §3).

## Validate

```sh
flutter pub get   # workspace resolution (workspace contains Flutter packages)
dart analyze
flutter test      # `dart test` is blocked by the workspace's Flutter example package
```
