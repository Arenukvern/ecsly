# ADR 0007: PersistentEntity is the one durable identity; allocation is a world-level policy

- Status: Accepted
- Date: 2026-11-20
- North Star impact: `amends` — changes the identity model of
  `plugins/ecsly_serialization` (and retires a public type), so the ownership
  story is restated here before the repo center moves.
- Related: `core_packages/ecsly` (`Entity`, entity manager), `plugins/ecsly_serialization`,
  `plugins/ecsly_replay`, `plugins/ecsly_world_sync` (`ComponentDelta.entityKey`).

## Context

The engine has two identity tiers by design. The runtime `Entity` handle
(index/generation packed into an int) is deliberately **throwable**: indices are
recycled through the free-list, generations invalidate stale handles, and the
type's own docs say it is unsafe to save. The durable tier was born in the
original game-side ECS (2025-11) as a String-typed identity paired with a
`PersistentEntityMap` registry component, and moved into this repo. By the
2026-07 prerelease prep it had been renamed `PersistentEntity`, parked in a
typo'd plugins folder, and left functionally empty: no allocator, no registry,
no plugin, no docs.

In 2026-08, `ecsly_serialization` needed durable identity and could not use
the ghost primitive, so it minted a parallel `PersistentId` — an **int**
component — unknowingly recycling the displaced type's name. Consumers
(the game in this repo's dogfood lineage, `ecsly_replay`,
`ecsly_world_sync`) built on the int. The result is the current debt:

- The identity contract (`PersistentId` must be unique among persisted
  entities; capture throws on duplicates) ships **no allocator**. Every app
  invents one; uniqueness is enforced at save time, far from the mistake.
- Restore resolves identities by linear scan (O(n²) in persisted entities),
  because there is no index and no lifecycle hooks to maintain one.
- Entity *references inside payloads* are not first-class: capture rewrites
  them app-side per model type; restore leaves raw ints and hands back a
  `Map<int, Entity>` mapping for the app to rehydrate — the mapping escaping
  restore is the serializer admitting it did half the job.
- Resource snapshots are keyed by `runtimeType.toString()`: fragile against
  renames (silent save-data loss), name collisions, and web minification.

Separately, durable identity must be **MMO-durable** (cross-shard, merge-safe),
while replay (`ecsly_replay`) requires id assignment to be a deterministic
function of seed and spawn order — cold-vs-hot comparison keys on identity.

## Decision

### 1. `PersistentEntity` (String) is the one durable identity type

The core primitive moves to `entities/persistent_entity.dart` next to `Entity`,
exported from the barrel, and is finished as a value type:

```dart
extension type const PersistentEntity._(String value) {
  /// Deterministic identity: decimal encoding of a sequence number, with an
  /// optional namespace (`'ns:42'`). Pure function of seed + spawn order.
  factory PersistentEntity.sequence(int value, {String? namespace});

  /// Random identity: 128 bits of secure randomness (+ counter suffix).
  /// Globally unique by collision resistance; the MMO/merge-safe default.
  factory PersistentEntity.create();

  /// The null identity (value-level counterpart of `Entity.nullEntity`).
  static const zero = PersistentEntity._('');
}
```

Decimal encoding for sequence identities is chosen for human readability in
logs/why-ledgers and reversibility. **Future gate**: if large-scale usage
surfaces issues (size pressure, encoding collisions with app data), a
alternative encoding may replace it behind the same factory — the gate is
this ADR, not an ad-hoc format drift.

The int `PersistentId` component and the empty `PersistentEntityMap` stub are
**removed**. The durable marker component is `PersistentEntityComponent`
(carrying a `PersistentEntity`); `registerPersistentEntity` /
`persistentEntityOf` replace their `PersistentId` counterparts.

### 2. Allocation is a world-level policy, never per-entity mixing

```dart
abstract interface class PersistentEntityAllocator {
  PersistentEntity next();
  void adoptMax(Iterable<PersistentEntity> identities);
  Map<String, Object?> snapshotState();   // {"mode": ..., ...impl state}
  void restoreState(Map<String, Object?> state);
}

SequencePersistentEntityAllocator   // counter → PersistentEntity.sequence(n)
RandomPersistentEntityAllocator     // PersistentEntity.create()
```

A world picks one allocator at setup (`SerializationPlugin` `manageIds: true`,
or direct installation). Mixing random identities into a deterministic world
is unrepresentable — which is what preserves replay determinism: sequence
allocation is a pure function of seed + spawn order, so `ecsly_replay`'s
cold-vs-hot comparison keyed by identity keeps working. Random allocation is
opt-in for worlds that participate in MMO/merge topologies.

### 3. The index is a cache repaired at the consumers that need it

`PersistentEntityIndex` (a `Resource`: identity → `Entity`) is maintained at
three write points only — allocator mint (`spawnPersistent`), restore
mappings, and an explicit `repair(world)` (O(n) full scan using
`Entities.isAlive`) that capture, restore, and reconcile call before their
lookups. Lookups are O(1) map reads with no per-read validation; a stale entry
between a despawn and the next repair is acceptable because every consumer
that needs correctness repairs first. This is why no core lifecycle hooks are
required.

### 4. Entity references become first-class in the codec contract

`ObjectComponentCodec` gains reference phases; the restore mapping never
escapes `restoreWorldSnapshot`:

```dart
abstract class ObjectComponentCodec<T extends Component> {
  Object? toJson(T component, EntityRefEncoder refs);
  T fromJson(Object? value, EntityRefResolver refs);
}
```

`EntityRefEncoder.encode(Entity)` returns the referenced entity's
`PersistentEntity` (null for `Entity.nullEntity`) and **throws** on a
non-persisted entity — one dangling-reference policy for the whole engine,
replacing the throw-vs-silent-null split apps had to resolve themselves.
`EntityRefResolver.resolve` accepts both String (v4) and int (v3 payloads)
normalizing to String, so old saves load without app-level migration steps.
Resource factories and `SnapshotableResource.toJson` receive the same
encoder/resolver, so resources hold `Entity` handles directly and their
`persisted*` shadow fields become unnecessary.

### 5. Named registration replaces `runtimeType.toString()` identity

- Components: the registry accepts an optional stable `name` at registration
  (`registerObjectComponent<T>(name: 'people.person_model', sample: ...)`).
  Snapshots prefer the registered name and fall back to `Type.toString()`
  when none is given, so existing snapshots keep loading.
- Resources: `ecsly_serialization` provides a snapshot-resource registry —
  name, capture codec and restore factory declared together. Registration IS
  the factory map; the per-app hand-written string-literal maps die.

### 6. Snapshot format v4

`worldSnapshotVersion` bumps to 4: `EntityEntry.identity` (String) replaces
`persistentId` (int). `WorldSnapshot.fromJson` normalizes v3 envelopes in
place (int `persistentId` → decimal String `identity`), so pre-v4 snapshots
decode transparently and no app migration is required for the format bump
itself; app-owned `schemaVersion` semantics are unchanged.

## Consequences

- Apps stop re-implementing identity: one allocation path
  (`world.spawnPersistent(...)`, which attaches the identity component and
  registers the index), one dangling-reference policy, one adopt path
  (restore auto-adopts into index and allocator).
- Restore, replay seek, and transient-despawn drops become O(n) instead of
  O(n²).
- Save size: sequence identities are comparable to the int format they
  replace; random identities cost ~22 bytes each and are opt-in per world.
- Breaking changes (pre-1.0): int `PersistentId` and its helpers removed;
  codec signatures gain the reference parameters; the `resourceFactories`
  map stays supported for back-compat but registered resources replace it.
- `runtimeType.toString()` remains the fallback identity for unnamed
  components/resources; migrating registrations to explicit names is
  incremental and non-breaking.
