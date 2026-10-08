# ADR 0003: Zone travel for ecsly worlds — the pulse is a system, interest stays game-side

- Status: Accepted
- Date: 2026-10-08
- North Star impact: `sub_star` (new plugin `plugins/ecsly_world_zones`;
  the world layer is a parent boundary like the kernel in [ADR 0001][a0001])
- Builds on: [ADR 0001][a0001] (world sync over the kernel) and the world
  layer ADRs in the `storage_problem` repo:
  [0047][k0047] (the world layer), [0048][k0048] (interest-managed exchange)
- Related: `plugins/ecsly_world_sync` (the entity delta lane this plugin
  rides beside)

[a0001]: 0001_world_sync_over_convergence_kernel.md
[k0047]: https://github.com/xsoulspace/universal_storage_sync/blob/main/dart_flutter_packages/docs/decisions/0047_world_layer_zone_journeys.md
[k0048]: https://github.com/xsoulspace/universal_storage_sync/blob/main/dart_flutter_packages/docs/decisions/0048_interest_managed_exchange.md

## Context

World-layer ADR 0047 gives every consumer — apps, games, the harness —
seamless zone travel over the CRDT mesh: catalogs enumerate a zone,
interest gates delivery to the working set, journeys double-buffer the
border. Games need exactly two things from it, and both are game
knowledge the storage family must never learn:

1. **Scheduling.** `ecsly_flutter` and `ecsly_app` already own schedulers
   (frame schedules, host schedules, triggers). A mesh sync loop owned by
   the storage family would fight the frame budget and duplicate every
   pacing decision.
2. **Interest.** Positions, rooms, radii — relevance in a game is spatial
   and world-defined. Coordinates in the storage family would be a
   boundary violation.

## Decision

New plugin `plugins/ecsly_world_zones`, two deliberately thin pieces:

### 1. The mesh sync pulse is an ORDINARY ecsly system

`meshPulseSystem(pulse)` returns an `AsyncSystem` — ecsly's own typedef —
that calls `Pulseable.pulse()` (the world layer's whole scheduling
contract: host-driven, idempotent, coalescing; world-layer ADR 0047 §4).
`registerMeshPulseSchedule(world, session)` drops it into the systems
registry under its own schedule with any trigger the game chooses
(`EveryNSeconds`, `ThrottledTrigger(EveryFrame())`, `ManualTrigger` in
tests). No new scheduler, no adapter layer: the game's existing loop runs
the pulse exactly like its AI and render systems, and a loading screen is
simply "don't register the schedule yet".

### 2. Interest policies are game-side implementations of the contract

- `ZoneCatalogInterest` — subscribes a whole zone from its census
  (the catalog doc's member list), re-resolved per pulse so a growing
  zone re-subscribes without protocol change.
- `SpatialInterestPolicy` — membership is whatever game query the host
  injects (entities in radius, room contents). The storage family sees
  only the resolved id set.
- `RoamingInterest` — the composite working set: open members ∪ current
  zone ∪ spatial query.

## Consequences

- A game gains zone travel with ~6 lines of composition: a
  `MeshWorldSession`, a transport, this plugin's schedule registration,
  and an interest policy.
- The dependency direction stays clean: `ecsly_world_zones` →
  `universal_storage_world` (types only), never the reverse; the world
  layer still knows nothing about ecsly.
- The entity content lane remains `ecsly_world_sync`'s job
  (`ComponentDelta` codec); this plugin adds no content mapping.

## Non-claims

- No binary-asset pipeline yet: blobs ride world-layer
  [ADR 0042][k0042] (chunk store + progressive manifests); wiring game
  assets onto it is future work with its own benchmark obligations.
- No server/authority migration — CRDT equality deletes that problem;
  zone travel here is subscription change + catch-up, by design.

[k0042]: https://github.com/xsoulspace/universal_storage_sync/blob/main/dart_flutter_packages/docs/decisions/0042_content_addressed_chunk_store.md
