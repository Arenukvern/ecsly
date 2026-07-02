// ignore_for_file: cascade_invocations

import 'dart:collection';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../archetypes/archetypes.dart';
import 'entity.dart';

export 'entity.dart';
export 'world_entity.dart';
export 'world_entity_extension.dart';
export 'world_entity_mut.dart';

/// The definitive, high-performance entity manager.
///
/// This class is the single source of truth for the lifecycle and location
/// of all entities. It uses tightly packed `Uint32List` buffers for performance
/// and a free-list to recycle entity IDs.
///
/// It has a simple, direct API and does NOT perform any deferred operations.
/// All command queueing and flushing is handled by the `World` and `CommandQueue`.
class Entities {
  static const int _initialCapacity = 1000;

  /// Stores metadata for each entity. We use parallel lists of `TypedData`
  /// for maximum data locality, mimicking a Struct-of-Arrays (SoA) layout.
  var _generations = Uint32List(_initialCapacity);
  var _archetypeIds = Uint32List(_initialCapacity);
  var _archetypeRows = Uint32List(_initialCapacity);

  /// A queue of entity indices that have been destroyed and are available for reuse.
  final Queue<int> _freeList = Queue<int>();

  /// The total number of entities that can be stored in the current buffers.
  int _capacity = _initialCapacity;

  /// The number of currently active entities.
  int _count = 0;
  int get count => _count;

  /// Creates a new, unique entity ID.
  ///
  /// Reuses a recycled ID from the free-list if available, otherwise allocates a new one.
  /// The new entity is immediately considered "alive" but has a null location until
  /// it's assigned to an archetype.
  Entity create() {
    _count++;
    if (_freeList.isNotEmpty) {
      final index = _freeList.removeFirst();
      // The generation was already incremented upon destruction.
      // The location is reset.
      _archetypeIds[index] = 0;
      _archetypeRows[index] = 0;
      return Entity.create(index, _generations[index]);
    } else {
      final index = _count;
      _ensureCapacity(index);
      const generation = EntityGeneration.initial;
      _generations[index] = generation.value;
      _archetypeIds[index] = 0;
      _archetypeRows[index] = 0;
      return Entity.create(index, generation.value);
    }
  }

  /// Destroys an entity, invalidating its ID and recycling its index.
  ///
  /// This increments the entity's generation, ensuring that any old `Entity`
  /// handles become invalid. The index is then added to the free-list for reuse.
  void destroy(final Entity entity) {
    final index = entity.indexValue;
    // Increment the generation to invalidate old handles.
    _generations[index] = _generations[index] + 1;
    // Add the index to the free-list for recycling.
    _freeList.addLast(index);
    _count--;
  }

  /// Gets the storage location of an entity.
  EntityLocation getLocation(final Entity entity) {
    final index = entity.indexValue;
    return EntityLocation(
      ArchetypeId(_archetypeIds[index]),
      _archetypeRows[index],
    );
  }

  /// Live archetype id for [entity] (O(1), no [EntityLocation] allocation).
  ///
  /// Matches [getLocation].entity; use when only the id is needed, e.g. cache
  /// checks while the entity may have migrated after a [WorldEntity] snapshot.
  ArchetypeId archetypeIdOf(final Entity entity) =>
      ArchetypeId(_archetypeIds[entity.indexValue]);

  /// Checks if an entity handle is still valid ("alive").
  ///
  /// An entity is considered alive if its generation in the handle matches
  /// the current generation stored in the manager.
  bool isAlive(final Entity entity) {
    final index = entity.indexValue;
    return index < _capacity && _generations[index] == entity.generation;
  }

  /// Sets the storage location of an entity.
  void setLocation(final Entity entity, final EntityLocation location) {
    final index = entity.indexValue;
    _archetypeIds[index] = location.archetypeId.value;
    _archetypeRows[index] = location.archetypeRow;
  }

  /// Ensures the internal buffers have enough capacity for a given index.
  void _ensureCapacity(final int index) {
    if (index >= _capacity) {
      final newCapacity = (index * 2).clamp(_initialCapacity, 0x7FFFFFFF);
      _capacity = newCapacity;

      _generations = _resizeBuffer(_generations, newCapacity);
      _archetypeIds = _resizeBuffer(_archetypeIds, newCapacity);
      _archetypeRows = _resizeBuffer(_archetypeRows, newCapacity);
    }
  }

  /// Helper to create a new `Uint32List` with the new capacity and copy old data.
  Uint32List _resizeBuffer(final Uint32List oldBuffer, final int newCapacity) {
    final newBuffer = Uint32List(newCapacity);
    newBuffer.setAll(0, oldBuffer);
    return newBuffer;
  }
}

/// A simple struct to hold an entity's location.
/// This is stored in the `Entities` manager.
@immutable
class EntityLocation {
  const EntityLocation(this.archetypeId, this.archetypeRow);
  static const nullLocation = EntityLocation(ArchetypeId.zero, 0);
  final ArchetypeId archetypeId;

  final int archetypeRow;
}
