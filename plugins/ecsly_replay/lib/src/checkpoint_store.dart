// ignore_for_file: prefer_final_parameters

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

/// Stores serialized [WorldSnapshot]s at a tick cadence for fast seek.
class CheckpointStore {
  /// Creates a store.
  CheckpointStore({this.cadence = 10}) : _byTick = <int, WorldSnapshot>{};

  /// Record a checkpoint every [cadence] ticks (must be >= 1).
  final int cadence;

  final Map<int, WorldSnapshot> _byTick;

  /// Recorded checkpoint ticks in ascending order.
  Iterable<int> get checkpointTicks => _byTick.keys.toList()..sort();

  /// Returns whether [tick] should receive a new checkpoint.
  bool shouldCheckpoint(int tick) =>
      cadence > 0 && tick % cadence == 0;

  /// Captures and stores [world] at [tick].
  void save(
    World world,
    int tick, {
    WorldSnapshotOptions options = const WorldSnapshotOptions(),
  }) {
    _byTick[tick] = captureWorldSnapshot(world, options: options);
  }

  /// Nearest checkpoint tick `<=` [targetTick], or null.
  int? nearestTickAtOrBefore(int targetTick) {
    int? best;
    for (final tick in _byTick.keys) {
      if (tick <= targetTick && (best == null || tick > best)) {
        best = tick;
      }
    }
    return best;
  }

  /// Snapshot at [tick], or null.
  WorldSnapshot? snapshotAt(int tick) => _byTick[tick];

  /// Drops checkpoints at or after [tick] (after log rewrite).
  void invalidateFromTick(int tick) {
    _byTick.removeWhere((key, _) => key >= tick);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'cadence': cadence,
    'checkpoints': _byTick.map(
      (tick, snap) => MapEntry(tick.toString(), snap.toJson()),
    ),
  };

  // ignore: prefer_constructors_over_static_methods
  static CheckpointStore fromJson(Map<String, Object?> json) {
    final store = CheckpointStore(
      cadence: (json['cadence'] as num?)?.toInt() ?? 10,
    );
    final raw = (json['checkpoints'] as Map<String, Object?>?) ?? const {};
    for (final entry in raw.entries) {
      final tick = int.tryParse(entry.key);
      if (tick == null) continue;
      final snapMap = entry.value as Map<String, Object?>?;
      if (snapMap == null) continue;
      store._byTick[tick] = WorldSnapshot.fromJson(snapMap);
    }
    return store;
  }
}
