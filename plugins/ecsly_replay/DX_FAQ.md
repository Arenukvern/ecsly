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
player.seekToTick(120);
player.seekToEventKey(myOpaqueKey);
player.seekTo(const ReplayPosition(tick: 10, seq: 2));
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
