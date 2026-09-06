# ADR 0001: ecsly world sync consumes the convergence kernel; parents choose strategies, the kernel never learns about worlds

- Status: Accepted
- Date: 2026-09-06
- North Star impact: `sub_star` (new plugin `plugins/ecsly_world_sync` with an
  explicit parent boundary; global ownership table unchanged until the surface
  graduates)
- Builds on: [convergence kernel ADR 0011][k0011] and [ADR 0029][k0029] in the
  `storage_problem` repo (`dart_flutter_packages/docs/decisions/`)
- Related: `plugins/ecsly_serialization` (identity model this plugin reuses)

[k0011]: https://github.com/xsoulspace/universal_storage_sync/blob/main/dart_flutter_packages/docs/decisions/0011_convergence_kernel_dual_mode.md
[k0029]: https://github.com/xsoulspace/universal_storage_sync/blob/main/dart_flutter_packages/docs/decisions/0029_convergence_kernel_presence_and_sequence_strategy.md

## Context

ecsly worlds need multiplayer convergence: two or more replicas of a world
must reach identical state from the same set of changes, in any delivery
order, without duplicating merge logic per game.

The convergence kernel (`universal_storage_convergence`, pure Dart) already
exists as a sub-star serving two parents — Universal Storage's mesh sync and
ecsly world sync. Its contract (kernel ADR 0011) fixes the hard parts:
dual-mode op log + snapshots, hybrid logical clocks, version vectors, and
pluggable `MergeStrategy` semantics. Kernel ADR 0029 later added the
presence/ephemeral op class and pulled the sequence strategy forward for
another consumer.

The alternative — ecsly hand-rolling its own ordering, version vectors, and
fold rules — was rejected for the reason kernel ADR 0011 records: per-consumer
ad-hoc merge logic multiplies silent divergence bugs by the number of
consumers, and ecsly would re-derive exactly the problems the kernel already
property-tests (commutativity, idempotence, HLC monotonicity).

## Decision

### 1. The kernel is the only merge substrate for world sync

`plugins/ecsly_world_sync` consumes `universal_storage_convergence` as a
dependency. It never implements ordering, version vectors, fold rules, or
dedupe; it only:

- converts world changes into kernel `OpRecord` payloads;
- chooses which kernel-exposed merge strategy and compaction policy to use;
- folds remote ops back into a read-only world-state projection.

The kernel knows nothing about worlds, entities, components, or events —
payloads are opaque to it. This direction of ignorance is permanent.

### 2. Mapping rules (v1, LWW map strategy)

- Default strategy: the kernel's `LwwMapStrategy` — one op per keyed piece of
  state, so independent keys never conflict.
- Keys name state by **stable identity** (`<entityKey>/<component>/<field>`,
  `event/<name>/<key>`), reusing the `ecsly_serialization` identity model:
  runtime `Entity` handles are world-local and never travel.
- Values are JSON-encoded before entering the kernel so any JSON-encodable
  payload rides the kernel's public LWW readers unchanged; the sync layer
  decodes on projection. It does not parse kernel state entry formats.
- Removals use the kernel's tombstone shape (`{'k', 'del': true}`) so deletes
  propagate to replicas that never saw the value.
- Delta shipping is version-vector based (`opsSince`); compaction is a
  deliberate parent-chosen policy executed by the kernel, after which lagging
  replicas are served snapshots (`needsSnapshotFor` / `adoptSnapshot`), never
  deltas.

### 3. Bootstrap constraint (recorded honestly)

The kernel is not published to pub.dev yet. Until it is,
`plugins/ecsly_world_sync/pubspec.yaml` resolves it via a local
`dependency_overrides` path entry pointing at
`../../storage_problem/dart_flutter_packages/pkgs/universal_storage_convergence`.
The declared `universal_storage_convergence: ^0.1.0-dev.1` dependency is the
long-term contract; the override is a temporary resolution hack that must be
removed at publish time. This is a cross-repo bootstrap dependency, not a
public claim that the kernel is an ecsly-owned surface.

## Non-claims

- **No real networking.** No sockets, relays, or radios. The shipped
  `FakeTransport` is test-only, in-memory, and JSON-copies ops to prove
  delivery-order independence. A real transport is a later phase.
- **No presence.** Kernel ADR 0029 defines the ephemeral-op contract; the
  world-sync adapter does not consume it yet.
- **No structural replication.** Spawn/despawn/archetype moves are not
  synced; only keyed state and events are. A structural phase must define
  identity-safe semantics before shipping.
- **No rollback / re-simulation.** Deterministic replay of command logs is a
  different mechanism and stays out of scope.
- **No host integration.** Nothing here wires into `ecsly_app`,
  `ecsly_flutter`, or the core runtime; core `ecsly` packages are unchanged.

## Consequences

- ecsly gains convergence without owning CRDT/clock logic; kernel changes
  now require conformance evidence from this parent too (kernel ADR 0011
  rule): the `plugins/ecsly_world_sync` suite is that evidence.
- The property-test obligations land in this repo: two replicas converge
  under shuffled delivery, redelivery is idempotent, JSON round-trip
  restores a participating replica, and compaction serves snapshots to
  lagging replicas.
- The repo gains a cross-repo bootstrap dependency that must be revisited
  when the kernel publishes to pub.dev.
- North Star follow-up (not done here): when world sync graduates beyond a
  bootstrap plugin, add it to the global owned-surfaces table and give the
  package its own `NORTH_STAR.md` sub-star doc.
