import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

/// Integration tests for live archetype resolution through [WorldEntity.archetype]
/// (backed by [Entities.archetypeIdOf]): migration, wrapper snapshots, and parity
/// with [Entities.getLocation].
void main() {
  group('WorldEntity archetype integration', () {
    late World world;

    setUp(() {
      world = buildTestWorld();
    });

    test(
      'stale WorldEntity.location vs live archetype after insert without re-fetch',
      () {
        final e = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          e,
          ComponentBundle.fromLists(const [NameComponent('live')]),
        );
        world.flush();

        final (we, valid) = world.getEntity(e);
        expect(valid, isTrue);
        final snapshotId = we.location.archetypeId;
        expect(we.archetype.archetypeId, snapshotId);
        expect(
          world.entities.getLocation(e).archetypeId,
          we.archetype.archetypeId,
        );

        we.insert(const HealthComponent());
        world.flush();

        expect(
          we.location.archetypeId,
          snapshotId,
          reason: 'location is a getEntity snapshot and is not refreshed',
        );
        expect(
          we.archetype.archetypeId,
          isNot(snapshotId),
          reason: 'archetype getter reads live storage after migration',
        );
        expect(
          world.entities.getLocation(e).archetypeId,
          we.archetype.archetypeId,
        );
        expect(
          we.archetype.signature.has(
            world.components.getComponentId<HealthComponent>(),
          ),
          isTrue,
        );

        we.remove<HealthComponent>();
        world.flush();
        expect(we.hasFast<HealthComponent>(), isFalse);
        expect(
          world.entities.getLocation(e).archetypeId,
          we.archetype.archetypeId,
        );
      },
    );

    test('batchAddExtensionComponents migration while holding WorldEntity', () {
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(const [NameComponent('batch')]),
      );
      world.flush();

      final (we, valid) = world.getEntity(e);
      expect(valid, isTrue);
      final before = we.location.archetypeId;

      world.commands.batchAddExtensionComponents(
        [e],
        const [(HealthComponent, Health)],
      );
      world.flush();

      expect(we.location.archetypeId, before);
      expect(
        we.archetype.signature.has(
          world.components.getComponentId<HealthComponent>(),
        ),
        isTrue,
      );
      expect(
        world.entities.getLocation(e).archetypeId,
        we.archetype.archetypeId,
      );
    });

    test('repeated archetype getter stays consistent without migration', () {
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(const [NameComponent('hot')]),
      );
      world.flush();

      final (we, _) = world.getEntity(e);
      final id = we.archetype.archetypeId;
      for (var i = 0; i < 200; i++) {
        expect(we.archetype.archetypeId, id);
      }
    });

    test('WorldEntity, Extension, and Mut expose same live archetype id', () {
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(const [NameComponent('triple')]),
      );
      world.flush();

      final (we, valid) = world.getEntity(e);
      expect(valid, isTrue);
      final ext = we.toExtension();
      final mut = we.toMut();

      final id = we.archetype.archetypeId;
      expect(ext.archetype.archetypeId, id);
      expect(mut.archetype.archetypeId, id);
    });

    test(
      'multi-step migration keeps live archetype aligned with getLocation',
      () {
        final e = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          e,
          ComponentBundle.fromLists(const [NameComponent('steps')]),
        );
        world.flush();

        final (we, _) = world.getEntity(e);

        we.insert(const HealthComponent());
        world.flush();
        expect(
          world.entities.getLocation(e).archetypeId,
          we.archetype.archetypeId,
        );

        we.insert(const PositionComponent());
        world.flush();
        expect(
          world.entities.getLocation(e).archetypeId,
          we.archetype.archetypeId,
        );
        expect(
          we.archetype.signature.has(
            world.components.getComponentId<PositionComponent>(),
          ),
          isTrue,
        );

        we.remove<PositionComponent>();
        world.flush();
        expect(
          world.entities.getLocation(e).archetypeId,
          we.archetype.archetypeId,
        );
      },
    );

    test('getEntity ensures flush so archetype matches pending insert', () {
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(const [NameComponent('flush')]),
      );
      world.flush();

      final (we, _) = world.getEntity(e);
      we.insert(const HealthComponent());
      expect(world.commandQueue.needsFlush, isTrue);

      final (we2, valid2) = world.getEntity(e);
      expect(valid2, isTrue);
      expect(world.commandQueue.needsFlush, isFalse);
      expect(
        we2.archetype.signature.has(
          world.components.getComponentId<HealthComponent>(),
        ),
        isTrue,
      );
      expect(
        world.entities.getLocation(e).archetypeId,
        we2.archetype.archetypeId,
      );

      // Original wrapper: location snapshot still pre-insert for we if we only
      // compare archetype — actually after getEntity on we2, we still holds old
      // snapshot; insert was flushed by getEntity on we2, so we.archetype live.
      expect(
        we.archetype.signature.has(
          world.components.getComponentId<HealthComponent>(),
        ),
        isTrue,
      );
    });
  });
}
