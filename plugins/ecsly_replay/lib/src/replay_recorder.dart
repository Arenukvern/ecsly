// ignore_for_file: prefer_final_parameters

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

import 'checkpoint_store.dart';
import 'replay_entry.dart';
import 'replay_log.dart';

/// Records commands (with outcomes) and optional checkpoints.
class ReplayRecorder {
  /// Creates a recorder.
  ReplayRecorder({
    required this.log,
    required this.checkpoints,
    this.snapshotOptions = const WorldSnapshotOptions(),
  });

  /// Target log.
  final ReplayLog log;

  /// Checkpoint store (shared with [ReplayPlayer]).
  final CheckpointStore checkpoints;

  /// Options used when capturing outcomes and checkpoints.
  final WorldSnapshotOptions snapshotOptions;

  /// Records a command whose [outcome] is the world after the command runs.
  ReplayEntry recordCommand({
    required final int tick,
    required final WorldSnapshot outcome,
    final String? eventKey,
    final String? label,
  }) {
    final entry = ReplayEntry(
      tick: tick,
      seq: log.nextSeqForTick(tick),
      kind: ReplayEntryKind.command,
      eventKey: eventKey,
      payload: <String, Object?>{
        if (label != null) commandLabelKey: label,
        commandOutcomeKey: outcome.toJson(),
      },
    );
    log.append(entry);
    return entry;
  }

  /// Records an input row (replayed by host systems).
  ReplayEntry recordInput({
    required final int tick,
    required final String inputType,
    required final Map<String, Object?> data,
    final String? eventKey,
  }) {
    final entry = ReplayEntry(
      tick: tick,
      seq: log.nextSeqForTick(tick),
      kind: ReplayEntryKind.input,
      eventKey: eventKey,
      payload: <String, Object?>{
        inputTypeKey: inputType,
        inputDataKey: data,
      },
    );
    log.append(entry);
    return entry;
  }

  /// Captures a checkpoint when [tick] matches [CheckpointStore.cadence].
  void maybeCheckpoint(final World world, final int tick) {
    if (!checkpoints.shouldCheckpoint(tick)) return;
    checkpoints.save(world, tick, options: snapshotOptions);
  }

  /// Rewrites history from [position] (invalidates checkpoints).
  void truncateFrom(final ReplayPosition position) {
    log.truncateFrom(position);
    checkpoints.invalidateFromTick(position.tick);
  }
}
