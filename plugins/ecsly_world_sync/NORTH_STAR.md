# ecsly_world_sync North Star

Parent boundary: [docs/NORTH_STAR.mdx](../../docs/NORTH_STAR.mdx). This
sub-star narrows the global vision to one surface — replica convergence for
world state — and cannot expand the repo's ownership by itself. The decision
record is [docs/decisions ADR 0001](../../docs/decisions/0001_world_sync_over_convergence_kernel.md).

## Vision

Synchronizing a game world between two replicas should be a **property, not
a project**: emit keyed deltas, exchange ops, and every replica ends in the
same state — regardless of delivery order, duplication, or when a peer
reconnects. Correctness is inherited, never re-implemented: the merge
substrate is the convergence kernel (`universal_storage_convergence`), and
this plugin owns only the translation between world vocabulary and kernel
vocabulary.

## What This Package Owns

| Surface                   | Owned here                                                                                     |
| ------------------------- | ---------------------------------------------------------------------------------------------- |
| Delta → op conversion     | `ComponentDelta` and `WorldSyncEvent` → one kernel op per keyed piece of state.                |
| Key discipline            | Stable keys from persistent entity identity, never runtime handles; `event/…` namespace.       |
| Replica adapter           | `WorldSync`: local/remote folds, tombstones, snapshot adoption, parent-chosen compaction, JSON. |
| Projection                | Read-only `WorldProjection` over the kernel's fold, read through kernel LWW readers.            |
| Test transport            | In-memory `FakeTransport` proving convergence before any real link.                             |

## What This Package Does Not Own

| Boundary                     | Rule                                                                                          |
| ---------------------------- | --------------------------------------------------------------------------------------------- |
| Merge semantics              | Ordering, version vectors, dedupe, and folds belong to the kernel — always.                    |
| Real networking              | No sockets, relays, discovery, or wire protocols; `FakeTransport` is test-only.                |
| Presence / ephemeral state   | Kernel ADR 0029's ephemeral ops are a later phase; no presence contract here.                  |
| Rollback / re-simulation     | Not shipped, not claimed.                                                                      |
| Core / app integration       | No imports of core `ecsly`, `ecsly_app`, or `ecsly_flutter`; the live-World bridge is later.    |
| Kernel changes               | Never made from this repo; this suite only supplies parent-side conformance evidence.          |
