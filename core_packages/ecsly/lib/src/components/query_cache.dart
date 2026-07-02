import 'package:meta/meta.dart';

import '../archetypes/archetypes.dart';
import '../entities/entity.dart';
import 'component.dart';
import 'component_mask/component_mask.dart';

/// Result of archetype matching with cached entity list.
class ArchetypeMatchResult {
  ArchetypeMatchResult._(this.matchingArchetypes);
  factory ArchetypeMatchResult._compute(
    final ComponentMask mask,
    final ArchetypeRegistry archetypes,
  ) {
    final matching = <Archetype>[];

    for (final archetype in archetypes.iterable) {
      if (archetype.matches(mask)) {
        matching.add(archetype);
      }
    }

    return ArchetypeMatchResult._(matching);
  }

  /// Archetypes that match the query
  final List<Archetype> matchingArchetypes;
}

/// Structural component-touch tracker for query-result cache entries.
class QueryStructuralTouchTracker {
  final Set<ComponentId> _touchedComponents = {};

  /// Component IDs touched by structural writes since the last flush.
  Set<ComponentId> get touchedComponents =>
      Set.unmodifiable(_touchedComponents);

  /// Clear all structural touch state.
  void clear() {
    _touchedComponents.clear();
  }

  /// Mark a component type as touched by a structural write.
  void markTouched(final ComponentId componentId) {
    _touchedComponents.add(componentId);
  }

  /// Check if any component in the mask was structurally touched.
  bool maskWasTouched(final ComponentMask mask) {
    for (final componentId in mask.componentIds) {
      if (_touchedComponents.contains(componentId)) {
        return true;
      }
    }
    return false;
  }

  /// Check if a component type was structurally touched.
  bool wasTouched(final ComponentId componentId) =>
      _touchedComponents.contains(componentId);
}

/// Enhanced QueryCache that integrates result caching.
class QueryCache {
  QueryCache({
    this.enableResultCaching = true,
    this.maxCacheSize = 1000,
    this.enableStructuralTouchTracking = true,
  });

  /// Whether to enable result caching
  final bool enableResultCaching;

  /// Maximum cache size for result caching
  final int maxCacheSize;

  /// Whether structural component touches evict matching query-result entries.
  final bool enableStructuralTouchTracking;

  /// Original archetype matching cache
  final Map<ComponentMask, ArchetypeMatchResult> _archetypeCache = {};

  /// Query result cache
  late final QueryResultCache _resultCache = enableResultCaching
      ? QueryResultCache(
          maxSize: maxCacheSize,
          enableStructuralTouchTracking: enableStructuralTouchTracking,
        )
      : throw UnsupportedError('Result caching disabled');

  /// Debug-only set of structurally touched component IDs since last flush.
  Set<ComponentId> get debugStructurallyTouchedComponents => enableResultCaching
      ? _resultCache.debugStructurallyTouchedComponents
      : const {};

  /// Debug-only view of the underlying result cache (if enabled).
  Map<QueryCacheKey, QueryCacheEntry> get debugResultCache =>
      enableResultCaching ? _resultCache.debugCache : const {};

  /// Get combined statistics
  ({
    int archetypeCacheSize,
    int resultCacheSize,
    int resultCacheHits,
    int resultCacheMisses,
    int resultCacheInvalidations,
    double resultCacheHitRate,
  })
  get stats {
    final resultStats = enableResultCaching ? _resultCache.stats : null;
    return (
      archetypeCacheSize: _archetypeCache.length,
      resultCacheSize: resultStats?.size ?? 0,
      resultCacheHits: resultStats?.hits ?? 0,
      resultCacheMisses: resultStats?.misses ?? 0,
      resultCacheInvalidations: resultStats?.invalidations ?? 0,
      resultCacheHitRate: resultStats?.hitRate ?? 0.0,
    );
  }

  /// Clear all caches and reset statistics
  void clear() {
    _archetypeCache.clear();
    if (enableResultCaching) {
      _resultCache.clear();
    }
  }

  /// Get cached query result or compute and cache it
  QueryCacheEntry? getCachedResult(
    final QueryCacheKey key,
    final ArchetypeRegistry archetypes,
    final List<Entity> Function() computeResult,
  ) {
    if (!enableResultCaching) {
      return null;
    }

    // Try to get from cache first
    final entry = _resultCache.get(key);
    if (entry != null) {
      return entry;
    }

    // Compute result
    final entities = computeResult();

    // Cache the result
    _resultCache.put(key, entities);

    // Return newly cached entry
    return _resultCache.get(key);
  }

  /// Get or compute archetype matches for a component mask.
  ArchetypeMatchResult getOrCompute(
    final ComponentMask mask,
    final ArchetypeRegistry archetypes,
  ) {
    var result = _archetypeCache[mask];
    if (result != null) {
      return result;
    }

    result = ArchetypeMatchResult._compute(mask, archetypes);
    _archetypeCache[mask] = result;
    return result;
  }

  /// Evict all caches.
  void invalidate() {
    _archetypeCache.clear();
    if (enableResultCaching) {
      _resultCache.invalidateAll();
    }
  }

  /// Evict cached results for queries shaped by a structurally touched type.
  ///
  /// Used by [CommandQueue] when structural writes affect query membership.
  void evictForStructuralComponent(final ComponentId componentId) {
    markStructurallyTouched(componentId);
  }

  /// Mark query-result entries for structural eviction by component mask.
  void markStructurallyTouched(final ComponentId componentId) {
    if (enableResultCaching) {
      _resultCache.markStructurallyTouched(componentId);
    }
  }

  /// Called when archetype registry changes
  void onArchetypeChange() {
    _archetypeCache.clear(); // Archetype matching cache becomes invalid
    if (enableResultCaching) {
      _resultCache.onArchetypeChange();
    }
  }

  /// Called when world is flushed
  void onWorldFlush() {
    if (enableResultCaching) {
      _resultCache.onWorldFlush();
    }
  }
}

/// Cached query result with version tracking for structural eviction.
class QueryCacheEntry {
  QueryCacheEntry(this.entities, this.flushVersion, this.archetypeVersion);

  /// The cached list of matching entities
  final List<Entity> entities;

  /// World flush version when this entry was cached
  final int flushVersion;

  /// Archetype registry version when this entry was cached
  final int archetypeVersion;

  /// Check if this entry is still valid
  bool isValid(
    final int currentFlushVersion,
    final int currentArchetypeVersion,
  ) =>
      flushVersion == currentFlushVersion &&
      archetypeVersion == currentArchetypeVersion;

  @override
  String toString() =>
      'QueryCacheEntry(entities: ${entities.length}, flush: $flushVersion, archetype: $archetypeVersion)';
}

/// Cache key for query results.
/// Combines component mask and optional predicate for unique identification.
@immutable
class QueryCacheKey {
  const QueryCacheKey(this.mask, [this.predicate]);

  final ComponentMask mask;
  final Object? predicate;

  @override
  int get hashCode => Object.hash(mask, predicate);

  @override
  bool operator ==(final Object other) {
    if (identical(this, other)) return true;
    return other is QueryCacheKey &&
        mask == other.mask &&
        predicate == other.predicate;
  }

  @override
  String toString() => 'QueryCacheKey(mask: $mask, predicate: $predicate)';
}

/// Query result cache with structural component-touch eviction.
/// Caches query results to avoid recomputation across systems.
class QueryResultCache {
  QueryResultCache({
    this.maxSize = 1000,
    this.enableStructuralTouchTracking = true,
  });

  /// Maximum number of cached entries
  final int maxSize;

  /// Whether structural component touches evict matching query-result entries.
  final bool enableStructuralTouchTracking;

  final Map<QueryCacheKey, QueryCacheEntry> _cache = {};
  final QueryStructuralTouchTracker _structuralTouches =
      QueryStructuralTouchTracker();

  /// Current world flush version
  int _flushVersion = 0;

  /// Current archetype registry version
  int _archetypeVersion = 0;

  /// Statistics for monitoring
  int _hits = 0;
  int _misses = 0;
  int _invalidations = 0;

  /// Get cache contents (for debugging)
  Map<QueryCacheKey, QueryCacheEntry> get debugCache =>
      Map.unmodifiable(_cache);

  /// Get structural component-touch info (for debugging).
  Set<ComponentId> get debugStructurallyTouchedComponents =>
      _structuralTouches.touchedComponents;

  /// Get cache statistics
  ({int size, int hits, int misses, int invalidations, double hitRate})
  get stats {
    final total = _hits + _misses;
    final hitRate = total > 0 ? _hits / total : 0.0;
    return (
      size: _cache.length,
      hits: _hits,
      misses: _misses,
      invalidations: _invalidations,
      hitRate: hitRate,
    );
  }

  /// Clear all caches and reset statistics
  void clear() {
    _cache.clear();
    _structuralTouches.clear();
    _hits = 0;
    _misses = 0;
    _invalidations = 0;
  }

  /// Get cached query result or null if not cached or stale
  QueryCacheEntry? get(final QueryCacheKey key) {
    final entry = _cache[key];
    if (entry == null) {
      _misses++;
      return null;
    }

    if (!entry.isValid(_flushVersion, _archetypeVersion)) {
      _cache.remove(key);
      _invalidations++;
      _misses++;
      return null;
    }

    // Check for structural writes touching components in this query mask.
    if (enableStructuralTouchTracking &&
        _structuralTouches.maskWasTouched(key.mask)) {
      _cache.remove(key);
      _invalidations++;
      _misses++;
      return null;
    }

    _hits++;
    return entry;
  }

  /// Evict all cached entries.
  void invalidateAll() {
    final cleared = _cache.length;
    _cache.clear();
    _invalidations += cleared;
  }

  /// Mark a component as structurally touched.
  void markStructurallyTouched(final ComponentId componentId) {
    if (enableStructuralTouchTracking) {
      _structuralTouches.markTouched(componentId);
    } else {
      // If not tracking structural touches, evict all cached results.
      invalidateAll();
    }
  }

  /// Called when archetype registry changes - increment version
  void onArchetypeChange() {
    _archetypeVersion++;
    // Archetype changes evict all cached results.
    _cache.clear();
  }

  /// Called when world is flushed - increment version and clear touches.
  void onWorldFlush() {
    _flushVersion++;
    _structuralTouches.clear();
  }

  /// Store query result in cache
  void put(final QueryCacheKey key, final List<Entity> entities) {
    // Implement LRU eviction if over size limit
    if (_cache.length >= maxSize) {
      // Simple eviction: remove oldest entry
      // In production, use proper LRU with access tracking
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    final entry = QueryCacheEntry(
      List.unmodifiable(entities), // Make immutable copy
      _flushVersion,
      _archetypeVersion,
    );

    _cache[key] = entry;
  }
}
