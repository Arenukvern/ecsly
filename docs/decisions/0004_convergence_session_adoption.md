# ADR 0004: world sync adopts the convergence session core; the bridge sheds its own anti-entropy stack

- Status: Accepted
- Date: 2026-10-11
- North Star impact: `clarifies` (no new owned surface; existing plugins
  re-substrate onto the foundation's session core)
- Builds on: [ADR 0001][adr0001], [ADR 0002][adr0002], and
  [convergence session ADR 0063][k0063] in the `storage_problem` repo
  (`dart_flutter_packages/docs/decisions/`)

[adr0001]: 0001_world_sync_over_convergence_kernel.md
[adr0002]: 0002_live_world_delta_bridge.md
[k0063]: https://github.com/xsoulspace/universal_storage_sync/blob/main/dart_flutter_packages/docs/decisions/0063_convergence_session_extraction.md

## Context

ADR 0002 shipped the bridge with its own anti-entropy stack
(`WorldSyncDriver`, `WorldSyncMessage`, `WorldSyncTransport`,
`LocalSyncHub`, `SnapshotPolicy`) — a parallel implementation of the
exchange mesh already runs, over a different wire. The repo layering law
is now explicit: universal_storage is the foundation, ecsly is the ECS
framework with plugins on top of it, so session mechanics belong to the
foundation and ecsly keeps only ECS translation and policy.

The cost of the duplication is no longer hypothetical: `WorldSync`
never ticks its HLC on receive, so a local write issued after folding a
remote op with an ahead wall clock loses LWW to a causally older write.
last_answer hand-patches the floor in its app (`mesh_task_board.dart`,
"the ecsly repo is not patched"). dfp ADR 0063 extracted the session
core — wire codec, `DeltaPlanner`, `ReceiveWatermark`,
`SnapshotPolicy` — into `universal_storage_convergence_session` so both
parents share one implementation.

## Decision

### 1. `WorldSync` is a session-core replica

`ecsly_world_sync` conforms to the session package's replica interface
(it already delegates every hard part to the kernel) and adopts
`ReceiveWatermark`: received op HLCs and adopted snapshot `createdAt`
raise the watermark; local `applyDelta`/`applyEvent`/`removeDelta` floor
their tick time strictly above it. This closes the receive-watermark gap
at the right layer. The public `WorldSync` API (constructor,
`applyDelta`, `applyRemote`, `projection`, JSON round-trip) is
source-compatible — last_answer's task board keeps compiling.

### 2. The bridge sheds its parallel stack

`ecsly_world_sync_bridge` deletes `WorldSyncDriver`, `WorldSyncMessage`,
`WorldSyncTransport`, `LocalSyncHub`, and the local `SnapshotPolicy`
(now the session package's type). Anti-entropy is driven by the shared
`DeltaPlanner` over a thin adapter from the session wire to the
foundation's `MeshTransport`/`MeshSession` (framing, LAN WebSocket,
relay, and fakes come from `universal_storage_mesh_transport`; the
in-memory `FakeMeshPair` replaces `LocalSyncHub` in tests). ecsly
speaks the mesh wire planes, so one `ClaimingMeshTransport` server can
later route both worlds' and documents' traffic.

### 3. Phase 3 stays deferred by design

The ECS world as a mesh *member* (bridge diff exposed as a
`MemberCodec`, a pulse system in `ecsly_flutter`/`ecsly_app` over
`Pulseable`) is recorded as the target shape but lands only when a game
needs it. Nothing in this ADR wires ecsly into dfp's mesh sessions yet.

## Non-claims

- **No kernel or session-core changes.** Both stay dfp-owned; ecsly is a
  consumer (ADR 0001 boundary unchanged).
- **No `live_apply` porting.** Undo in replicated worlds is
  compensating ops at the `WorldSync` layer, never file-inverse replay;
  `universal_storage_live_apply` stays a dfp-side, single-writer
  mechanism.
- **No last_answer code changes in this repo.** Its task-board watermark
  floor becomes redundant but harmless; removing it is that app's call.
- **No core ecsly changes.** The bridge remains the only plugin that
  touches core (`World.flushObserver`), unchanged.
- **Bootstrap constraint.** The session package, like the kernel, is not
  published yet; `plugins/ecsly_world_sync/pubspec.yaml` extends the
  existing `dependency_overrides` path entry to it, and the bridge
  relies on the shared workspace resolution. Both overrides are removed
  at publish time, together.
  *Resolution (2026-10-12): kernel, session core, world layer, and mesh
  transport all published at 0.1.0-dev.1; the overrides are removed and
  all three sync plugins resolve hosted.*

## Consequences

- The bridge loses its driver/message/transport/policy (~500 lines) and
  keeps only what is genuinely ecsly's: capture-diff translation,
  ECS vocabulary, schedule.
- Watermark correctness lands once, in the foundation; the ahead-clock
  LWW scenario joins this repo's property-test obligations (two replicas
  + an ahead wall clock must converge with the causally later local
  write winning).
- `ecsly_world_sync` gains a second foundation dependency; both ride the
  path override until the kernel and session core publish.
