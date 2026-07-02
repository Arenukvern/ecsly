import 'package:ecsly/src/archetypes/archetype.dart';
import 'package:ecsly/src/archetypes/archetype_signature.dart';
import 'package:ecsly/src/archetypes/archetypes_registry.dart';
import 'package:ecsly/src/components/component_mask/component_mask.dart';
import 'package:ecsly/src/components/query_cache.dart';
import 'package:ecsly/src/errors/ecs_errors.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('ArchetypeRegistry', () {
    test('getOrCreateArchetype is stable and creates columns via registry', () {
      final components = buildTestWorld().components;

      final registry = ArchetypeRegistry(componentRegistry: components);
      final posId = components.getComponentId<PositionComponent>();
      final hpId = components.getComponentId<HealthComponent>();
      final signature = ArchetypeSignature.fromIds([posId, hpId]);

      final a1 = registry.getOrCreateArchetype(signature);
      final a2 = registry.getOrCreateArchetype(signature);
      expect(a2, a1);

      final index = registry.findArchetypeIndex(a1);
      final archetype = registry[index];
      expect(archetype.getColumn(posId), isNotNull);
      expect(archetype.getColumn(hpId), isNotNull);
    });

    test('findArchetypeIndex throws for unknown ID', () {
      final registry = ArchetypeRegistry();
      expect(
        () => registry.findArchetypeIndex(const ArchetypeId(999)),
        throwsA(isA<ArchetypeNotFoundError>()),
      );
    });

    test('findMatchingArchetypes works with and without query cache', () {
      final components = buildTestWorld().components;

      final posId = components.getComponentId<PositionComponent>();
      final nameId = components.getComponentId<NameComponent>();

      final noCache = ArchetypeRegistry(componentRegistry: components);
      noCache.getOrCreateArchetype(ArchetypeSignature.fromIds([posId]));
      noCache.getOrCreateArchetype(ArchetypeSignature.fromIds([posId, nameId]));

      final withCache = ArchetypeRegistry(
        componentRegistry: components,
        queryCache: QueryCache(),
      );
      withCache.getOrCreateArchetype(ArchetypeSignature.fromIds([posId]));
      withCache.getOrCreateArchetype(
        ArchetypeSignature.fromIds([posId, nameId]),
      );

      final mask = createComponentMask([posId]);
      expect(noCache.findMatchingArchetypes(mask).length, 2);
      expect(withCache.findMatchingArchetypes(mask).length, 2);
      expect(withCache.findMatchingArchetypes(mask).length, 2);
    });

    test(
      'preRegisterArchetypes creates missing archetypes and reuses existing',
      () {
        final components = buildTestWorld().components;
        final registry = ArchetypeRegistry(
          componentRegistry: components,
          queryCache: QueryCache(),
        );

        final posId = components.getComponentId<PositionComponent>();
        final nameId = components.getComponentId<NameComponent>();
        final sig1 = ArchetypeSignature.fromIds([posId]);
        final sig2 = ArchetypeSignature.fromIds([nameId]);

        final existing = registry.getOrCreateArchetype(sig1);
        final ids = registry.preRegisterArchetypes([sig1, sig2]);

        expect(ids.length, 2);
        expect(ids, contains(existing));
        expect(registry.findArchetype(sig2), isNotNull);
      },
    );
  });
}
