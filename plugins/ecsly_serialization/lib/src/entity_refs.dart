import 'package:ecsly/ecsly.dart';

import 'persistent_entity.dart';

/// Capture-side reference encoder handed to codecs and snapshotable
/// resources (ADR 0007 §4).
///
/// Encodes a runtime [Entity] reference into the stable identity that
/// travels inside snapshot payloads. `Entity.nullEntity` encodes as null;
/// a reference to a **non-persisted entity throws** — this is the one
/// dangling-reference policy for the whole engine, replacing the
/// throw-vs-silent-null split apps previously had to resolve themselves.
class EntityRefEncoder {
  /// Creates the encoder reading identities from [world].
  const EntityRefEncoder(this._world);

  final World _world;

  /// The stable identity of [entity] for a snapshot payload.
  ///
  /// Returns null for [Entity.nullEntity]. Throws [StateError] when
  /// [entity] is alive but carries no [PersistentEntityComponent] — persist
  /// referenced entities via [spawnPersistent].
  String? encode(Entity entity) {
    if (entity.isNull) return null;
    final identity = persistentEntityOf(_world, entity);
    if (identity == null) {
      throw StateError(
        'Cannot snapshot a reference to a non-persisted entity '
        '(${entity.entityToString()}). All referenced entities must carry a '
        'PersistentEntityComponent — spawn them via spawnPersistent.',
      );
    }
    return identity.toJson();
  }

  /// Encodes each reference of [entities], preserving order and nulls.
  List<String?> encodeAll(Iterable<Entity> entities) => [
    for (final entity in entities) encode(entity),
  ];
}

/// Restore-side reference resolver handed to codecs and resource factories
/// (ADR 0007 §4).
///
/// Resolves a raw payload reference back to the live [Entity] using the
/// restore mapping — which never escapes `restoreWorldSnapshot`. Legacy
/// pre-v4 payloads carry int-encoded references; they are normalized, so
/// old saves load without app-level migration steps.
class EntityRefResolver {
  /// Creates the resolver over the restore [mapping] (identity → entity).
  const EntityRefResolver(this.mapping);

  /// The restore mapping: stable identity string → live entity.
  final Map<String, Entity> mapping;

  /// Resolves [raw] to the referenced live entity.
  ///
  /// Null, empty, zero and legacy `0` payloads resolve to
  /// [Entity.nullEntity]. Throws [StateError] when the identity is unknown
  /// to the snapshot — a save referencing an entity it never captured.
  Entity resolve(Object? raw) {
    final key = switch (raw) {
      null => '',
      final int value => '$value',
      final String value => value,
      _ => throw StateError('Not an entity reference: $raw'),
    };
    if (key.isEmpty || key == '0') return Entity.nullEntity;
    final entity = mapping[key];
    if (entity == null) {
      throw StateError('Snapshot references unknown identity $key');
    }
    return entity;
  }

  /// Resolves each reference of [raw], preserving order.
  List<Entity> resolveList(Object? raw) => switch (raw) {
    final List<Object?> list => [for (final item in list) resolve(item)],
    _ => const [],
  };
}
