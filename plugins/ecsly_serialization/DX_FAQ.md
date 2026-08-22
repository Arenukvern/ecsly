# DX FAQ — ecsly_serialization

## How do I save and load the whole world?

```dart
final snapshot = captureWorldSnapshot(world);
File('save.json').writeAsStringSync(encodeWorldSnapshot(snapshot));

// Load:
final snapshot = decodeWorldSnapshot(File('save.json').readAsStringSync());
restoreWorldSnapshot(world, snapshot, resourceFactories: myFactories);
```

## How do I serialize only one entity?

```dart
final snap = captureEntityColumns(world, entity);
// ... later ...
restoreEntityColumns(world, entity, snap!);
```

## How do I get readable keys instead of `3_0`?

Pass `fieldNames` mapping component IDs to key lists:

```dart
captureEntityColumns(
  world,
  entity,
  fieldNames: {positionId: ['x', 'y']},
);
```

## How do I serialize object components?

Register a codec:

```dart
final codecs = ObjectComponentCodecRegistry()
  ..register<NameComponent>(const _NameCodec());

captureWorldSnapshot(world, options: WorldSnapshotOptions(codecs: codecs));
```

## Why does restore fail / produce empty columns?

The target world must have identical component registration order — component
IDs are positional per-world. Entities must also already exist in the target
world; this plugin serializes state, not structure.

## How do I exclude components from snapshots?

Use `includeOnly` with a set of `ComponentId`s, or filter after capture.

## What is the performance profile?

Wall-clock micro-benchmarks (Apple Silicon, debug-mode VM, JSON path):

| Entities | Capture | Encode | Decode | Restore |
| -------- | ------- | ------ | ------ | ------- |
| 100      | 35 µs   | 144 µs | 123 µs | 27 µs   |
| 1,000    | 323 µs  | 1.5 ms | 1.2 ms | 286 µs  |
| 10,000   | 3.4 ms  | 14 ms  | 20 ms  | 3.3 ms  |

Single-entity column capture: ~0.3 µs. JSON encode/decode dominates at scale;
a binary codec behind the same envelope is the planned fast path. Run via
`just bench-serialization`.
