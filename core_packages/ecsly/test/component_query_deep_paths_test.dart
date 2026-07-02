import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

class D1 extends Component {
  const D1(this.v);
  final int v;
}

class D2 extends Component {
  const D2(this.v);
  final int v;
}

class D3 extends Component {
  const D3(this.v);
  final int v;
}

class D4 extends Component {
  const D4(this.v);
  final int v;
}

class D5 extends Component {
  const D5(this.v);
  final int v;
}

class D6 extends Component {
  const D6(this.v);
  final int v;
}

void main() {
  group('ComponentQuery deep paths', () {
    late World world;

    setUp(() {
      world = buildTestWorld();
      world.components.registerObjectComponent<D1>();
      world.components.registerObjectComponent<D2>();
      world.components.registerObjectComponent<D3>();
      world.components.registerObjectComponent<D4>();
      world.components.registerObjectComponent<D5>();
      world.components.registerObjectComponent<D6>();

      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(
          [
            const NameComponent('deep'),
            const D1(1),
            const D2(2),
            const D3(3),
            const D4(4),
            const D5(5),
            const D6(6),
          ],
          const [(PositionComponent, Position), (HealthComponent, Health)],
        ),
      );
      world.flush();
    });

    test('iter5 and iter6 return tuples for matching archetypes', () {
      final q = ComponentQuery.fromWorld(world);
      expect(q.iter5<D1, D2, D3, D4, D5>().length, 1);
      expect(q.iter6<D1, D2, D3, D4, D5, D6>().length, 1);
    });

    test('iterExt3 and iterExt4 return typed tuples', () {
      final q = ComponentQuery.fromWorld(world);

      final ext3 = q
          .iterExt3<
            PositionComponent,
            Position,
            HealthComponent,
            Health,
            NameComponent,
            NameComponent
          >()
          .toList();
      expect(ext3.length, 1);

      final ext4 = q
          .iterExt4<
            PositionComponent,
            Position,
            HealthComponent,
            Health,
            NameComponent,
            NameComponent,
            D1,
            D1
          >()
          .toList();
      expect(ext4.length, 1);
    });

    test(
      'iterator current throws before moveNext across iterator families',
      () {
        final q = ComponentQuery.fromWorld(world);

        expect(
          () => q.iter1<D1>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iter2<D1, D2>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iter3<D1, D2, D3>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iter4<D1, D2, D3, D4>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iter5<D1, D2, D3, D4, D5>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iter6<D1, D2, D3, D4, D5, D6>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );

        expect(
          () => q.iterExt1<PositionComponent, Position>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q
              .iterExt2<PositionComponent, Position, HealthComponent, Health>()
              .iterator
              .current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q
              .iterExt3<
                PositionComponent,
                Position,
                HealthComponent,
                Health,
                NameComponent,
                NameComponent
              >()
              .iterator
              .current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q
              .iterExt4<
                PositionComponent,
                Position,
                HealthComponent,
                Health,
                NameComponent,
                NameComponent,
                D1,
                D1
              >()
              .iterator
              .current,
          throwsA(isA<IteratorNotReadyError>()),
        );

        expect(
          () => q.iterMut1<D1>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iterMut2<D1, D2>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iterMut3<D1, D2, D3>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
        expect(
          () => q.iterMut4<D1, D2, D3, D4>().iterator.current,
          throwsA(isA<IteratorNotReadyError>()),
        );
      },
    );

    test(
      'iterExt3/iterExt4 validate mismatches and missing extension types',
      () {
        final q = ComponentQuery.fromWorld(world);

        expect(
          () => q
              .iterExt3<
                PositionComponent,
                String,
                HealthComponent,
                Health,
                D1,
                D1
              >()
              .toList(),
          throwsA(isA<ExtensionTypeMismatchError>()),
        );

        expect(
          () => q
              .iterExt4<
                PositionComponent,
                Position,
                HealthComponent,
                Health,
                D1,
                D1,
                NameComponent,
                String
              >()
              .toList(),
          throwsA(
            anyOf(
              isA<ExtensionTypeNotRegisteredError>(),
              isA<ExtensionTypeMismatchError>(),
            ),
          ),
        );
      },
    );

    test('RequiredQuery and ExcludedQuery match signature masks', () {
      final d1Id = world.components.getComponentId<D1>();
      final hpId = world.components.getComponentId<HealthComponent>();
      final sig = ArchetypeSignature.fromIds([d1Id, hpId]);

      final req = RequiredQuery([d1Id]);
      final ex = ExcludedQuery([hpId]);
      expect(req.matches(sig), isTrue);
      expect(ex.matches(sig), isFalse);
    });
  });
}
