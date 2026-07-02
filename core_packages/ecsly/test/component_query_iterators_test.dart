import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

class ArmorComponent extends Component {
  const ArmorComponent(this.value);
  final int value;
}

class TeamComponent extends Component {
  const TeamComponent(this.value);
  final int value;
}

class ScoreComponent extends Component {
  const ScoreComponent(this.value);
  final int value;
}

void main() {
  group('ComponentQuery iterators and filters', () {
    late World world;

    setUp(() {
      world = buildTestWorld();
      world.components.registerObjectComponent<ArmorComponent>();
      world.components.registerObjectComponent<TeamComponent>();
      world.components.registerObjectComponent<ScoreComponent>();

      final e1 = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e1,
        ComponentBundle.fromLists(
          const [
            NameComponent('a'),
            ArmorComponent(1),
            TeamComponent(10),
            ScoreComponent(100),
          ],
          const [(PositionComponent, Position)],
        ),
      );

      final e2 = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e2,
        ComponentBundle.fromLists(
          const [NameComponent('b'), ArmorComponent(2), TeamComponent(20)],
          const [(PositionComponent, Position), (HealthComponent, Health)],
        ),
      );

      final e3 = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e3,
        ComponentBundle.fromLists(
          const [NameComponent('c')],
          const [(HealthComponent, Health)],
        ),
      );

      world.flush();
    });

    test('iter1/iter2/iter3/iter4 return expected tuples', () {
      final q = ComponentQuery.fromWorld(world);

      expect(q.iter1<NameComponent>().length, 3);
      expect(q.iter2<NameComponent, ArmorComponent>().length, 2);
      expect(q.iter3<NameComponent, ArmorComponent, TeamComponent>().length, 2);
      expect(
        q
            .iter4<
              NameComponent,
              ArmorComponent,
              TeamComponent,
              ScoreComponent
            >()
            .length,
        1,
      );
    });

    test('iter1Where filters without missing matching entities', () {
      final q = ComponentQuery.fromWorld(world);

      final filtered = q
          .iter1Where<NameComponent>((final name) => name.value != 'b')
          .map((final item) => item.$2.value)
          .toList();

      expect(filtered, containsAll(['a', 'c']));
      expect(filtered, isNot(contains('b')));
    });

    test('excludedMask filtering returns only non-excluded archetypes', () {
      final q = ComponentQuery.fromWorld(
        world,
      ).withType<NameComponent>().withoutType<HealthComponent>();

      final names = q.entities
          .map((final e) => world.getComponent<NameComponent>(e).value)
          .toList();
      expect(names, ['a']);
    });

    test('count and any use flushed dense matching archetypes', () {
      final q = ComponentQuery.fromWorld(world).withType<ScoreComponent>();

      expect(q.count(), 1);
      expect(q.any(), isTrue);

      world.spawnComponents([
        const NameComponent('pending'),
        const ScoreComponent(2),
      ]);

      expect(q.count(), 2);
      expect(q.any(), isTrue);
    });

    test('any is false for empty matching archetypes after despawn', () {
      final q = ComponentQuery.fromWorld(world).withType<ScoreComponent>();
      final entity = q.entities.single;

      world.despawnEntity(entity);
      world.flush();

      expect(q.count(), 0);
      expect(q.any(), isFalse);
    });

    test('any and count honor excluded archetypes', () {
      final included = ComponentQuery.fromWorld(
        world,
      ).withType<NameComponent>().withoutType<HealthComponent>();
      final excluded = ComponentQuery.fromWorld(world)
          .withType<NameComponent>()
          .withoutType<HealthComponent>()
          .withoutType<ArmorComponent>();

      expect(included.count(), 1);
      expect(included.any(), isTrue);
      expect(excluded.count(), 0);
      expect(excluded.any(), isFalse);
    });

    test('queryExt and queryExt2 helpers return typed extension facades', () {
      final ext1 = world.queryExt<PositionComponent, Position>().toList();
      expect(ext1, isNotEmpty);

      final first = ext1.first.$2;
      first.x = 42;
      expect(first.x, 42);

      final ext2 = world
          .queryExt2<PositionComponent, Position, HealthComponent, Health>()
          .toList();
      expect(ext2.length, 1);
      final (_, pos, hp) = ext2.single;
      pos.y = 9;
      hp.value = 77;
      expect(pos.y, 9);
      expect(hp.value, 77);
    });
  });
}
