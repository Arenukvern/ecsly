import 'package:meta/meta.dart';

/// A world event-channel event reduced to sync-relevant fields.
///
/// Event-channel events in the core runtime are runtime-scoped; replicas
/// only need a stable name, a key, and a JSON-encodable payload to converge.
/// Each event becomes exactly one kernel op, folded under the kernel's LWW
/// map strategy under an `event/…` key namespace.
@immutable
final class WorldSyncEvent {
  /// Creates a sync event with [name], [key], and JSON-encodable [value].
  const WorldSyncEvent({required this.name, required this.key, this.value});

  /// Event name (stable across replicas).
  final String name;

  /// Key within the event — often an entity's stable identity, but any
  /// string works.
  final String key;

  /// JSON-encodable payload.
  final Object? value;

  /// Sync key this event folds under: `event/<name>/<key>`.
  String get syncKey => 'event/$name/$key';

  /// JSON round-trip form.
  Map<String, Object?> toJson() => {'name': name, 'key': key, 'value': value};

  @override
  String toString() => 'WorldSyncEvent($syncKey = $value)';
}
