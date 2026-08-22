# ecsly_serialization

Serialization and deserialization plugin for [ecsly](https://pub.dev/packages/ecsly)
worlds.

Captures and restores JSON snapshots of:

- Entities carrying a `PersistentId` component (identity + SoA columns +
  object-tier components);
- Resources implementing `SnapshotableResource`;
- Whole worlds via a versioned snapshot envelope (format v3).

## Identity model

Runtime `Entity` handles are world-local and never serialized — they are
regenerated on restore, exactly like Bevy and networked ECS engines treat
entity ids. Stable identity lives in a component:

```dart
world.spawnComponents([
  const PersistentId(42), // stable cross-session identity
  const PositionComponent(),
]);
```

Only entities carrying `PersistentId` are captured; particles, VFX, and other
transient entities are runtime-only by default. Restore **spawns fresh
entities** into the target world — the target can be completely empty.

## Install

Add to your `pubspec.yaml` (workspace consumers can use the path):

```yaml
dependencies:
  ecsly_serialization:
```

## Usage

### Whole world save/load

```dart
// Mark persistable entities with PersistentId at spawn time.
final entity = world.spawnComponents([
  const PersistentId(1),
  const PositionComponent(),
  const HealthComponent(),
]);

final snapshot = captureWorldSnapshot(world);
final encoded = encodeWorldSnapshot(snapshot); // JSON string → disk

// Later — any fresh world, even a completely empty one:
final decoded = decodeWorldSnapshot(encoded);
final mapping = restoreWorldSnapshot(freshWorld, decoded);
// mapping: persistentId → newly spawned Entity
```

Restore is idempotent: re-applying the same snapshot leaves entities whose
`PersistentId` already exists in the target world untouched.

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

### Structural changes between versions

Component identity travels as type names, so registration reorder, additions,
and removals are handled automatically. Renames and value transforms need an
explicit migration chain keyed on `schemaVersion`:

```dart
final restored = decodeAndMigrateWorldSnapshot(oldSaveJson, [
  const RenameComponentMigration(
    fromVersion: 1,
    oldName: 'Transform',
    newName: 'PositionComponent',
  ),
], targetVersion: 2);
```

### Resources

```dart
class GameConfig extends Resource with SnapshotableResource {
  GameConfig({this.speed = 100});
  final double speed;

  @override
  Map<String, Object?> toJson() => {'speed': speed};

  static GameConfig fromJson(Map<String, Object?> json) =>
      GameConfig(speed: (json['speed'] as num).toDouble());
}

restoreWorldSnapshot(target, snapshot, resourceFactories: {
  'GameConfig': GameConfig.fromJson,
});
```

### Plugin

```dart
world.addPlugin(const SerializationPlugin());
```

## Constraints

- Capture saves only `PersistentId` carriers; duplicate persistent ids fail
  capture loudly.
- Restore requires object-tier components to have a registered sample or an
  explicit `componentFactories` entry — missing ones throw with the type name.
- Renames and value transforms need an explicit `SnapshotMigration` chain;
  nothing is inferred automatically.

See [DX_FAQ.md](DX_FAQ.md) for recipes and [DESIGN_FAQ.md](DESIGN_FAQ.md)
for design rationale.
