// ignore_for_file: prefer_final_parameters

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

import 'checkpoint_restore_mode.dart';
import 'checkpoint_store.dart';
import 'determinism.dart';
import 'replay_entry.dart';
import 'replay_log.dart';
import 'transient_policy.dart';

/// Applies [ReplayEntryKind.input] rows during forward replay.
typedef InputReplayer = void Function(
  World world,
  String inputType,
  Map<String, Object?> data,
);

/// Restores and seeks within a replay log.
class ReplayPlayer {
  /// Creates a player bound to [world].
  ReplayPlayer({
    required this.world,
    required this.log,
    required this.checkpoints,
    this.snapshotOptions = const WorldSnapshotOptions(),
    this.resourceFactories = const {},
    this.componentFactories = const {},
    this.inputReplayer,
    this.checkpointRestoreMode = CheckpointRestoreMode.reconcile,
    this.initialBaseline,
    this.defaultTransientPolicy = TransientPolicy.keep,
  });

  /// World mutated by seek/replay.
  final World world;

  /// Source log.
  final ReplayLog log;

  /// Checkpoint store aligned with [log].
  final CheckpointStore checkpoints;

  /// Snapshot capture/restore options.
  final WorldSnapshotOptions snapshotOptions;

  /// Resource factories for reconcile/restore.
  final Map<String, SnapshotResourceFactory> resourceFactories;

  /// Component factories for object-tier components.
  final Map<String, Component Function()> componentFactories;

  /// Optional input applier for [ReplayEntryKind.input].
  final InputReplayer? inputReplayer;

  /// Checkpoint restore strategy (default [CheckpointRestoreMode.reconcile]).
  final CheckpointRestoreMode checkpointRestoreMode;

  /// Baseline when seeking before the first checkpoint (empty persisted set
  /// when null).
  final WorldSnapshot? initialBaseline;

  /// Default [TransientPolicy] for [seekTo] when not overridden per call.
  final TransientPolicy defaultTransientPolicy;

  /// Current inclusive position after the last [seek].
  ReplayPosition _position = const ReplayPosition(tick: -1, seq: -1);

  /// Position after the last successful [seek].
  ReplayPosition get position => _position;

  /// Seeks to [tick] or [eventKey] (exactly one must be set).
  void seek({
    final int? tick,
    final String? eventKey,
    final TransientPolicy? transientPolicy,
  }) {
    if (tick != null && eventKey != null) {
      throw ArgumentError('Pass only one of tick or eventKey.');
    }
    if (eventKey != null) {
      seekToEventKey(eventKey, transientPolicy: transientPolicy);
      return;
    }
    if (tick != null) {
      seekToTick(tick, transientPolicy: transientPolicy);
      return;
    }
    throw ArgumentError('Pass tick or eventKey.');
  }

  /// Seeks to the inclusive end of [targetTick] (all rows with that tick).
  void seekToTick(
    final int targetTick, {
    final TransientPolicy? transientPolicy,
  }) {
    final lastSeq = _maxSeqAtTick(targetTick);
    seekTo(
      ReplayPosition(tick: targetTick, seq: lastSeq),
      transientPolicy: transientPolicy,
    );
  }

  /// Seeks to the inclusive position of [eventKey].
  void seekToEventKey(
    final String eventKey, {
    final TransientPolicy? transientPolicy,
  }) {
    final found = log.positionForEventKey(eventKey);
    if (found == null) {
      throw StateError('Unknown eventKey "$eventKey".');
    }
    seekTo(found, transientPolicy: transientPolicy);
  }

  /// Seeks to [target] by restoring the nearest checkpoint and replaying.
  void seekTo(
    final ReplayPosition target, {
    final TransientPolicy? transientPolicy,
  }) {
    if (target.tick < 0) {
      throw ArgumentError.value(target, 'target', 'tick must be non-negative.');
    }

    final policy = transientPolicy ?? defaultTransientPolicy;
    final checkpointTick = checkpoints.nearestTickAtOrBefore(target.tick);

    if (checkpointTick != null) {
      final snap = checkpoints.snapshotAt(checkpointTick);
      if (snap == null) {
        throw StateError(
          'Checkpoint store references tick $checkpointTick but snapshot data '
          'is missing.',
        );
      }
      _restoreCheckpoint(snap);
      _position = ReplayPosition(
        tick: checkpointTick,
        seq: _maxSeqAtTick(checkpointTick),
      );
    } else {
      _applyBaseline(_baselineSnapshot());
      _position = const ReplayPosition(tick: -1, seq: -1);
    }

    for (final entry in log.entries) {
      if (!entry.isAfterPosition(_position)) continue;
      if (!entry.isBeforeOrAt(target.tick, target.seq)) break;
      _applyEntry(entry);
      _position = ReplayPosition.after(entry);
    }

    _applyTransientPolicy(policy);
  }

  /// Cold replay from empty vs hot [seekTo] at [target]; returns equality.
  ///
  /// Always uses [TransientPolicy.despawn] because [TransientPolicy.keep] does
  /// not guarantee determinism when systems observe transient entities.
  bool verifyDeterminism({
    required final World emptyTemplate,
    required final ReplayPosition target,
    final WorldSnapshot? initialSnapshot,
    final TransientPolicy transientPolicy = TransientPolicy.despawn,
  }) {
    if (transientPolicy != TransientPolicy.despawn) {
      throw ArgumentError.value(
        transientPolicy,
        'transientPolicy',
        'verifyDeterminism requires TransientPolicy.despawn.',
      );
    }
    final baseline = initialSnapshot ?? initialBaseline;
    final cold = _coldReplay(
      emptyTemplate,
      target,
      baseline,
      transientPolicy: transientPolicy,
    );
    seekTo(target, transientPolicy: transientPolicy);
    final hot = capturePersistentKeyedColumns(world, options: snapshotOptions);
    return persistentCapturesEqual(cold, hot);
  }

  Map<int, Map<String, Object?>> _coldReplay(
    final World template,
    final ReplayPosition target,
    final WorldSnapshot? baseline, {
    required final TransientPolicy transientPolicy,
  }) {
    final cold = _cloneWorldTemplate(template);
    final player = ReplayPlayer(
      world: cold,
      log: log,
      checkpoints: checkpoints,
      snapshotOptions: snapshotOptions,
      resourceFactories: resourceFactories,
      componentFactories: componentFactories,
      inputReplayer: inputReplayer,
      checkpointRestoreMode: checkpointRestoreMode,
      initialBaseline: baseline ?? initialBaseline,
    );
    player.seekTo(target, transientPolicy: transientPolicy);
    return capturePersistentKeyedColumns(cold, options: snapshotOptions);
  }

  World _cloneWorldTemplate(final World template) => template;

  WorldSnapshot _baselineSnapshot() =>
      initialBaseline ??
      WorldSnapshot(
        version: worldSnapshotVersion,
        schemaVersion: snapshotOptions.schemaVersion,
        componentIds: const {},
        resources: const {},
        entities: const [],
      );

  void _applyBaseline(final WorldSnapshot baseline) {
    reconcileWorldSnapshot(
      world,
      baseline,
      resourceFactories: resourceFactories,
      componentFactories: componentFactories,
      options: snapshotOptions,
      despawnAbsent: true,
    );
    world.flush();
  }

  void _restoreCheckpoint(final WorldSnapshot snapshot) {
    switch (checkpointRestoreMode) {
      case CheckpointRestoreMode.reconcile:
        reconcileWorldSnapshot(
          world,
          snapshot,
          resourceFactories: resourceFactories,
          componentFactories: componentFactories,
          options: snapshotOptions,
          despawnAbsent: true,
        );
      case CheckpointRestoreMode.spawn:
        restoreWorldSnapshot(
          world,
          snapshot,
          resourceFactories: resourceFactories,
          componentFactories: componentFactories,
          options: WorldSnapshotOptions(
            includeOnly: snapshotOptions.includeOnly,
            codecs: snapshotOptions.codecs,
            schemaVersion: snapshotOptions.schemaVersion,
            strictComponents: snapshotOptions.strictComponents,
            restoreMode: WorldSnapshotRestoreMode.spawn,
          ),
        );
    }
    world.flush();
  }

  void _applyTransientPolicy(final TransientPolicy policy) {
    if (policy == TransientPolicy.keep) return;
    _despawnTransientEntities();
  }

  void _despawnTransientEntities() {
    registerPersistentId(world);
    final toDespawn = <Entity>[];
    for (final archetype in world.archetypes.all) {
      for (final entity in archetype.entities) {
        if (persistentIdOf(world, entity) == null) {
          toDespawn.add(entity);
        }
      }
    }
    for (final entity in toDespawn) {
      world.despawnEntity(entity);
    }
    world.flush();
  }

  void _applyEntry(final ReplayEntry entry) {
    switch (entry.kind) {
      case ReplayEntryKind.command:
        final raw = entry.payload[commandOutcomeKey];
        if (raw is! Map<String, Object?>) {
          throw StateError('Command entry missing "$commandOutcomeKey".');
        }
        final outcome = WorldSnapshot.fromJson(raw);
        reconcileWorldSnapshot(
          world,
          outcome,
          resourceFactories: resourceFactories,
          componentFactories: componentFactories,
          options: snapshotOptions,
          despawnAbsent: false,
        );
        world.flush();
      case ReplayEntryKind.input:
        final type = entry.payload[inputTypeKey] as String? ?? '';
        final data =
            (entry.payload[inputDataKey] as Map<String, Object?>?) ?? const {};
        if (inputReplayer == null) {
          throw StateError('Input replay requires an inputReplayer callback.');
        }
        inputReplayer!(world, type, data);
        world.flush();
    }
  }

  int _maxSeqAtTick(final int tick) {
    var maxSeq = 0;
    for (final entry in log.entries) {
      if (entry.tick == tick && entry.seq >= maxSeq) {
        maxSeq = entry.seq;
      }
    }
    return maxSeq;
  }
}
