# ecsly_serialization

Serialization and deserialization plugin for [ecsly](https://pub.dev/packages/ecsly)
worlds.

Captures and restores JSON snapshots of:

- Resources implementing `SnapshotableResource`;
- Entity SoA component columns (`FloatColumn`, `IntColumn`, `Uint8Column`);
- Object-tier components via per-type codecs;
- Whole worlds via a versioned snapshot envelope.

## Install

Add to your `pubspec.yaml` (workspace consumers can use the path):

```yaml
dependencies:
  ecsly_serialization:
```

## Usage

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

final snapshot = captureResourceSnapshot(world);
restoreResourceSnapshot(world, snapshot, {
  'GameConfig': GameConfig.fromJson,
});
```

### Whole world

```dart
final snapshot = captureWorldSnapshot(world);
final encoded = encodeWorldSnapshot(snapshot); // JSON string

// Later, in a fresh world with the same component registration order:
final decoded = decodeWorldSnapshot(encoded);
restoreWorldSnapshot(freshWorld, decoded, resourceFactories: {
  'GameConfig': GameConfig.fromJson,
});
```

### Plugin

```dart
world.addPlugin(const SerializationPlugin());
```

## Constraints

- Restore requires entities to pre-exist in the target world (state, not
  structure, is serialized).
- Component data is remapped by type name (format v2+), so registration
  reorder/add/remove is handled automatically. Renames and value transforms
  need an explicit `SnapshotMigration` chain keyed on `schemaVersion`.
- Object-tier components need a codec registered in
  `ObjectComponentCodecRegistry`.

See [DX_FAQ.md](DX_FAQ.md) for recipes and [DESIGN_FAQ.md](DESIGN_FAQ.md)
for design rationale.
