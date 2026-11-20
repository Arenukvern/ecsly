import 'package:ecsly/ecsly.dart';

import 'entity_refs.dart';

/// Mixin for resources that participate in serialization snapshots.
///
/// Resources implementing this mixin are captured automatically during
/// [captureResourceSnapshot] and restored via the [SnapshotResourceRegistry]
/// (or the legacy factories map) during [restoreResourceSnapshot].
///
/// Entity references inside resource payloads are first-class: capture
/// receives an [EntityRefEncoder] to rewrite runtime `Entity` handles into
/// stable identities; restore factories receive an [EntityRefResolver] to
/// resolve them back — resources hold `Entity` handles directly, with no
/// `persisted*` shadow fields (ADR 0007 §4).
///
/// ```dart
/// class GameConfig extends Resource with SnapshotableResource {
///   GameConfig({this.speed = 100});
///   final double speed;
///
///   @override
///   Map<String, Object?> toJson(EntityRefEncoder refs) => {'speed': speed};
///
///   static GameConfig fromJson(Map<String, Object?> json, EntityRefResolver refs) =>
///       GameConfig(speed: (json['speed'] as num).toDouble());
/// }
/// ```
mixin SnapshotableResource on Resource {
  /// Serialize this resource to a JSON-compatible map, rewriting entity
  /// references through [refs].
  Map<String, Object?> toJson(EntityRefEncoder refs);
}

/// Type-erased factory for deserializing a [SnapshotableResource] from a
/// legacy (resolver-less) factory map.
///
/// Prefer [SnapshotResourceRegistry], whose factories receive the
/// [EntityRefResolver] and can hold `Entity` references directly.
typedef SnapshotResourceFactory = Resource Function(Map<String, Object?> json);

/// Factory signature for registry-registered resources: receives the
/// restore [EntityRefResolver] so payloads may reference entities.
typedef SnapshotResourceRegistryFactory =
    Resource Function(Map<String, Object?> json, EntityRefResolver refs);

/// Registry pairing snapshotable resources with their stable snapshot name
/// and restore factory (ADR 0007 §5).
///
/// Registration IS the factory map: declare name + factory once here and
/// the per-app hand-written string-literal maps die. Capture keys the
/// resource under its registered [name] instead of
/// `runtimeType.toString()` — stable against renames, name collisions and
/// web minification.
class SnapshotResourceRegistry {
  final Map<String, SnapshotResourceRegistryFactory> _factories = {};
  final Map<Type, String> _names = {};

  /// Registers [T] under stable [name] with its restore [factory].
  ///
  /// [aliases] are additional snapshot keys the same factory restores —
  /// legacy type-name keys from saves written before the resource was
  /// registered under a stable name. Capture always writes [name].
  void register<T extends Resource>(
    String name,
    SnapshotResourceRegistryFactory factory, {
    Set<String> aliases = const <String>{},
  }) {
    final existing = _names[T];
    if (existing != null && existing != name) {
      throw StateError(
        'Resource $T is already registered as "$existing" and cannot be '
        're-registered as "$name".',
      );
    }
    _names[T] = name;
    _factories[name] = factory;
    for (final alias in aliases) {
      _factories.putIfAbsent(alias, () => factory);
    }
  }

  /// The registered snapshot name for [resource]'s type, or null.
  String? nameOf(Resource resource) => _names[resource.runtimeType];

  /// The registered factory for snapshot [name], or null.
  SnapshotResourceRegistryFactory? factoryFor(String name) =>
      _factories[name];

  /// All registered names.
  Iterable<String> get names => _factories.keys;
}

/// Captures all [SnapshotableResource] resources from [world] into a JSON map.
///
/// Each resource is stored under its registry [SnapshotResourceRegistry.nameOf]
/// when registered, otherwise under its runtime type name. The registry and
/// factories are not needed for capture — only for restore.
Map<String, Object?> captureResourceSnapshot(
  World world, {
  SnapshotResourceRegistry? registry,
}) {
  final refs = EntityRefEncoder(world);
  final snapshot = <String, Object?>{};
  for (final resource in world.resources.iterDense()) {
    if (resource is SnapshotableResource) {
      final name = registry?.nameOf(resource) ?? resource.runtimeType.toString();
      snapshot[name] = resource.toJson(refs);
    }
  }
  return snapshot;
}

/// Restores [SnapshotableResource] resources into [world] from a JSON map.
///
/// [registry] provides resolver-aware deserialization for registered
/// resources (the first-class path). [factories] is the legacy resolver-less
/// map — supported for back-compat, but it cannot restore resources holding
/// entity references. Registry entries take precedence.
void restoreResourceSnapshot(
  World world,
  Map<String, Object?> snapshot, {
  Map<String, SnapshotResourceFactory> factories =
      const <String, SnapshotResourceFactory>{},
  SnapshotResourceRegistry? registry,
  EntityRefResolver? refs,
}) {
  world.resources.ensureFlushed();

  for (final entry in snapshot.entries) {
    final json = entry.value;
    if (json is! Map) continue;
    final resolved = json.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    Resource? resource;
    final registryFactory = registry?.factoryFor(entry.key);
    if (registryFactory != null) {
      resource = registryFactory(resolved, refs ?? const _NullResolver());
    } else {
      final legacyFactory = factories[entry.key];
      if (legacyFactory == null) continue;
      resource = legacyFactory(resolved);
    }
    world.resources.pushByType(resource.runtimeType, resource);
  }
  world.resources.flush();
}

class _NullResolver implements EntityRefResolver {
  const _NullResolver();

  @override
  Map<String, Entity> get mapping => const {};

  @override
  Entity resolve(Object? raw) {
    final isEmptyOrNull = raw == null || raw == '' || raw == 0 || raw == '0';
    if (isEmptyOrNull) return Entity.nullEntity;
    throw StateError(
      'No entity-reference resolver available; resource payloads in this '
      'snapshot cannot be resolved. Pass refs to restoreResourceSnapshot.',
    );
  }

  @override
  List<Entity> resolveList(Object? raw) => const [];
}
