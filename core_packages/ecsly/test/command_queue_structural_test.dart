import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('CommandQueue structural changes', () {
    test('flush throws on stale-entity command and still records failure', () {
      final world = buildTestWorld();
      final dead = world.entities.create();
      world.entities.destroy(dead);

      final live = world.reserveEmptyEntity().entity;
      world.commands.spawnBundle(
        live,
        ComponentBundle.fromLists(const [NameComponent('ok')]),
      );
      world.commands.spawnBundle(
        dead,
        ComponentBundle.fromLists(const [NameComponent('stale')]),
      );

      expect(world.flush, throwsA(isA<EntityNotFoundError>()));

      expect(world.commandQueue.hasFailures, isTrue);
      final failure = world.commandQueue.failures.single;
      expect(failure.commandType, SpawnEntityComponentsCommand);
      expect(failure.error, isA<EntityNotFoundError>());

      expect(world.entities.isAlive(live), isTrue);
      expect(world.getComponent<NameComponent>(live).value, 'ok');
      expect(world.query<NameComponent>(), hasLength(1));
    });

    test(
      'spawnBundle on reserved entity writes archetype/component data on flush',
      () {
        final world = buildTestWorld();
        final entity = world.reserveEmptyEntity().entity;

        world.spawnBundle(
          entity,
          ComponentBundle.fromLists(
            const [NameComponent('alpha')],
            const [(PositionComponent, Position), (HealthComponent, Health)],
          ),
        );

        expect(
          world.entities.getLocation(entity).archetypeId,
          ArchetypeId.zero,
        );

        world.flush();

        final posRow = world.queryExt<PositionComponent, Position>().single;
        final (_, pos) = posRow;
        final hpRow = world.queryExt<HealthComponent, Health>().single;
        final (_, hp) = hpRow;

        expect(pos.x, 0);
        expect(pos.y, 0);
        expect(hp.value, 0);
        expect(world.getComponent<NameComponent>(entity).value, 'alpha');
      },
    );

    test(
      'upsert updates existing and migrates when missing while preserving others',
      () {
        final world = buildTestWorld();
        final entity = world.reserveEmptyEntity().entity;

        world.spawnBundle(
          entity,
          ComponentBundle.fromLists(const [NameComponent('before')]),
        );
        world.flush();

        world.upsertComponent<NameComponent>(
          entity,
          const NameComponent('after'),
        );
        expect(world.getComponent<NameComponent>(entity).value, 'after');

        world.upsertComponent<HealthComponent>(entity, const HealthComponent());
        world.flush();

        expect(world.getComponent<NameComponent>(entity).value, 'after');
        final (_, hp) = world.queryExt<HealthComponent, Health>().single;
        expect(hp.value, 0);
      },
    );

    test(
      'removeComponent migrates and can return entity to empty archetype',
      () {
        final world = buildTestWorld();
        final entity = world.reserveEmptyEntity().entity;

        world.spawnBundle(
          entity,
          ComponentBundle.fromLists(
            const [NameComponent('remove-me')],
            const [(HealthComponent, Health)],
          ),
        );
        world.flush();

        world.removeComponent<HealthComponent>(entity);
        world.flush();
        expect(world.queryExt<HealthComponent, Health>(), isEmpty);
        expect(world.getComponent<NameComponent>(entity).value, 'remove-me');

        world.removeComponent<NameComponent>(entity);
        world.flush();
        final location = world.entities.getLocation(entity);
        expect(location.archetypeId, ArchetypeId.zero);
      },
    );

    test('despawn invalidates entity and removes from storage', () {
      final world = buildTestWorld();
      final entity = world.reserveEmptyEntity().entity;

      world.spawnBundle(
        entity,
        ComponentBundle.fromLists(const [NameComponent('x')]),
      );
      world.flush();
      expect(world.entities.isAlive(entity), isTrue);

      world.despawnEntity(entity);
      world.flush();

      expect(world.entities.isAlive(entity), isFalse);
      expect(world.query<NameComponent>(), isEmpty);
    });

    test('batchDespawn invalidates entities and removes them from storage', () {
      final world = buildTestWorld();
      final entities = <Entity>[];
      for (var i = 0; i < 3; i++) {
        final entity = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          entity,
          ComponentBundle.fromLists([NameComponent('n$i')]),
        );
        entities.add(entity);
      }
      world.flush();

      world.commands.batchDespawn(entities);
      world.flush();

      for (final entity in entities) {
        expect(world.entities.isAlive(entity), isFalse);
      }
      expect(world.query<NameComponent>(), isEmpty);
    });

    test('batchSpawn matches repeated single spawns for same bundle', () {
      final single = buildTestWorld();
      final batch = buildTestWorld();
      final bundle = ComponentBundle.fromLists(const [], const [
        (HealthComponent, Health),
      ]);

      for (var i = 0; i < 3; i++) {
        final e = single.reserveEmptyEntity().entity;
        single.spawnBundle(e, bundle);
      }
      single.flush();

      batch.batchSpawn(bundle, 3);
      batch.flush();

      expect(single.queryExt<HealthComponent, Health>().length, 3);
      expect(batch.queryExt<HealthComponent, Health>().length, 3);
    });

    test('reserveEmptyEntities returns live ids without command wrappers', () {
      final world = buildTestWorld();
      final entities = world.reserveEmptyEntities(3);

      expect(entities, hasLength(3));
      expect(entities.toSet(), hasLength(3));
      for (final entity in entities) {
        expect(world.entities.isAlive(entity), isTrue);
        expect(
          world.entities.getLocation(entity).archetypeId,
          ArchetypeId.zero,
        );
      }

      final bundle = ComponentBundle.fromLists(const [], const [
        (HealthComponent, Health),
      ]);
      for (final entity in entities) {
        world.spawnBundle(entity, bundle);
      }
      world.flush();

      expect(world.queryExt<HealthComponent, Health>().length, 3);
      expect(() => world.reserveEmptyEntities(-1), throwsRangeError);
    });

    test('batchSpawn rejects class component bundles to avoid aliasing', () {
      final world = buildTestWorld();
      final bundle = ComponentBundle.fromLists(const [NameComponent('n')]);

      world.batchSpawn(bundle, 2);
      expect(world.flush, throwsA(isA<StateError>()));
      expect(world.commandQueue.hasFailures, isTrue);
      final failure = world.commandQueue.failures.single;
      expect(failure.commandType, BatchSpawnCommand);
      expect(failure.error, isA<StateError>());
    });

    test('batch add/remove components matches single-entity behavior', () {
      final world = buildTestWorld();
      final e1 = world.reserveEmptyEntity().entity;
      final e2 = world.reserveEmptyEntity().entity;

      world.spawnBundle(
        e1,
        ComponentBundle.fromLists(const [NameComponent('a')]),
      );
      world.spawnBundle(
        e2,
        ComponentBundle.fromLists(const [NameComponent('b')]),
      );
      world.flush();

      world.commands.batchAddExtensionComponents(
        [e1, e2],
        const [(HealthComponent, Health)],
      );
      world.flush();
      expect(world.queryExt<HealthComponent, Health>().length, 2);

      final healthId = world.components.getComponentId<HealthComponent>();
      world.commands.batchRemoveComponents([e1, e2], [healthId]);
      world.flush();

      expect(world.queryExt<HealthComponent, Health>(), isEmpty);
      expect(world.query<NameComponent>().length, 2);
    });

    test('batchAddClassComponents rejects multi-entity class writes', () {
      final world = buildTestWorld();
      final e1 = world.reserveEmptyEntity().entity;
      final e2 = world.reserveEmptyEntity().entity;

      world.commands.batchAddClassComponents(
        [e1, e2],
        const [NameComponent('x')],
      );
      expect(world.flush, throwsA(isA<StateError>()));
      expect(world.commandQueue.hasFailures, isTrue);
      final failure = world.commandQueue.failures.single;
      expect(failure.commandType, BatchAddClassComponentsCommand);
    });
  });
}
