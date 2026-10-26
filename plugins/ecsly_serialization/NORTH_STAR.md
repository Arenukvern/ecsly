# ecsly_serialization North Star

Parent boundary: [docs/NORTH_STAR.mdx](../../docs/NORTH_STAR.mdx). This
sub-star narrows the global vision to one surface — world persistence — and
cannot expand the repo's ownership by itself.

## Vision

Saving and loading a game world should be a **one-line decision, not an
architecture project**. Attach `PersistentId` to what matters; everything
else is transient by default. A save file must load into any target world —
including a freshly constructed, completely empty one — without the app
reproducing spawn order, registration order, or entity layout.

The model follows established ECS practice (Bevy scenes, networked MMO
identity): runtime `Entity` handles are disposable and never serialized;
stable identity lives in a component. The framework owns structure and data
integrity; the app owns only what no algorithm can infer — semantics of
change.

## What This Package Owns

| Surface                  | Owned here                                                                    |
| ------------------------ | ----------------------------------------------------------------------------- |
| Persistent identity      | `PersistentId` component, uniqueness enforcement, idempotent restore.         |
| World snapshot envelope  | Versioned format v3: name-table remap, entity entries, resources.             |
| Column serialization     | Generic SoA capture/restore (`FloatColumn`, `IntColumn`, `Uint8Column`).       |
| Object-tier support      | Registry samples for construction, per-type codecs for values.                |
| Schema evolution         | `schemaVersion` + ordered `SnapshotMigration` chains with loud gaps.          |
| JSON codec               | Human-readable encoding incl. Infinity/NaN markers.                           |

## What This Package Does Not Own

| Boundary                     | Rule                                                                                          |
| ---------------------------- | --------------------------------------------------------------------------------------------- |
| Binary formats               | Planned fast path behind the same envelope; not shipped here yet — do not claim it.           |
| Automatic migration          | Renames/transforms are never inferred; apps declare them. No "smart" diffing will be added.   |
| Entity handle persistence    | Runtime handles are never serialized; this is a permanent contract, not a limitation to lift. |
| Core storage changes         | Storage tiers, columns, and archetypes belong to core `ecsly`.                                |
| Network replication          | Snapshot transport is out of scope; the format is transport-agnostic but unowned here.        |

## Values

- **Fail loudly over silent drift**: duplicate IDs, missing samples, missing
  migration steps all throw with actionable messages.
- **Explicit beats inferred**: persistence is opt-in per entity; schema change
  semantics are declared, not guessed.
- **Names over ordinals**: snapshots survive registration reorder/add/remove
  with zero user effort.
- **Empty-world restore is the tested default path**, not an edge case.

## Decision Gate

Changes here classify against the parent North Star first. Within this
package:

- New snapshot format fields → bump `worldSnapshotVersion`, keep decode of
  older envelopes working.
- New identity semantics → ADR before implementation.
- Performance work → benchmark first via `just bench-serialization`; relative
  movement on the existing harness is the signal.

## Proof Rule

Behavior is proven by the package test suite (evals, stability, dogfood,
benchmarks) and the runnable `example/main.dart`. Docs claims must map to a
test or example in this package.
