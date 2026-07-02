import '../components/component.dart';
import '../components/component_mask/component_mask.dart';
import '../components/component_registry.dart';
import '../components/query_cache.dart';
import '../errors/ecs_errors.dart';
import 'archetype.dart';
import 'archetype_signature.dart';

/// Registry for managing archetypes.
/// Provides fast lookup by component signature.
class ArchetypeRegistry {
  ArchetypeRegistry({
    final ComponentRegistry? componentRegistry,
    final QueryCache? queryCache,
  }) : _componentRegistry = componentRegistry,
       _queryCache = queryCache,
       _nextArchetypeId = 1 {
    // Reserve index 0 for empty archetype
    _archetypes.add(
      Archetype(
        archetypeId: ArchetypeId.zero,
        signature: ArchetypeSignature.empty,
      ),
    );
    // Initialize mapping for empty archetype
    _ensureArchetypeIdCapacity(ArchetypeId.zero.value + 1);
    _archetypeIdToIndexList[ArchetypeId.zero.value] = ArchetypeIndex.zero;
    _signatureToArchetypeId[ArchetypeSignature.empty] = ArchetypeId.zero;
  }

  final ComponentRegistry? _componentRegistry;
  final QueryCache? _queryCache;

  final List<Archetype> _archetypes = [];

  // Fast lookup: signature → archetype ID
  final Map<ArchetypeSignature, ArchetypeId> _signatureToArchetypeId = {};

  // Fast lookup: archetype ID → archetype index (dense array for O(1) access)
  final List<ArchetypeIndex?> _archetypeIdToIndexList = [];

  int _nextArchetypeId;
  int _structuralVersion = 0;

  /// Get all archetypes (for debugging).
  List<Archetype> get all => List.unmodifiable(_archetypes);

  /// Internal allocation-free archetype iteration for cache recomputation.
  Iterable<Archetype> get iterable => _archetypes;

  /// Get number of archetypes.
  int get count => _archetypes.length;

  /// Monotonic version incremented on structural archetype-set changes.
  int get structuralVersion => _structuralVersion;

  /// Get archetype by index.
  Archetype operator [](final ArchetypeIndex index) {
    if (index.value >= _archetypes.length) {
      throw RangeError('ArchetypeIndex out of range: ${index.value}');
    }
    return _archetypes[index.value];
  }

  void clear() {
    _archetypes.clear();
    _signatureToArchetypeId.clear();
    _archetypeIdToIndexList.clear();
    _nextArchetypeId = 1;

    // Reinitialize empty archetype
    _archetypes.add(
      Archetype(
        archetypeId: ArchetypeId.zero,
        signature: ArchetypeSignature.empty,
      ),
    );
    _signatureToArchetypeId[ArchetypeSignature.empty] = ArchetypeId.zero;
    _ensureArchetypeIdCapacity(ArchetypeId.zero.value + 1);
    _archetypeIdToIndexList[ArchetypeId.zero.value] = ArchetypeIndex.zero;
    _structuralVersion++;
  }

  /// Find archetype by signature.
  ArchetypeId? findArchetype(final ArchetypeSignature signature) =>
      _signatureToArchetypeId[signature];

  /// Find archetype index by ID (O(1) array access).
  ArchetypeIndex findArchetypeIndex(final ArchetypeId id) {
    if (id.value >= _archetypeIdToIndexList.length) {
      throw ArchetypeNotFoundError(id);
    }
    final index = _archetypeIdToIndexList[id.value];
    if (index == null) {
      throw ArchetypeNotFoundError(id);
    }
    return index;
  }

  /// Find all archetypes that match the query mask (bitmask-based).
  /// O(1) via QueryCache.getOrCompute after warmup. Falls back to O(#archetypes) scan on miss.
  List<Archetype> findMatchingArchetypes(final ComponentMask queryMask) {
    if (_queryCache != null) {
      final cached = _queryCache.getOrCompute(queryMask, this);
      return cached.matchingArchetypes;
    }
    return _computeMatchingArchetypes(queryMask);
  }

  /// Get or create archetype for the given signature.
  ArchetypeId getOrCreateArchetype(final ArchetypeSignature signature) =>
      _getOrCreateArchetype(signature, invalidateCache: true);

  /// Pre-register archetypes for efficient batch spawning.
  ///
  /// Checks existing first to minimize getOrCreateArchetype calls and cache invalidations.
  /// Only invalidates query cache once if any new archetypes created.
  /// Call before batch spawning large numbers of entities with known combinations.
  ///
  /// Returns the list of archetype IDs (existing or newly created).
  List<ArchetypeId> preRegisterArchetypes(
    final List<ArchetypeSignature> signatures,
  ) {
    final archetypeIds = <ArchetypeId>[];
    final missingSignatures = <ArchetypeSignature>[];
    for (final signature in signatures) {
      final existingId = _signatureToArchetypeId[signature];
      if (existingId != null) {
        archetypeIds.add(existingId);
      } else {
        missingSignatures.add(signature);
      }
    }
    bool invalidated = false;
    for (final signature in missingSignatures) {
      final archetypeId = _getOrCreateArchetype(
        signature,
        invalidateCache: false,
      );
      archetypeIds.add(archetypeId);
      invalidated = true;
    }
    if (invalidated) {
      _queryCache?.invalidate();
    }
    return archetypeIds;
  }

  List<Archetype> _computeMatchingArchetypes(final ComponentMask queryMask) {
    final matching = <Archetype>[];
    for (final archetype in iterable) {
      if (archetype.matches(queryMask)) {
        matching.add(archetype);
      }
    }
    return matching;
  }

  /// Ensure the archetype ID to index list has capacity for the given ID.
  void _ensureArchetypeIdCapacity(final int minCapacity) {
    while (_archetypeIdToIndexList.length < minCapacity) {
      _archetypeIdToIndexList.add(null);
    }
  }

  /// Extract ComponentIds from ComponentMask.
  /// Optimized to iterate only set bits (O(popcount) instead of O(256)).
  List<ComponentId> _getComponentIdsFromMask(final ComponentMask mask) =>
      mask.componentIds.toList();

  ArchetypeId _getOrCreateArchetype(
    final ArchetypeSignature signature, {
    required final bool invalidateCache,
  }) {
    // Check if archetype already exists
    final existingId = _signatureToArchetypeId[signature];
    if (existingId != null) {
      return existingId;
    }

    // Create new archetype
    final archetypeId = ArchetypeId(_nextArchetypeId++);
    final archetype = Archetype(archetypeId: archetypeId, signature: signature);

    // Create columns for each component in signature using ColumnFactory
    if (_componentRegistry != null) {
      // Extract ComponentIds from signature mask
      final componentIds = _getComponentIdsFromMask(signature.mask);
      for (final componentId in componentIds) {
        final componentType = _componentRegistry.getType(componentId);
        final column = _componentRegistry.createColumnFor(componentType);
        archetype.addColumn(componentId, column);
      }
    }

    _archetypes.add(archetype);
    _signatureToArchetypeId[signature] = archetypeId;

    // Maintain ID → index mapping
    final archetypeIndex = _archetypes.length - 1;
    _ensureArchetypeIdCapacity(archetypeId.value + 1);
    _archetypeIdToIndexList[archetypeId.value] = ArchetypeIndex(archetypeIndex);
    _structuralVersion++;

    if (invalidateCache) {
      _queryCache?.invalidate();
    }

    return archetypeId;
  }
}
