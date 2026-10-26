# ecsly_replay — DESIGN FAQ

## Why command outcomes instead of re-simulating systems?

Inspector and agent harness commands come from non-deterministic models. Recording
each command's serialized outcome lets replay reproduce state without requiring
deterministic systems or inverse deltas.

## Why reconcile restore for command application?

Partial outcome snapshots must not despawn unrelated persisted entities.
`reconcileWorldSnapshot(..., despawnAbsent: false)` applies entity-scoped
patches. Full checkpoints use spawn restore into the player world.

## Why `(tick, seq)` ordering?

Multiple commands may land in one tick (agent bursts). `seq` gives a total order
without overloading tick semantics.

## Why duplicate event keys are rejected?

The event index is a map. Duplicate keys would make seek-by-event ambiguous.

## Why are fingerprints in the header?

Consumers can refuse to play logs when build or schema identity drifts, before
mutating a world.
