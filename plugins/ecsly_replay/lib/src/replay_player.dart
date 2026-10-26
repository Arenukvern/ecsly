// ignore_for_file: prefer_final_parameters

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

import 'checkpoint_store.dart';
import 'determinism.dart';
import 'replay_entry.dart';
import 'replay_log.dart';
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

  /// Current inclusive position after the last [seek].
  ReplayPosition _position = const ReplayPosition(tick: -1, seq: -1);

  /// Position after the last successful [seek].
  ReplayPosition get position => _position;

  /// Seeks to the inclusive end of [targetTick] (all rows with that tick).
  void seekToTick(final int targetTick) {
    final lastSeq = _maxSeqAtTick(targetTick);
    seekTo(ReplayPosition(tick: targetTick, seq: lastSeq));
  }

  /// Seeks to the inclusive position of [eventKey].
  void seekToEventKey(final String eventKey) {
    final found = log.positionForEventKey(eventKey);
    if (found == null) {
      throw StateError('Unknown eventKey "$eventKey".');
    }
    seekTo(found);
  }

  /// Seeks to [target] by restoring the nearest checkpoint and replaying.
  void seekTo(final ReplayPosition target) {
    if (target.tick < 0) {
      throw ArgumentError.value(target, 'target', 'tick must be non-negative.');
    }

    final checkpointTick = checkpoints.nearestTickAtOrBefore(target.tick);
    if (checkpointTick != null) {
      final snap = checkpoints.snapshotAt(checkpointTick);
      if (snap != null) {
        _restoreFull(snap);
        _position = ReplayPosition(
          tick: checkpointTick,
          seq: _maxSeqAtTick(checkpointTick),
        );
      }
    } else {
      _position = const ReplayPosition(tick: -1, seq: -1);
    }

    for (final entry in log.entries) {
      if (!entry.isAfterPosition(_position)) continue;
      if (!entry.isBeforeOrAt(target.tick, target.seq)) break;
      _applyEntry(entry);
      _position = ReplayPosition.after(entry);
    }
  }

  /// Cold replay from empty vs hot [seekTo] at [target]; returns equality.
  bool verifyDeterminism({
    required final World emptyTemplate,
    required final ReplayPosition target,
    final WorldSnapshot? initialSnapshot,
  }) {
    final cold = _coldReplay(emptyTemplate, target, initialSnapshot);
    seekTo(target);
    final hot = capturePersistentKeyedColumns(world, options: snapshotOptions);
    return persistentCapturesEqual(cold, hot);
  }

  Map<int, Map<String, Object?>> _coldReplay(
    final World template,
    final ReplayPosition target,
    final WorldSnapshot? initialSnapshot,
  ) {
    final cold = _cloneWorldTemplate(template);
    if (initialSnapshot != null) {
      restoreWorldSnapshot(
        cold,
        initialSnapshot,
        resourceFactories: resourceFactories,
        componentFactories: componentFactories,
        options: snapshotOptions,
      );
    }
    final player = ReplayPlayer(
      world: cold,
      log: log,
      checkpoints: checkpoints,
      snapshotOptions: snapshotOptions,
      resourceFactories: resourceFactories,
      componentFactories: componentFactories,
      inputReplayer: inputReplayer,
    );
    player.seekTo(target);
    return capturePersistentKeyedColumns(cold, options: snapshotOptions);
  }

  World _cloneWorldTemplate(final World template) {
    // Host supplies a fresh world with the same registrations as [world].
    return template;
  }

  void _restoreFull(final WorldSnapshot snapshot) {
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
