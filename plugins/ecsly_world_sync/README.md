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
Since [ADR 0004](../../docs/decisions/0004_convergence_session_adoption.md)
it also consumes the session core
(`universal_storage_convergence_session`): `WorldSync` conforms to the
core's `DeltaReplica` seam (so the shared `DeltaPlanner` can plan against
it) and carries an HLC **receive watermark** — every remote op HLC and
adopted snapshot `createdAt` raises it, and local writes are floored above
it, so a local write issued after folding a remote op with an ahead wall
clock wins LWW instead of losing forever.

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

The kernel and the session core are not on pub.dev yet; the pubspec resolves
them (plus the session core's transitive foundation packages) through local
path overrides into the sibling `storage_problem` repo. Remove the overrides
once those packages publish (ADR 0001 §3, ADR 0004).

## Validate

```sh
flutter pub get   # workspace resolution (workspace contains Flutter packages)
dart analyze
flutter test      # `dart test` is blocked by the workspace's Flutter example package
```
