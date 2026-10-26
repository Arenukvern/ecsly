# ecsly_replay

Record simulation history for an [ecsly](https://github.com/Arenukvern/ecsly)
world and seek forward or backward to any tick or opaque event key. Built for
inspector time bars and harness tooling where agent commands are not
deterministic but recorded outcomes are.

## Design

- **Identity**: [PersistentId](https://github.com/Arenukvern/ecsly/tree/main/plugins/ecsly_serialization)
  and [WorldSnapshot](https://github.com/Arenukvern/ecsly/tree/main/plugins/ecsly_serialization)
  from `ecsly_serialization` — no parallel id scheme.
- **Log**: append-only `ReplayEntry { tick, seq, kind, payload, eventKey? }`
  ordered by `(tick, seq)` with an `eventKey → position` index.
- **Commands**: each entry carries a full serialized outcome snapshot; replay
  applies it via reconcile restore (no inverse deltas, no re-running systems).
- **Inputs**: optional second kind for deterministic games (host supplies
  `InputReplayer`).
- **Checkpoints**: serialized world snapshots on a cadence; invalidated when
  history is truncated.
- **Seek**: nearest checkpoint at or before the target, then replay forward.
  Checkpoints **reconcile** into the live world by default (transient entities
  survive with `TransientPolicy.keep`). Use `TransientPolicy.despawn` to drop
  non-persistent entities after each seek. `CheckpointRestoreMode.spawn` is the
  explicit oracle. Use `seek`, `seekToTick`, `seekToEventKey`, or `seekTo`.
- **No Flutter UI** in this package.

## Quick start

```dart
import 'package:ecsly_replay/ecsly_replay.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

final log = ReplayLog(
  header: ReplayLogHeader(
    formatVersion: replayLogFormatVersion,
    fingerprints: ReplayFingerprints(
      buildFingerprint: myBuildId,
      schemaFingerprint: 'schema-$schemaVersion',
    ),
  ),
);
final checkpoints = CheckpointStore(cadence: 30);
final recorder = ReplayRecorder(log: log, checkpoints: checkpoints);

// After each command:
recorder.recordCommand(
  tick: tick,
  outcome: captureWorldSnapshot(world),
  eventKey: harnessEncodedKey,
);
recorder.maybeCheckpoint(world, tick);

final player = ReplayPlayer(world: world, log: log, checkpoints: checkpoints);
player.seekToEventKey(harnessEncodedKey);
```

See [DX_FAQ.md](DX_FAQ.md) for usage notes and [DESIGN_FAQ.md](DESIGN_FAQ.md)
for rationale.

## Dependencies

- `ecsly` (core runtime)
- `ecsly_serialization` (snapshots, reconcile restore)

## What was borrowed

Concepts (not code paths) from internal `ecs_replay_tools`: log ordering rules,
checkpoint cadence/invalidation, cold-vs-hot determinism checks, and build/schema
fingerprints in the log header.
