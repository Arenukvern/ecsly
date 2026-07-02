import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

class MutableA extends Component {
  MutableA(this.value);
  int value;
}

class MutableB extends Component {
  MutableB(this.value);
  int value;
}

class MutableC extends Component {
  MutableC(this.value);
  int value;
}

void main() {
  group('WorldEntity wrappers', () {
    late World world;

    setUp(() {
      world = buildTestWorld();
      world.components.registerObjectComponent<MutableA>();
      world.components.registerObjectComponent<MutableB>();
      world.components.registerObjectComponent<MutableC>();
    });

    test(
      'WorldEntity supports get/has/insert/remove/despawn and cache refresh',
      () {
        final e = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          e,
          ComponentBundle.fromLists(const [NameComponent('a')]),
        );
        world.flush();

        final (we, valid) = world.getEntity(e);
        expect(valid, isTrue);
        expect(we.isValid, isTrue);
        expect(we.has<NameComponent>(), isTrue);
        expect(we.hasFast<NameComponent>(), isTrue);
        expect(we.get<NameComponent>()?.value, 'a');
        expect(we.archetype.archetypeId, isNot(ArchetypeId.zero));

        we.insert(const HealthComponent());
        world.flush();
        expect(
          we.archetype.signature.has(
            world.components.getComponentId<HealthComponent>(),
          ),
          isTrue,
        );

        we.remove<HealthComponent>();
        world.flush();
        expect(we.hasFast<HealthComponent>(), isFalse);

        we.despawn();
        world.flush();
        expect(world.entities.isAlive(e), isFalse);
        expect(we.isValid, isFalse);
      },
    );

    test('WorldEntityExtension get/create/getOrCreate and mismatch paths', () {
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(const [NameComponent('ext')]),
      );
      world.flush();

      final ext = world.getEntityExtension(e).$1;
      expect(ext.getExtension<HealthComponent, Health>(), isNull);

      final created = ext.create<HealthComponent, Health>();
      expect(created.value, 0);

      created.value = 15;
      final existing = ext.getOrCreate<HealthComponent, Health>();
      expect(existing.value, 15);

      // Class components have no registered extension facade by default.
      world.upsertComponent<MutableA>(e, MutableA(3));
      world.flush();
      expect(
        () => ext.getExtension<MutableA, MutableA>(),
        throwsA(isA<ExtensionTypeNotRegisteredError>()),
      );
    });

    test('WorldEntityMut getMut/getMut2/getMut3 and hasFast behavior', () {
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists([MutableA(1), MutableB(2), MutableC(3)]),
      );
      world.flush();

      final (mut, valid) = world.getEntityMut(e);
      expect(valid, isTrue);
      expect(mut.isAlive, isTrue);

      final a = mut.getMut<MutableA>();
      a.value = 10;
      expect(mut.getMut<MutableA>().value, 10);

      final (b1, c1) = mut.getMut2<MutableB, MutableC>();
      b1.value = 20;
      c1.value = 30;

      final (a2, b2, c2) = mut.getMut3<MutableA, MutableB, MutableC>();
      expect(a2.value, 10);
      expect(b2.value, 20);
      expect(c2.value, 30);

      expect(mut.has<MutableA>(), isTrue);
      expect(mut.hasFast<MutableA>(), isTrue);
      expect(mut.hasFast<HealthComponent>(), isFalse);

      expect(
        () => mut.getMut<HealthComponent>(),
        throwsA(isA<ComponentNotFoundError>()),
      );
    });
  });
}
