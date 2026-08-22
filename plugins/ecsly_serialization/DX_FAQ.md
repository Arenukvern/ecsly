# DX FAQ — ecsly_serialization

## How do I mark an entity as saved?

Attach a `PersistentId` component at spawn. Only `PersistentId` carriers are
captured; everything else is transient by default.

```dart
world.spawnComponents([
  const PersistentId(42), // stable cross-session identity
  const PositionComponent(),
]);
```

## How do I save and load the whole world?

```dart
// Save:
final snapshot = captureWorldSnapshot(world);
File('save.json').writeAsStringSync(encodeWorldSnapshot(snapshot));

// Load — the target world can be completely empty:
final snapshot = decodeWorldSnapshot(File('save.json').readAsStringSync());
final mapping = restoreWorldSnapshot(world, snapshot);
// mapping: persistentId → newly spawned Entity
```

Restore spawns fresh entities; runtime `Entity` handles are never serialized.

## Why do I need a `sample` for object components?

Dart has no runtime reflection, so restore cannot construct an
`InventoryComponent` from its type name. Register a representative instance
once at registration (mirrors the event-side `sampleEvent` pattern):

```dart
world.components.registerObjectComponent<InventoryComponent>(
  sample: const InventoryComponent.empty(),
);
```

Missing samples throw at restore time with the exact type name. SoA and tag
components never need one — their columns are zero-initialized and filled
from snapshot data.

## How do I serialize only one entity?

```dart
final snap = captureEntityColumns(world, entity);
// ... later ...
restoreEntityColumns(world, entity, snap!);
```

## How do I serialize object component _values_?

Samples give restore an instance; codecs serialize the value:

```dart
final codecs = ObjectComponentCodecRegistry()
  ..register(const _NameCodec());

captureWorldSnapshot(world, options: WorldSnapshotOptions(codecs: codecs));
```

## What happens to entities already in the target world?

Restore is idempotent per `PersistentId`: an id already live in the target is
left untouched, so re-applying a snapshot is a no-op. New ids are spawned
fresh. Duplicate ids in a snapshot fail capture loudly.

## How do I handle renamed or restructured components?

Bump `schemaVersion` when capturing and declare a migration:

```dart
final snapshot = decodeAndMigrateWorldSnapshot(saveJson, [
  const RenameComponentMigration(
    fromVersion: 1,
    oldName: 'Transform',
    newName: 'PositionComponent',
  ),
], targetVersion: 2);
restoreWorldSnapshot(world, snapshot);
```

For value transforms (not just renames), extend `SnapshotMigration` and edit
the raw JSON map directly.

Registration reorder/add/remove needs no migration — component identity
travels as type names and data is remapped automatically.

## How do I make restore fail loudly on unknown components?

```dart
restoreWorldSnapshot(
  world,
  snapshot,
  options: const WorldSnapshotOptions(strictComponents: true),
);
```

Default skips unregistered components; strict mode throws. Use strict for
authoritative saves, lenient for tooling.

## How do I exclude components from snapshots?

Use `includeOnly` with a set of `ComponentId`s, or filter after capture.

## What is the performance profile?

Wall-clock micro-benchmarks (Apple Silicon, debug-mode VM, JSON path, restore
into an empty world):

| Entities | Capture | Encode  | Decode  | Restore |
| -------- | ------- | ------- | ------- | ------- |
| 100      | ~35 µs  | ~144 µs | ~123 µs | ~30 µs  |
| 1,000    | ~323 µs | ~1.5 ms | ~1.2 ms | ~290 µs |
| 10,000   | ~3.4 ms | ~14 ms  | ~20 ms  | ~330 µs |

Single-entity column capture: ~0.3 µs. JSON encode/decode dominates at scale;
a binary codec behind the same envelope is the planned fast path. Run via
`just bench-serialization`.
