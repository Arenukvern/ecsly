# ecsly_serialization

Serialization and deserialization plugin for [ecsly](https://pub.dev/packages/ecsly)
worlds.

Captures and restores JSON snapshots of:

- Entities carrying a `PersistentEntityComponent` (identity + SoA columns +
  object-tier components);
- Resources implementing `SnapshotableResource`;
- Whole worlds via a versioned snapshot envelope (format v4).

Vision and boundaries: [NORTH_STAR.md](NORTH_STAR.md).

## Identity model

Runtime `Entity` handles are world-local and never serialized — they are
regenerated on restore, exactly like Bevy and networked ECS engines treat
entity ids. Stable identity is a `PersistentEntity` (String) carried by a
component, and it is **allocated, never hand-picked**:

```dart
// SerializationPlugin(manageIds: true) installs a sequence allocator
// (deterministic, replay-safe) and the O(1) identity index.
final entity = world.spawnPersistent([
  const PositionComponent(),
]);
// persistentEntityOf(world, entity) == PersistentEntity.sequence(1) → '1'
```

Allocation is a world-level policy (ADR 0007): a
`SequencePersistentEntityAllocator` (default — identities are a pure function
of seed and spawn order, which deterministic replay requires) or a
`RandomPersistentEntityAllocator` (128-bit secure random — the merge-safe
choice for MMO-style topologies). Never mix policies within one world.

Only entities carrying the identity component are captured; particles, VFX,
and other transient entities are runtime-only by default. Restore **spawns
fresh entities** into the target world — the target can be completely empty —
and auto-adopts allocation state, so identities minted after restore never
collide with restored ones.

Pre-v4 snapshots (int `persistentId`) decode transparently: identities are
normalized to their decimal String form on load.

## Install

```sh
dart pub add ecsly_serialization
```

Workspace consumers inside this repo can use a key-only entry
(`ecsly_serialization:`).

## Usage

A complete runnable save/load story lives in [example/main.dart](example/main.dart)
(`dart run example/main.dart`).

### Whole world save/load

```dart
final snapshot = captureWorldSnapshot(world);
final encoded = encodeWorldSnapshot(snapshot); // JSON string → disk

// Later — any fresh world, even a completely empty one:
final decoded = decodeWorldSnapshot(encoded);
final mapping = restoreWorldSnapshot(freshWorld, decoded);
// mapping: identity String → newly spawned Entity
```

Restore is idempotent: re-applying the same snapshot leaves entities whose
identity already exists in the target world untouched.

### Entity references inside payloads

References are first-class in the codec contract — capture receives an
`EntityRefEncoder`, restore an `EntityRefResolver`:

```dart
class RefCodec extends ObjectComponentCodec<RefComponent> {
  @override
  Object? toJson(RefComponent component, EntityRefEncoder refs) =>
      refs.encode(component.target); // stable identity, or null

  @override
  RefComponent fromJson(Object? value, EntityRefResolver refs) =>
      RefComponent(refs.resolve(value)); // live entity again
}
```

A reference to a non-persisted entity **fails capture loudly** — one
dangling-reference policy for the whole engine. The restore mapping never
escapes `restoreWorldSnapshot`; there is no second rehydration pass.

### Object-tier components

Object components live in an `ObjectColumn`, so restore needs a way to build
an instance. Register a **sample** at registration time (the component-side
mirror of the event-side `sampleEvent` pattern):

```dart
world.components.registerObjectComponent<InventoryComponent>(
  sample: const InventoryComponent.empty(),
);
```

Alternatively pass per-call factories:

```dart
restoreWorldSnapshot(
  target,
  snapshot,
  componentFactories: {
    'InventoryComponent': () => const InventoryComponent.empty(),
  },
);
```

SoA/tag components need no sample — their columns are zero-initialized at
spawn and overwritten from snapshot data. Object values are serialized via
codecs registered in `ObjectComponentCodecRegistry`.

### Stable names

Component and resource identity travels as **stable registered names** when
given, falling back to type names for unregistered types:

```dart
world.components.registerObjectComponent<PositionComponent>(
  name: 'game.position',
  columnFactory: positionColumnFactory,
);
```

Names survive class renames, cannot collide across libraries, and are
independent of web minification. Registered resources declare name and
restore factory together — registration IS the factory map:

```dart
final registry = SnapshotResourceRegistry()
  ..register<GameConfig>('game.config', (json, refs) => GameConfig.fromJson(json));
restoreWorldSnapshot(target, snapshot, resourceRegistry: registry);
```

### Structural changes between versions

Registration reorder, additions, and removals are handled automatically.
Renames and value transforms need an explicit migration chain keyed on
`schemaVersion`:

```dart
final restored = decodeAndMigrateWorldSnapshot(oldSaveJson, [
  const RenameComponentMigration(
    fromVersion: 1,
    oldName: 'Transform',
    newName: 'PositionComponent',
  ),
], targetVersion: 2);
```

### Plugin

```dart
// Identity management off (capture/restore only):
world.addPlugin(const SerializationPlugin());

// Full identity layer: allocator + index + auto-adopt + spawnPersistent:
world.addPlugin(const SerializationPlugin(manageIds: true));
```

## Constraints

- Capture saves only identity carriers; duplicate identities fail capture
  loudly (allocate through the allocator so this cannot happen).
- Restore requires object-tier components to have a registered sample or an
  explicit `componentFactories` entry — missing ones throw with the type name.
- Renames and value transforms need an explicit `SnapshotMigration` chain;
  nothing is inferred automatically.

See [DX_FAQ.md](DX_FAQ.md) for recipes and [DESIGN_FAQ.md](DESIGN_FAQ.md)
for design rationale.
