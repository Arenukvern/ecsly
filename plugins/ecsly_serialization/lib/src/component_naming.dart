import 'package:ecsly/ecsly.dart';

/// The snapshot identity for [componentId]: the stable registered name when
/// present, falling back to the component type name (ADR 0007 §5).
///
/// Returns null when the component is not registered in [world].
String? componentSnapshotName(World world, ComponentId componentId) {
  final registered = world.components.nameOf(componentId);
  if (registered != null) return registered;
  try {
    return world.components.getType(componentId).toString();
    // ignore: avoid_catching_errors
  } on EcsStateError {
    return null;
  }
}

/// Resolves a snapshot component identity back to the local [ComponentId].
///
/// Registered stable names resolve in O(1); unregistered names fall back to
/// a `Type.toString()` scan for pre-name snapshots.
ComponentId? componentIdForSnapshotName(World world, String name) {
  final byName = world.components.componentIdByName(name);
  if (byName != null) return byName;
  for (final entry in world.components.registeredTypes.entries) {
    if (entry.value.toString() == name) return entry.key;
  }
  return null;
}

/// The local component [Type] for a snapshot identity, or null.
Type? componentTypeForSnapshotName(World world, String name) {
  final id = componentIdForSnapshotName(world, name);
  if (id == null) return null;
  try {
    return world.components.getType(id);
    // ignore: avoid_catching_errors
  } on EcsStateError {
    return null;
  }
}
