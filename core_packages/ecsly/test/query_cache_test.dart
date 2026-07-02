import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('QueryCache', () {
    test('archetype match caching computes once and invalidates on change', () {
      final world = buildTestWorld();
      final posId = world.components.getComponentId<PositionComponent>();

      world.archetypes.getOrCreateArchetype(
        ArchetypeSignature.fromIds([posId]),
      );

      final mask = createComponentMask([posId]);
      final first = world.archetypes.findMatchingArchetypes(mask);
      final second = world.archetypes.findMatchingArchetypes(mask);

      expect(first.length, second.length);
      expect(world.queryCache.stats.archetypeCacheSize, 1);

      world.archetypes.getOrCreateArchetype(
        ArchetypeSignature.fromIds([
          posId,
          world.components.getComponentId<NameComponent>(),
        ]),
      );
      expect(world.queryCache.stats.archetypeCacheSize, 0);
    });

    test('result cache has miss then hit for same key', () {
      final cache = QueryCache();
      final key = QueryCacheKey(emptyComponentMask, 'same');
      var computeCount = 0;

      final e1 = cache.getCachedResult(key, ArchetypeRegistry(), () {
        computeCount++;
        return [Entity.create(1)];
      });
      final e2 = cache.getCachedResult(key, ArchetypeRegistry(), () {
        computeCount++;
        return [Entity.create(2)];
      });

      expect(e1, isNotNull);
      expect(e2, isNotNull);
      expect(computeCount, 1);
      expect(cache.stats.resultCacheHits, 2);
      expect(cache.stats.resultCacheMisses, 1);
    });

    test('result cache evicts on world flush version bump', () {
      final cache = QueryCache();
      final key = QueryCacheKey(emptyComponentMask, 'flush');
      var computeCount = 0;

      cache.getCachedResult(key, ArchetypeRegistry(), () {
        computeCount++;
        return [Entity.create(1)];
      });
      cache.onWorldFlush();
      cache.getCachedResult(key, ArchetypeRegistry(), () {
        computeCount++;
        return [Entity.create(2)];
      });

      expect(computeCount, 2);
      expect(cache.stats.resultCacheInvalidations, greaterThanOrEqualTo(1));
    });

    test('result cache evicts on structural component touch', () {
      final cache = QueryCache();
      const id = ComponentId(7);
      final mask = createComponentMask(const [id]);
      final key = QueryCacheKey(mask, 'mut');
      var computeCount = 0;

      cache.getCachedResult(key, ArchetypeRegistry(), () {
        computeCount++;
        return [Entity.create(1)];
      });

      cache.markStructurallyTouched(id);

      cache.getCachedResult(key, ArchetypeRegistry(), () {
        computeCount++;
        return [Entity.create(2)];
      });

      expect(computeCount, 2);
      expect(cache.stats.resultCacheInvalidations, greaterThanOrEqualTo(1));
    });

    test('QueryResultCache.invalidateAll tracks invalidation count', () {
      final rc = QueryResultCache();
      final key1 = QueryCacheKey(emptyComponentMask, 'k1');
      final key2 = QueryCacheKey(emptyComponentMask, 'k2');

      rc.put(key1, [Entity.create(1)]);
      rc.put(key2, [Entity.create(2)]);
      expect(rc.stats.size, 2);

      rc.invalidateAll();

      expect(rc.stats.size, 0);
      expect(rc.stats.invalidations, 2);
    });
  });
}
