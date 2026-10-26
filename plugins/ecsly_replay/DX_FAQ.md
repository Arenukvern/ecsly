# ecsly_replay — DX FAQ

## How do I record a harness command?

Capture the world **after** the command runs and store it as the command outcome:

```dart
recorder.recordCommand(
  tick: tick,
  outcome: captureWorldSnapshot(world),
  eventKey: opaqueHarnessKey, // optional
  label: 'optional-string',
);
```

## How do I seek?

```dart
player.seek(tick: 120);
player.seek(eventKey: myOpaqueKey);
player.seekToTick(120);
player.seekToEventKey(myOpaqueKey);
player.seekTo(const ReplayPosition(tick: 10, seq: 2));
```

### Transient entities

```dart
player.seekToTick(5, transientPolicy: TransientPolicy.keep); // default
player.seekToTick(5, transientPolicy: TransientPolicy.despawn);
```

`TransientPolicy.keep` leaves entities without `PersistentId` alone. There is
**no determinism guarantee** if systems read transient entities during replay.

`verifyDeterminism` always uses `TransientPolicy.despawn` (and rejects other
policies).

Set `initialBaseline` on the player when the first checkpoint is after tick 0.

Checkpoints reconcile into the live world by default. For spawn-oracle restore:

```dart
ReplayPlayer(
  world: world,
  log: log,
  checkpoints: checkpoints,
  checkpointRestoreMode: CheckpointRestoreMode.spawn,
);
```

## How do checkpoints work?

Call `recorder.maybeCheckpoint(world, tick)` after entries for that tick are
recorded. `CheckpointStore.cadence` controls frequency. Truncating the log via
`recorder.truncateFrom` drops checkpoints at or after that tick.

## How do I verify cold vs hot replay?

```dart
final ok = player.verifyDeterminism(
  emptyTemplate: freshWorldWithSameRegistrations,
  target: const ReplayPosition(tick: 50, seq: 0),
  initialSnapshot: baselineCapture,
);
```

Comparison uses captures keyed by `PersistentId`.

## Where do event ids / actors / parents go?

Encode them into `eventKey` (opaque string). This package only indexes and
seeks on that value.
