import 'package:ecsly/ecsly.dart';
import 'package:meta/meta.dart';

/// Optional data-only projection from stable app/domain ids to ECS entities.
///
/// The stable id itself should live on a normal component. This resource is
/// only a cold app/plugin lookup cache for screens or actions that repeatedly
/// need to resolve an external id to the current runtime [Entity].
///
/// [TScope] separates id spaces that use the same key type, such as todo ids
/// and user ids that are both strings.
@experimental
class EntityIndexResource<TScope, K> extends Resource {
  EntityIndexResource([Map<K, Entity>? initial])
    : _entities = initial == null ? <K, Entity>{} : Map<K, Entity>.of(initial);

  final Map<K, Entity> _entities;

  Iterable<K> get keys => _entities.keys;

  Iterable<Entity> get entities => _entities.values;

  int get length => _entities.length;

  bool get isEmpty => _entities.isEmpty;

  bool containsKey(K key) => _entities.containsKey(key);

  Entity? maybeEntityOf(K key) => _entities[key];

  Entity entityOf(K key) {
    final entity = _entities[key];
    if (entity != null) return entity;
    throw StateError('No ECS entity indexed for key $key.');
  }

  void upsert(K key, Entity entity) {
    _entities[key] = entity;
  }

  Entity? remove(K key) => _entities.remove(key);

  void clear() {
    _entities.clear();
  }

  Map<K, Entity> toMap() => Map<K, Entity>.unmodifiable(_entities);
}
