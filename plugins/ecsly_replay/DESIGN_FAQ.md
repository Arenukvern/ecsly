# ecsly_replay — DESIGN FAQ

## Why command outcomes instead of re-simulating systems?

Inspector and agent harness commands come from non-deterministic models. Recording
each command's serialized outcome lets replay reproduce state without requiring
deterministic systems or inverse deltas.

## Why reconcile restore for command application?

Partial outcome snapshots must not despawn unrelated persisted entities.
`reconcileWorldSnapshot(..., despawnAbsent: false)` applies entity-scoped
patches.

## Why reconcile restore for checkpoints?

Inspector worlds keep transient entities (selection, gizmos) without
`PersistentId`. Checkpoint restore defaults to reconcile with
`despawnAbsent: true` so persisted rows match the snapshot while transient
entities survive and runtime `Entity` handles for persisted rows stay stable.
Use `CheckpointRestoreMode.spawn` when you need the save/load spawn oracle.

## Why is transient policy separate from checkpoint mode?

Inspector hosts keep selection and gizmo entities without `PersistentId`.
`TransientPolicy.keep` preserves them across seeks; `despawn` trims the world to
recorded persisted state only. Cold-vs-hot checks require `despawn` because
transients are not part of the log.

## Why reconcile baseline when no checkpoint exists?

Without a checkpoint at or before the target, replay must not stack on an
arbitrary later world. The player reconciles `initialBaseline` (or an empty
persisted set) with `despawnAbsent: true`, then replays forward.

## Why `(tick, seq)` ordering?

Multiple commands may land in one tick (agent bursts). `seq` gives a total order
without overloading tick semantics.

## Why duplicate event keys are rejected?

The event index is a map. Duplicate keys would make seek-by-event ambiguous.

## Why are fingerprints in the header?

Consumers can refuse to play logs when build or schema identity drifts, before
mutating a world.
