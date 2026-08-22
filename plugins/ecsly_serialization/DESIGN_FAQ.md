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

Snapshots (format v2+) embed a `componentIds` table mapping component _type
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

## Why does restore require pre-spawned entities?

Structural identity (which archetype an entity belongs to) depends on
registration order and spawn sequence, which are app concerns. Serializing
state only keeps the plugin small and avoids duplicating spawn logic. The
snapshot stores each entity's index/generation so handles stay valid when the
target world reproduces the same layout.

## Why per-type codecs for object components?

Object columns hold heap objects whose shape only the app knows. A registry of
`ObjectComponentCodec`s keeps core serialization generic while letting apps opt
in per type.

## Why is this a plugin package, not part of core?

Core `ecsly` stays pure runtime (entities, archetypes, schedules). Serialization
is a companion concern like codegen or Flutter bridges, matching the repo's
package-boundary rules.
