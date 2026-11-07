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

## Plugin

`WorldSyncBridgePlugin` wires a host-built replica (and optionally a
host-built session) into a world in one call. Kernel identity and pairing
stay host decisions; the plugin owns the world-side attachment:

```dart
final sync = WorldSync(actorId: 'peer-a');
world.addPlugin(WorldSyncBridgePlugin(sync: sync));

// Every world.flush() now emits deltas into the replica.
// Projection reads and manual emits go through the resource:
final bridge = world.getResource<WorldSyncBridgeResource>().bridge;
```

Pass `attachFlushObserver: false` for inert installs (host calls
`bridge.emitDeltas()` on its own cadence), and a `session:` built over the
mesh radio to keep anti-entropy reachable from the same resource.
`removePlugin` detaches the observer, stops the session, and removes the
resource.

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

## Boundaries

No networking *of its own*: pairing, discovery, framing, LAN sockets, and
relays are `universal_storage_mesh_transport`'s domain (its `FakeMeshPair`
stands in for tests); no kernel→World reverse materialization (peers read
the projection; nothing rebuilds a live World), no presence/ephemeral ops,
no rollback/re-sim, no resource sync. Core `ecsly` and `ecsly_world_sync`
are unchanged dependencies, not surfaces of this package.

## Dependencies

Same as `plugins/ecsly_world_sync`: the kernel, the session core, and the
mesh transport (`universal_storage_mesh_transport`) are published on pub.dev
(`0.1.0-dev.1`, 2026-10-12) and resolve as ordinary hosted dependencies; the
bootstrap path overrides are removed.

## Status and validate

In the repo, in active development; not published (`publish_to: none`).
Depend on it through the pub workspace inside this repo, or via a git
dependency outside it.

```sh
dart pub get        # from the repo root (pub workspace)
cd plugins/ecsly_world_sync_bridge
dart analyze
dart test           # 19 tests
```
