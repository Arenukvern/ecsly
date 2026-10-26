// ignore_for_file: prefer_final_parameters

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';

/// Capture keyed by [PersistentId] for cold-vs-hot replay comparison.
Map<int, Map<String, Object?>> capturePersistentKeyedColumns(
  final World world, {
  final WorldSnapshotOptions options = const WorldSnapshotOptions(),
}) {
  final snapshot = captureWorldSnapshot(world, options: options);
  return {
    for (final entry in snapshot.entities)
      entry.persistentId: Map<String, Object?>.from(entry.columns),
  };
}

/// Returns true when [a] and [b] describe the same persisted entity state.
bool persistentCapturesEqual(
  final Map<int, Map<String, Object?>> a,
  final Map<int, Map<String, Object?>> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null) return false;
    if (entry.value.length != other.length) return false;
    for (final col in entry.value.entries) {
      if (!_jsonEqual(col.value, other[col.key])) return false;
    }
  }
  return true;
}

bool _jsonEqual(final Object? a, final Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!_jsonEqual(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
