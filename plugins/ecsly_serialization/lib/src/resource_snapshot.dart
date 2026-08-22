import 'package:ecsly/ecsly.dart';

/// Mixin for resources that participate in serialization snapshots.
///
/// Resources implementing this mixin are captured automatically during
/// [captureResourceSnapshot] and restored via registered factories during
/// [restoreResourceSnapshot].
///
/// Pair with hand-written or generated `toJson` implementations:
///
/// ```dart
/// class GameConfig extends Resource with SnapshotableResource {
///   GameConfig({this.speed = 100});
///   final double speed;
///
///   @override
///   Map<String, Object?> toJson() => {'speed': speed};
///
///   static GameConfig fromJson(Map<String, Object?> json) =>
///       GameConfig(speed: (json['speed'] as num).toDouble());
/// }
/// ```
mixin SnapshotableResource on Resource {
  /// Serialize this resource to a JSON-compatible map.
  Map<String, Object?> toJson();
}

/// Type-erased factory for deserializing a [SnapshotableResource].
///
/// Register one per snapshotable resource type so the serializer can restore
/// resources from JSON without knowing the concrete type at compile time.
typedef SnapshotResourceFactory = Resource Function(Map<String, Object?> json);

/// Captures all [SnapshotableResource] resources from [world] into a JSON map.
///
/// Each resource is stored under its runtime type name as key.
/// The [factories] map is not needed for capture — only for restore.
Map<String, Object?> captureResourceSnapshot(final World world) {
  final snapshot = <String, Object?>{};
  for (final resource in world.resources.iterDense()) {
    if (resource is SnapshotableResource) {
      snapshot[resource.runtimeType.toString()] = resource.toJson();
    }
  }
  return snapshot;
}

/// Restores [SnapshotableResource] resources into [world] from a JSON map.
///
/// The [factories] map provides deserialization for each resource type.
/// Keys must match the type name used during capture.
void restoreResourceSnapshot(
  final World world,
  final Map<String, Object?> snapshot,
  final Map<String, SnapshotResourceFactory> factories,
) {
  world.resources.ensureFlushed();

  for (final entry in factories.entries) {
    final json = snapshot[entry.key];
    if (json is! Map) continue;
    final resolved = json.map(
      (final key, final value) => MapEntry(key.toString(), value),
    );
    final resource = entry.value(resolved);
    world.resources.pushByType(resource.runtimeType, resource);
  }
  world.resources.flush();
}
