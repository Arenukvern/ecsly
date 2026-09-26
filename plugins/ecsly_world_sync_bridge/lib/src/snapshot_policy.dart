import 'package:ecsly_world_sync/ecsly_world_sync.dart';
import 'package:meta/meta.dart';

/// Parent-chosen compaction policy for a [WorldSync] replica (ecsly ADR
/// 0002): when the kernel should fold the pending op log into state.
///
/// Two triggers, whichever fires first:
///
/// - **Size** — the log grew past [maxLogOps];
/// - **Age** — the log is non-empty and [minInterval] elapsed since the
///   owner's last compaction.
///
/// The policy itself is pure: the owner (typically the anti-entropy driver)
/// tracks `lastCompactionAt` and passes it in. An empty log never
/// compacts — there is nothing to retire.
@immutable
final class SnapshotPolicy {
  /// Creates a policy. Defaults: 512 ops, 5 minutes.
  const SnapshotPolicy({
    this.maxLogOps = defaultMaxLogOps,
    this.minInterval = defaultMinInterval,
  });

  /// Default log-length trigger.
  static const int defaultMaxLogOps = 512;

  /// Default compaction interval.
  static const Duration defaultMinInterval = Duration(minutes: 5);

  /// Compact once the pending log exceeds this many ops.
  final int maxLogOps;

  /// Compact no more often than this (when the log is non-empty).
  final Duration minInterval;

  /// Whether [sync] should compact now.
  ///
  /// [lastCompactionAt] is the owner's last compaction timestamp; `null`
  /// means "never compacted by this owner", in which case only the size
  /// trigger can fire (there is no interval to have elapsed yet).
  bool shouldCompact(
    final WorldSync sync,
    final DateTime now, {
    final DateTime? lastCompactionAt,
  }) {
    final logLength = sync.pendingOps.length;
    if (logLength > maxLogOps) return true;
    if (logLength == 0) return false;
    final since = lastCompactionAt == null
        ? null
        : now.difference(lastCompactionAt);
    return since != null && since >= minInterval;
  }

  @override
  String toString() =>
      'SnapshotPolicy(maxLogOps: $maxLogOps, minInterval: $minInterval)';
}
