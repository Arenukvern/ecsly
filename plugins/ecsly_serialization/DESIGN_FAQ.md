# Design FAQ — ecsly_serialization

## Why JSON maps instead of binary?

JSON keeps the format debuggable, diffable, and versionable. The SoA columns
are read/written through their typed accessors so no reflection or dynamic
field access is needed on the hot path. A binary column codec can be added
later behind the same `WorldSnapshot` envelope without breaking the API.

## How do snapshots survive structural world changes?

This is the central stability question. The failure mode to avoid is **silent
data corruption**: a save file whose positional component IDs no longer match
the target world's registration order would bind health values to positions.

The design layers three mechanisms, in increasing invasiveness:

### 1. Stable identity by type name (automatic)

Snapshots (format v3) embed a `componentIds` table mapping component _type
names_ to the source world's local numeric IDs. On restore, the plugin builds
a snapshot-ID → target-ID remap from those names and rewrites all column keys.
Registration reorder, added components, and removed components therefore need
**zero user effort** — data lands on the right components regardless.

DB analogy: logical column names vs physical column ordinals. SQL tables
survive column reordering because queries reference names; same principle.

### 2. Strict validation (opt-in)

`WorldSnapshotOptions(strictComponents: true)` makes restore throw when the
snapshot contains a component absent from the target world. Default behavior
skips unknown components silently, which suits best-effort loads (analytics,
tooling); strict mode suits authoritative loads (the player's save game) where
partial restores are worse than loud failure.

### 3. Explicit schema migrations (app-owned)

Some changes cannot be expressed as a name remap: renaming a class, splitting
one component into two, transforming values (e.g., health int → double). For
these the envelope carries an app-owned `schemaVersion`, and apps declare an
ordered chain of `SnapshotMigration` steps that rewrite raw JSON forward:

```dart
final snapshot = decodeAndMigrateWorldSnapshot(saveJson, [
  const RenameComponentMigration(
    fromVersion: 1,
    oldName: 'Transform',
    newName: 'PositionComponent',
  ),
], targetVersion: currentSchemaVersion);
```

Each step upgrades exactly one version (`fromVersion` → `fromVersion + 1`).
A missing step throws with the version gap named — loud failure beats drift.

**Why not automatic migrations?** Because inferring intent is impossible. If
component A was removed and component B appeared between versions, no
algorithm can know whether B replaces A, coexists with it, or is unrelated.
Every mature system (Flyway, Rails migrations, Unity DOTS serialization
versions, Bevy's explicit scene type registration) requires the developer to
declare semantics. The framework's job is to make declaring them cheap and to
fail loudly when a declaration is missing — which is what layers 1–3 do.

## Why PersistentId instead of serializing entity handles?

Runtime `Entity` handles are world-local: index + generation, recycled on
despawn. Serializing them would make saves fragile (any spawn-order change
invalidates every reference) and would couple the format to core's internal
entity encoding.

This matches how Bevy and networked ECS engines treat identity: the runtime
handle is disposable; stable identity lives in a component (`PersistentId`
here, Bevy's `PrimaryEntity`/BSN `Context`-scoped ids, or MMO persistent
object GUIDs). The snapshot stores only `PersistentId` carriers and re-spawns
them into any target world — including a completely empty one — returning a
`persistentId → Entity` map so apps can re-resolve references.

Consequences:

- Transient entities (particles, VFX) are excluded by default — an explicit,
  cheap opt-in to persistence rather than a global filter list.
- Restore is idempotent per id: applying a snapshot twice is a no-op for
  entities already present.
- Duplicate ids fail capture loudly; silent aliasing is worse than an error.

## Why samples at registration time for object components?

Dart has no runtime reflection, so restore cannot construct an object-tier
component from its type name. Two options existed: ad-hoc factory maps passed
to every restore call, or a representative instance registered once where the
type is already being registered. The sample follows the existing event-side
`sampleEvent` pattern: one canonical place per type, validated at registration
time, no per-call ceremony. Per-call `componentFactories` remain as an escape
hatch for one-off constructions. SoA/tag components need nothing — their
columns are zero-initialized and filled from snapshot data.

## Why does restore spawn fresh entities instead of writing into pre-existing ones?

Writing into pre-spawned entities required the target world to reproduce the
exact entity layout of the source — brittle across sessions and useless for
the primary flow (load a save into a freshly constructed world). Spawning
from the snapshot itself makes the target world's live state irrelevant:
structure travels with the snapshot as type names, data lands via the ID
remap, and empty-world restores are the tested default path.

## Why per-type codecs for object components?

Object columns hold heap objects whose shape only the app knows. A registry of
`ObjectComponentCodec`s keeps core serialization generic while letting apps opt
in per type.

## Why is this a plugin package, not part of core?

Core `ecsly` stays pure runtime (entities, archetypes, schedules). Serialization
is a companion concern like codegen or Flutter bridges, matching the repo's
package-boundary rules.
