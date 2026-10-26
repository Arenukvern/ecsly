import 'dart:convert';

import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// Read-only projection of a world's synced state, folded from kernel ops.
///
/// This is derived data — a projection, never a source of truth (the same
/// discipline ADR 0011 records for the kernel). Values are decoded from the
/// JSON-encoded form the sync layer stores under the kernel's LWW map
/// strategy; tombstoned keys are absent.
final class WorldProjection {
  const WorldProjection._(this._values);

  /// Builds a projection over a kernel LWW-map fold.
  ///
  /// Values are read through the kernel's own public readers
  /// ([LwwMapStrategy.readValue]) — the sync layer never re-derives fold
  /// rules, it only decodes the JSON payload it encoded.
  factory WorldProjection.fromState(final Map<String, Object?> state) {
    final values = <String, Object?>{};
    for (final key in state.keys) {
      final encoded = LwwMapStrategy.readValue(state, key);
      if (encoded == null) continue;
      values[key] = jsonDecode(encoded) as Object?;
    }
    return WorldProjection._(Map.unmodifiable(values));
  }

  final Map<String, Object?> _values;

  /// All live synced values by sync key (tombstones excluded).
  Map<String, Object?> get values => _values;

  /// Raw value for [key], or `null` when absent/tombstoned. Note that a
  /// stored `null` value is also reported as `null`; use [contains] when
  /// the distinction matters.
  Object? operator [](final String key) => _values[key];

  /// Whether [key] currently holds a live (non-tombstoned) value.
  bool contains(final String key) => _values.containsKey(key);

  /// Value for a component field, or `null` when absent/tombstoned.
  Object? componentValue({
    required final String entityKey,
    required final String component,
    required final String field,
  }) =>
      _values['$entityKey/$component/$field'];

  /// Value for a sync event, or `null` when absent/tombstoned.
  Object? eventValue({
    required final String name,
    required final String key,
  }) =>
      _values['event/$name/$key'];

  @override
  String toString() => 'WorldProjection(${_values.length} keys)';
}
