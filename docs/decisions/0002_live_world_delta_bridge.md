# ADR 0002: the live World→delta bridge exists as `ecsly_world_sync_bridge`; structure syncs as keyed state, and the driver owns anti-entropy

- Status: Accepted
- Date: 2026-09-26
- North Star impact: `sub_star` (new plugin `plugins/ecsly_world_sync_bridge`;
  global ownership table unchanged until the surface graduates)
- Builds on: [ADR 0001][adr0001] (world sync over the convergence kernel) and
  [convergence kernel ADR 0011][k0011]

[adr0001]: 0001_world_sync_over_convergence_kernel.md
[k0011]: https://github.com/xsoulspace/universal_storage_sync/blob/main/dart_flutter_packages/docs/decisions/0011_convergence_kernel_dual_mode.md

## Context

ADR 0001 shipped the world-sync adapter (`plugins/ecsly_world_sync`) over the
convergence kernel but explicitly deferred the "live World→delta bridge":
nothing turned a running `ecsly` `World` into `ComponentDelta`s. Two facts
drove the deferral, and both still hold — this ADR records how the bridge
lives with them:

- Core ecsly has change detection **only for structure**
  (`World.structuralRevision`, bumped on spawn/despawn/add/remove). There is
  no per-component data-mutation hook to subscribe to.
- `ecsly_serialization` already owns the identity model and a capture shape:
  `captureWorldSnapshot` produces a versioned `WorldSnapshot` over
  `PersistentId`-tagged entities with per-entity `EntityEntry{persistentId,
  components, columns}`.

A bridge that watched structure alone would silently drop data-only writes;
one that re-derived its own identity model would drift from serialization's.
Both risks disappear if the bridge is a **capture differ**: reuse the
snapshot capture verbatim, diff consecutive captures, and map each changed
key onto the delta vocabulary ADR 0001 already fixed.

## Decision

### 1. The bridge is a flush-boundary capture diff

`WorldSyncBridge` binds one live `World` to one `WorldSync`. Each
`emitDeltas()` runs `captureWorldSnapshot(world)` and diffs the capture
against the previous capture kept internally (first call emits everything):

- **Key mapping** (derived from the capture grammar in
  `ecsly_serialization`'s column capture): `entityKey` is the
  `PersistentId` value in string form; `component` is the component **type
  name**, resolved by reverse-mapping the world-local column id prefix
  (`{componentId}_{offset}` / `obj_{componentId}`) through
  `WorldSnapshot.componentIds`; `field` is the column offset (`'0'`,
  `'1'`, …) or `'obj'` for codec-captured object components. The result is
  ADR 0001's `<entityKey>/<component>/<field>` — runtime `Entity` handles
  never appear in keys, and the same component type maps to the same key on
  every replica even though `ComponentId`s are world-local.
- **Values** are the raw captured column values (nums) or the lossless
  `{'type', 'value'}` codec map for object components — JSON-encodable, and
  `WorldSync` JSON-encodes them into kernel ops as before.
- **Structure syncs as keyed state.** Spawn and despawn are not
  special-cased: a spawn shows up as new keys (deltas), a despawn or
  component removal as vanished keys (`WorldSync.removeDelta` tombstones).
  Key presence *is* the structure; no separate structural channel exists.
- **One op per changed key**, decided by structural equality of captured
  values; an unchanged world re-emits nothing (idempotent in ops, not in
  capture cost).
- **The `structuralRevision` is not used as a skip gate.** It bumps only on
  structural changes, so gating diffs on it would silently drop data-only
  writes, and there is no data-mutation hook to OR with it. Every emit pays
  a full capture plus a full key diff — O(entities × columns). If that
  becomes hot, the fix is change detection in core ecsly, not a heuristic
  here.
- **Liveness** rides the flush boundary: the bridge exposes a
  `WorldFlushObserver` whose `onFlushEnd` calls `emitDeltas()`. `World` has a
  single observer slot, so attaching chains and detaching restores any
  previously registered observer; capture's internal `world.flush()` is
  guarded against re-entrant emission. Periodicity is deliberately not part
  of the bridge (the driver owns scheduling).

### 2. Wire, transport, and anti-entropy driver

- `WorldSyncMessage` is a sealed envelope over the three kernel payloads —
  `VvMessage`, `OpsMessage`, `SnapshotMessage` — with a `type` discriminator
  and a format version `v`; unknown discriminators and unsupported versions
  are rejected, never guessed at. The JSON round-trip is the deep-copy rule
  (same discipline as ADR 0001's `FakeTransport`).
- `WorldSyncTransport` is the seam (`send(toPeerId, message)` +
  `Stream` of `(fromPeerId, message)`); the only bundled implementation is
  `LocalSyncHub`/`LocalSyncTransport`, an in-memory, explicitly-pumped hub
  for tests. Message copies share no mutable state.
- `WorldSyncDriver` runs anti-entropy over a replica + transport + peer set:
  `tick()` broadcasts the replica's version vector; an inbound vv is answered
  with `opsFor(theirVv)`, or — when the log can no longer serve the peer
  (`needsSnapshotFor`) — with `snapshotFor()`. Inbound ops fold via
  `applyRemote`; inbound snapshots go through `adoptSnapshot`, whose kernel
  staleness rule makes over-sending safe. Ordering, dedupe, and merge
  semantics stay in the kernel; the driver only decides *when* to send what.
- `SnapshotPolicy` is the parent-chosen compaction policy (ADR 0001 §2 kept):
  compact when the pending log exceeds `maxLogOps` (default 512) or when it
  is non-empty and `minInterval` (default 5 minutes) elapsed since the
  owner's last compaction; an empty log never compacts. The policy is pure;
  the driver tracks the timestamp and executes `sync.compact()`.

### 3. Bootstrap constraint (unchanged, recorded honestly)

The kernel is still not published. `ecsly_world_sync_bridge` declares
`universal_storage_convergence: ^0.1.0-dev.1` (the long-term contract) and
resolves it through the same workspace-level `dependency_overrides` path
entry into the sibling `storage_problem` repo that
`plugins/ecsly_world_sync/pubspec.yaml` carries. It does not repeat the
override — pub workspaces share one resolution and reject the same override
declared by two members.

## Non-claims

- **No kernel→World reverse materialization.** A remote replica converges on
  the *projection*; nothing rebuilds a live `World` from kernel state
  (a local world and its replica's projection can legitimately differ —
  LWW means a local stale write loses). Restore-from-snapshot into a live
  world remains `ecsly_serialization`'s separate, deliberate act.
- **No presence / ephemeral state.** Kernel ADR 0029's ephemeral ops are
  untouched, as in ADR 0001.
- **No rollback / re-simulation.** Deterministic replay stays out of scope.
- **No real networking.** `LocalSyncHub` is in-memory and explicit; sockets,
  relays, discovery, and wire security are later phases.
- **No resource sync.** `WorldSnapshot.resources` is not diffed;
  `ComponentDelta` is entity-scoped. A resource namespace would be a new
  key-space decision, taken separately.
- **`ecsly_world_sync` keeps its charter.** The kernel adapter still imports
  no core ecsly; the bridge is a separate package that depends on *both* and
  owns only the translation and the schedule. Core ecsly and
  ecsly_serialization are unchanged dependencies.

## Consequences

- ecsly worlds gain flush-granularity replication without core-runtime
  changes; two live worlds converge through the driver under shuffled
  delivery, despawns tombstone correctly, and compacted replicas serve
  snapshots to fresh peers (suite in
  `plugins/ecsly_world_sync_bridge/test`).
- Entities with zero captured columns (no SoA fields, no codec'd object
  components) are invisible to the bridge — capture skips them, so neither
  spawns nor despawns of such entities sync. Register a codec if they must.
- Every `emitDeltas` pays a full capture + diff; callers control the
  frequency via the flush boundary. The known optimization path (core ecsly
  change detection) is recorded above rather than worked around here.
- Kernel publication removes the cross-repo path override in
  `plugins/ecsly_world_sync` (and with it this package's bootstrap note).
