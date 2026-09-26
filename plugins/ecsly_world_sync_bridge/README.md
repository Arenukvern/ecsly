# ecsly_world_sync_bridge

Live World-to-delta bridge for [ecsly](https://pub.dev/packages/ecsly)
worlds: binds a live `ecsly` `World` to an `ecsly_world_sync` `WorldSync`
replica and keeps replicas converging. See
[ADR 0002](../../docs/decisions/0002_live_world_delta_bridge.md) (and ADR
0001 for the kernel-adapter boundary this package builds on).

Merge semantics are **not implemented here** — ordering, version vectors,
dedupe, and folds stay in
[`universal_storage_convergence`](https://github.com/xsoulspace/universal_storage_sync)
(ADR 0011). This package owns only the world→delta capture diff, the wire
envelope, and the anti-entropy schedule.

## What it does

- `WorldSyncBridge` — one live `World` → one `WorldSync`:
  - `emitDeltas()` captures a whole-world snapshot
    (`ecsly_serialization`) and diffs it against the previous capture —
    one `ComponentDelta` op per changed key, `removeDelta` tombstones for
    vanished keys (despawn and component removal included);
  - keys are `<persistentId>/<ComponentType>/<field>` — runtime `Entity`
    handles never travel;
  - `flushObserver` / `attach()` emit deltas on every `World.flush()`
    boundary (chains any observer already registered).
- `WorldSyncMessage` (`VvMessage` / `OpsMessage` / `SnapshotMessage`) —
  wire envelope with a versioned, discriminated JSON codec.
- `WorldSyncTransport` + `LocalSyncHub` — the transport seam and an
  in-memory, explicitly-pumped hub for tests. **No real networking**;
  sockets, relays, and discovery are later phases.
- `WorldSyncDriver` — anti-entropy over a replica + transport + peer set:
  VV exchange, op batches, snapshots for peers the compacted log can no
  longer serve; optional periodic mode; policy compaction via
  `SnapshotPolicy`.

## Not claimed

No kernel→World reverse materialization (peers read the projection; nothing
rebuilds a live World), no presence/ephemeral ops, no rollback/re-sim, no
resource sync. Core `ecsly` and `ecsly_world_sync` are unchanged
dependencies, not surfaces of this package.

## Bootstrap dependency

Same as `plugins/ecsly_world_sync`: the kernel is not on pub.dev yet, so
the pubspec resolves it through a local path override into the sibling
`storage_problem` repo. Remove the override once the kernel publishes.

## Validate

```sh
fvm dart pub get
fvm dart analyze
fvm dart test
```
