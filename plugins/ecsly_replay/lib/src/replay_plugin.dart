import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

import 'checkpoint_restore_mode.dart';
import 'checkpoint_store.dart';
import 'replay_log.dart';
import 'replay_player.dart';
import 'replay_recorder.dart';
import 'transient_policy.dart';

/// World-bound replay state installed by [ReplayPlugin].
///
/// One resource wires the whole record-and-seek story together: the
/// append-only [log], the [checkpoints] store, the [recorder] that captures
/// command outcomes, and the [player] bound to the same world.
class ReplayStateResource extends Resource {
  /// Creates the state bundle; all four pieces share one log and store.
  ReplayStateResource({
    required this.log,
    required this.checkpoints,
    required this.recorder,
    required this.player,
  });

  /// The append-only replay log.
  final ReplayLog log;

  /// Checkpoint store aligned with [log].
  final CheckpointStore checkpoints;

  /// Recorder writing command outcomes (and optional inputs) into [log].
  final ReplayRecorder recorder;

  /// Player seeking within [log] against the installing world.
  final ReplayPlayer player;
}

/// Plugin that makes record-and-seek replay native to the ECS.
///
/// Installs a [ReplayStateResource] wiring log, checkpoints, recorder, and
/// a player bound to the world — no external construction needed:
///
/// ```dart
/// world.addPlugin(ReplayPlugin(
///   header: ReplayLogHeader(
///     formatVersion: replayLogFormatVersion,
///     fingerprints: ReplayFingerprints(
///       buildFingerprint: myBuildId,
///       schemaFingerprint: 'schema-$schemaVersion',
///     ),
///   ),
/// ));
///
/// final state = world.getResource<ReplayStateResource>();
/// state.recorder.recordCommand(
///   tick: tick,
///   outcome: captureWorldSnapshot(world),
/// );
/// ```
///
/// The recorder and player are deliberately reachable from systems and host
/// tooling through the resource; recording cadence and seek calls stay
/// host-driven, exactly like the standalone API.
class ReplayPlugin extends Plugin {
  /// Creates the plugin from a replay [header] and restore-policy options.
  ReplayPlugin({
    required this.header,
    this.checkpointCadence = 10,
    this.snapshotOptions = const WorldSnapshotOptions(),
    this.resourceFactories = const {},
    this.componentFactories = const {},
    this.inputReplayer,
    this.checkpointRestoreMode = CheckpointRestoreMode.reconcile,
    this.initialBaseline,
    this.defaultTransientPolicy = TransientPolicy.keep,
  });

  /// Log header: format version plus build/schema fingerprints.
  final ReplayLogHeader header;

  /// Checkpoint cadence handed to [CheckpointStore].
  final int checkpointCadence;

  /// Capture/restore options shared by recorder and player.
  final WorldSnapshotOptions snapshotOptions;

  /// Resource factories for reconcile/restore.
  final Map<String, SnapshotResourceFactory> resourceFactories;

  /// Component factories for object-tier components.
  final Map<String, Component Function()> componentFactories;

  /// Optional input applier for [ReplayEntryKind.input] rows.
  final InputReplayer? inputReplayer;

  /// Checkpoint restore strategy.
  final CheckpointRestoreMode checkpointRestoreMode;

  /// Baseline when seeking before the first checkpoint.
  final WorldSnapshot? initialBaseline;

  /// Default transient-entity policy for seeks.
  final TransientPolicy defaultTransientPolicy;

  @override
  String get name => 'ecsly_replay';

  @override
  void install(final World world) {
    final log = ReplayLog(header: header);
    final checkpoints = CheckpointStore(cadence: checkpointCadence);
    final recorder = ReplayRecorder(
      log: log,
      checkpoints: checkpoints,
      snapshotOptions: snapshotOptions,
    );
    final player = ReplayPlayer(
      world: world,
      log: log,
      checkpoints: checkpoints,
      snapshotOptions: snapshotOptions,
      resourceFactories: resourceFactories,
      componentFactories: componentFactories,
      inputReplayer: inputReplayer,
      checkpointRestoreMode: checkpointRestoreMode,
      initialBaseline: initialBaseline,
      defaultTransientPolicy: defaultTransientPolicy,
    );
    world.upsertResource(
      ReplayStateResource(
        log: log,
        checkpoints: checkpoints,
        recorder: recorder,
        player: player,
      ),
    );
  }

  @override
  void uninstall(final World world) {
    world.resources.remove<ReplayStateResource>();
  }
}
