# ecsly_world_sync_bridge

Live World-to-delta bridge for [ecsly](https://pub.dev/packages/ecsly)
worlds: binds a live `ecsly` `World` to an `ecsly_world_sync` `WorldSync`
replica and keeps replicas converging. See
[ADR 0002](../../docs/decisions/0002_live_world_delta_bridge.md) (and ADR
0001 for the kernel-adapter boundary this package builds on).

Merge semantics are **not implemented here** — ordering, version vectors,
dedupe, and folds stay in
[`universal_storage_convergence`](https://github.com/xsoulspace/universal_storage_sync)
(ADR 0011), and since [ADR
0004](../../docs/decisions/0004_convergence_session_adoption.md) the
anti-entropy protocol itself is the session core's
(`universal_storage_convergence_session`), not this package's. This package
owns only the world→delta capture diff and the exchange schedule.

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
- `WorldSyncSession` — the anti-entropy schedule over one replica + the
  foundation's `MeshTransport`/`MeshSession` radio
  (`universal_storage_mesh_transport`): each round runs the session
  protocol's symmetric script (hello → vv → delta, wire =
  `MeshSyncProtocol`), plans what to send with the session core's
  `DeltaPlanner` against the replica's `DeltaReplica` seam, applies the
  peer's delta, and compacts on the session core's `shouldCompact` policy.
  Periodic mode (`start`/`stop`/`tick`) survives; inbound (peer-dialed)
  sessions run the same script, so mutual dials are safe. Ordering, dedupe,
  folding, staleness, and the wire codec are never re-implemented here.
- The compaction policy surface (`shouldCompact`, `defaultMaxLogOps`,
  `defaultMinInterval`) is re-exported from the session core — it is that
  package's type now (ADR 0004).

## Not claimed

No networking *of its own*: pairing, discovery, framing, LAN sockets, and
relays are `universal_storage_mesh_transport`'s domain (its `FakeMeshPair`
stands in for tests); no kernel→World reverse materialization (peers read
the projection; nothing rebuilds a live World), no presence/ephemeral ops,
no rollback/re-sim, no resource sync. Core `ecsly` and `ecsly_world_sync`
are unchanged dependencies, not surfaces of this package.

## Bootstrap dependency

Same as `plugins/ecsly_world_sync`: the kernel and the session core are not
on pub.dev yet, so the workspace resolves them (and the session core's
transitive foundation packages) through the path overrides declared in
`plugins/ecsly_world_sync/pubspec.yaml`. Remove those overrides once the
kernel and session core publish.

## Validate

```sh
fvm dart pub get
fvm dart analyze
fvm dart test
```
