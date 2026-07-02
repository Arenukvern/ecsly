import 'dart:collection';

import 'package:meta/meta.dart';

import '../errors/ecs_errors.dart';
import '../world/world.dart';
import 'resource.dart';

typedef TypeResourceRecord = (Type, Resource);

class ResourceRegistry {
  ResourceRegistry({required this.world});

  final World world;

  // Type → ResourceId mappings for registration and lookup
  final Map<Type, ResourceId> _typeToId = {};
  final Map<ResourceId, Type> _idToType = {};
  int _nextId = 0;

  // Dense array storage for O(1) access (replaces MutableOrderedMap)
  List<Resource?> _resources = [];

  // Dense list of active resource IDs (non-null resources only).
  final List<int> _presentResourceIds = <int>[];
  final List<int> _presentDenseIndexById = <int>[];

  // Free-list for ResourceId recycling (similar to Entities pattern)
  final Queue<int> _freeIds = Queue<int>();
  int _revision = 0;

  @internal
  final pendingPush = Queue<TypeResourceRecord>();
  @internal
  final pendingRemove = Queue<Type>();

  /// Debug-only: mapping of ResourceId to registered type.
  Map<ResourceId, Type> get debugIdToType => Map.unmodifiable(_idToType);

  /// Debug-only: all registered resource types (includes absent resources).
  Iterable<Type> get debugRegisteredTypes => _typeToId.keys;

  /// Debug-only: mapping of resource type to assigned ResourceId.
  Map<Type, ResourceId> get debugTypeToId => Map.unmodifiable(_typeToId);

  bool get doesNeedFlush => pendingPush.isNotEmpty || pendingRemove.isNotEmpty;

  int get pendingPushCount => pendingPush.length;

  int get pendingRemoveCount => pendingRemove.length;

  int get revision => _revision;

  void clear() {
    pendingPush.clear();
    pendingRemove.clear();
    _typeToId.clear();
    _idToType.clear();
    _nextId = 0;
    _resources = [];
    _presentResourceIds.clear();
    _presentDenseIndexById.clear();
    _freeIds.clear();
    _revision = 0;
  }

  /// Conditionally flushes resources if any pending changes exist.
  ///
  /// This method only flushes resource changes (not entire world).
  /// More efficient than world.ensureFlushed() when only resources changed.
  void ensureFlushed() {
    if (doesNeedFlush) {
      flush();
    }
  }

  void flush() {
    flushToRemove();
    flushToUpsert();
  }

  void flushToRemove() {
    // 1. **Atomic Swap:** Get the entities to process and replace the old queue with a new, empty one.
    final itemsToProceed = ListQueue<Type>();
    // Transfer all elements from the pending queue to the processing queue
    while (pendingRemove.isNotEmpty) {
      itemsToProceed.addLast(pendingRemove.removeFirst());
    }
    // At this point, pendingEntities is empty and ready to accept new additions.
    while (itemsToProceed.isNotEmpty) {
      final type = itemsToProceed.removeFirst();

      // Dense array: Set to null and recycle ResourceId
      final resourceId = _typeToId.remove(type);
      if (resourceId != null) {
        _idToType.remove(resourceId);
        _ensureCapacity(resourceId.value + 1);
        if (_resources[resourceId.value] != null) {
          _resources[resourceId.value] = null;
          _removePresentResourceId(resourceId.value);
          _revision += 1;
        }
        _freeIds.addLast(resourceId.value);
      }
    }
  }

  void flushToUpsert() {
    // 1. **Atomic Swap:** Get the entities to process and replace the old queue with a new, empty one.
    final itemsToProceed = ListQueue<TypeResourceRecord>();
    // Transfer all elements from the pending queue to the processing queue
    while (pendingPush.isNotEmpty) {
      itemsToProceed.addLast(pendingPush.removeFirst());
    }
    // At this point, pendingEntities is empty and ready to accept new additions.
    while (itemsToProceed.isNotEmpty) {
      final (type, resource) = itemsToProceed.removeFirst();

      // Dense array: Get or assign ResourceId and store in array
      var resourceId = _typeToId[type];
      resourceId ??= registerResourceByType(type);
      _ensureCapacity(resourceId.value + 1);
      if (_resources[resourceId.value] == null) {
        _addPresentResourceId(resourceId.value);
      }
      _resources[resourceId.value] = resource;
      _revision += 1;
    }
  }

  @internal
  T get<T extends Resource>() {
    // Auto-flush resources only (more efficient than world.ensureFlushed)
    ensureFlushed();

    // Fast path: Use ResourceId for O(1) array access if registered
    final resourceId = _typeToId[T];
    if (resourceId != null) {
      final resource = getById<T>(resourceId);
      if (resource != null) {
        return resource;
      }
    }
    throw EcsStateError('Resource not found for type $T');
  }

  /// Gets a resource by ResourceId for O(1) direct access.
  ///
  /// This is the hot path - direct array access without Type lookup.
  /// Use this when you have a pre-registered ResourceId.
  ///
  /// Returns null if ResourceId is invalid or resource not found.
  @internal
  T? getById<T extends Resource>(final ResourceId id) {
    ensureFlushed();

    if (!id.isValid || id.value >= _resources.length) {
      return null;
    }

    final resource = _resources[id.value];
    return resource as T?;
  }

  /// Gets a resource by ResourceId for O(1) direct access (throws if not found).
  ///
  /// This is the hot path - direct array access without Type lookup.
  /// Use this when you have a pre-registered ResourceId and expect the resource to exist.
  T getByIdOrThrow<T extends Resource>(final ResourceId id) {
    final resource = getById<T>(id);
    if (resource == null) {
      final type = getType(id);
      throw ArgumentError.notNull(
        'Resource not found for ResourceId $id (${type ?? 'unknown type'})',
      );
    }
    return resource;
  }

  /// Gets the ResourceId for a given resource type.
  ///
  /// Returns null if the type is not registered.
  ResourceId? getResourceId<T extends Resource>() => _typeToId[T];

  /// Gets the Type for a given ResourceId.
  ///
  /// Returns null if the ResourceId is not registered.
  Type? getType(final ResourceId id) => _idToType[id];

  /// Check if a resource of type [T] exists without throwing.
  ///
  /// Returns `false` if the resource doesn't exist or isn't flushed yet.
  /// Auto-flushes to ensure pending resources are available.
  ///
  /// Example:
  /// ```dart
  /// if (world.resources.has<PerformanceResource>()) {
  ///   final perf = world.getResource<PerformanceResource>();
  ///   // Use performance resource
  /// }
  /// ```
  bool has<T extends Resource>() {
    // Auto-flush resources only (more efficient than world.ensureFlushed)
    ensureFlushed();
    final resourceId = _typeToId[T];
    if (resourceId == null) return false;
    if (!resourceId.isValid) return false;
    if (resourceId.value >= _resources.length) return false;
    return _resources[resourceId.value] != null;
  }

  /// Check if a resource exists by runtime [Type].
  ///
  /// Same as [has] but accepts a runtime Type instead of a generic parameter.
  /// Useful for registry-driven snapshot/restore where types are known at
  /// runtime rather than compile time.
  bool hasByType(final Type type) {
    ensureFlushed();
    final resourceId = _typeToId[type];
    if (resourceId == null) return false;
    if (!resourceId.isValid) return false;
    if (resourceId.value >= _resources.length) return false;
    return _resources[resourceId.value] != null;
  }

  /// Gets a resource by runtime [Type].
  ///
  /// Returns null if the type is not registered or the resource is absent.
  /// Same as [get] but accepts a runtime Type instead of a generic parameter.
  Resource? getByType(final Type type) {
    ensureFlushed();
    final resourceId = _typeToId[type];
    if (resourceId == null) return null;
    if (!resourceId.isValid || resourceId.value >= _resources.length) {
      return null;
    }
    return _resources[resourceId.value];
  }

  Iterable<T> iter<T extends Resource>() sync* {
    ensureFlushed();
    for (final resourceIdValue in _presentResourceIds) {
      final resource = _resources[resourceIdValue];
      if (resource is T) {
        yield resource;
      }
    }
  }

  /// Dense iteration over all active resources (skips null holes).
  Iterable<Resource> iterDense() sync* {
    ensureFlushed();
    for (final resourceIdValue in _presentResourceIds) {
      final resource = _resources[resourceIdValue];
      if (resource != null) {
        yield resource;
      }
    }
  }

  void push<T extends Resource>(final T resource) =>
      pendingPush.addLast((T, resource));

  /// Push a resource using a runtime [Type] instead of a generic parameter.
  ///
  /// Used by registry-driven snapshot/restore where the concrete type is
  /// known at runtime rather than compile time.
  void pushByType(final Type type, final Resource resource) =>
      pendingPush.addLast((type, resource));

  /// Registers a resource type and returns its ResourceId for O(1) access.
  ///
  /// This method enables hot-path access via ResourceId instead of Type-based Map lookups.
  /// Returns the existing ResourceId if the type is already registered.
  ///
  /// Prefer to use [world.upsertResource] instead.
  @internal
  ResourceId registerResource<T extends Resource>() {
    if (_typeToId.containsKey(T)) {
      return _typeToId[T]!;
    }

    final id = _allocateResourceId();
    _typeToId[T] = id;
    _idToType[id] = T;

    return id;
  }

  /// Registers a resource type by runtime Type and returns its ResourceId.
  ///
  /// Prefer to use [world.upsertResource] instead.
  @internal
  ResourceId registerResourceByType(final Type type) {
    if (_typeToId.containsKey(type)) {
      return _typeToId[type]!;
    }

    final id = _allocateResourceId();
    _typeToId[type] = id;
    _idToType[id] = type;

    return id;
  }

  void remove<T extends Resource>() => pendingRemove.addLast(T);

  /// Remove resource by runtime type (for use in command execution)
  void removeByType(final Type type) => pendingRemove.addLast(type);

  /// Ensures the dense array has capacity for the given index.
  void _ensureCapacity(final int minCapacity) {
    if (_resources.length < minCapacity) {
      final newCapacity = minCapacity > _resources.length * 2
          ? minCapacity
          : _resources.length * 2;
      _resources.length = newCapacity;
    }
  }

  ResourceId _allocateResourceId() {
    if (_freeIds.isNotEmpty) {
      return ResourceId(_freeIds.removeFirst());
    }
    if (_nextId > ResourceId.maxValue) {
      throw StateError(
        'Maximum resource types exceeded (${ResourceId.maxValue})',
      );
    }
    return ResourceId(_nextId++);
  }

  void _addPresentResourceId(final int resourceIdValue) {
    _ensurePresentDenseIndexCapacity(resourceIdValue + 1);
    if (_presentDenseIndexById[resourceIdValue] != -1) {
      return;
    }
    _presentDenseIndexById[resourceIdValue] = _presentResourceIds.length;
    _presentResourceIds.add(resourceIdValue);
  }

  void _removePresentResourceId(final int resourceIdValue) {
    if (resourceIdValue >= _presentDenseIndexById.length) {
      return;
    }
    final denseIndex = _presentDenseIndexById[resourceIdValue];
    if (denseIndex == -1) {
      return;
    }

    final lastDenseIndex = _presentResourceIds.length - 1;
    final lastResourceIdValue = _presentResourceIds[lastDenseIndex];
    _presentResourceIds[denseIndex] = lastResourceIdValue;
    _presentResourceIds.removeLast();
    _presentDenseIndexById[lastResourceIdValue] = denseIndex;
    _presentDenseIndexById[resourceIdValue] = -1;
  }

  void _ensurePresentDenseIndexCapacity(final int minCapacity) {
    while (_presentDenseIndexById.length < minCapacity) {
      _presentDenseIndexById.add(-1);
    }
  }
}
