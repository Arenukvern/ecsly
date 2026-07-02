import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

class C1 extends Component {
  C1(this.value);
  int value;
}

class C2 extends Component {
  C2(this.value);
  int value;
}

class C3 extends Component {
  C3(this.value);
  int value;
}

class C4 extends Component {
  C4(this.value);
  int value;
}

class C5 extends Component {
  C5(this.value);
  int value;
}

class C6 extends Component {
  C6(this.value);
  int value;
}

class CAbsent extends Component {}

class LookupResource extends Resource {
  LookupResource(this.value);

  final int value;
}

void main() {
  group('World query extensions', () {
    late World world;

    setUp(() {
      world = buildTestWorld();
      world.components.registerObjectComponent<C1>();
      world.components.registerObjectComponent<C2>();
      world.components.registerObjectComponent<C3>();
      world.components.registerObjectComponent<C4>();
      world.components.registerObjectComponent<C5>();
      world.components.registerObjectComponent<C6>();
      world.components.registerObjectComponent<CAbsent>();

      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(
          [C1(1), C2(2), C3(3), C4(4), C5(5), C6(6), const NameComponent('q')],
          const [(PositionComponent, Position), (HealthComponent, Health)],
        ),
      );
      world.flush();
    });

    test('query/query2/query3/query4/query5/query6 return rows', () {
      expect(world.query<C1>().length, 1);
      expect(world.query2<C1, C2>().length, 1);
      expect(world.query3<C1, C2, C3>().length, 1);
      expect(world.query4<C1, C2, C3, C4>().length, 1);
      expect(world.query5<C1, C2, C3, C4, C5>().length, 1);
      expect(world.query6<C1, C2, C3, C4, C5, C6>().length, 1);
    });

    test('prepared queries can be reused after later flushes', () {
      final prepared = world.prepareQuery2<C1, C2>();
      expect(prepared.iter2<C1, C2>().length, 1);

      world.spawnComponents([C1(7), C2(8)]);
      world.flush();

      final rows = prepared.iter2<C1, C2>().toList();
      expect(rows.length, 2);
      expect(rows.map((final row) => row.$2.value), containsAll(<int>[1, 7]));
    });

    test('spawnComponents creates one entity from a component bundle', () {
      final entity = world.spawnComponents([C1(41), C2(42)]);
      world.flush();

      expect(world.entities.isAlive(entity), isTrue);
      expect(world.getComponent<C1>(entity).value, 41);
      expect(world.getComponent<C2>(entity).value, 42);
    });

    test('component lookup resolves by entity', () {
      final entity = world.spawnComponents([C1(99), C2(100)]);
      final other = world.spawnComponents([C1(5), C2(6)]);
      world.flush();

      final byEntity = world.maybeGetComponent<C1>(entity);
      expect(byEntity?.value, 99);

      final absentOnOther = world.maybeGetComponent<CAbsent>(other);
      expect(absentOnOther, isNull);
    });

    test('maybeGetResource returns null for missing resources', () {
      expect(world.maybeGetResource<LookupResource>(), isNull);

      world.upsertResource(LookupResource(7));

      expect(world.maybeGetResource<LookupResource>()?.value, 7);
    });

    test('queryExtWhere/queryExt2Where filter typed extension rows', () {
      final ext1 = world
          .queryExtWhere<PositionComponent, Position>((final p) => p.x == 0)
          .toList();
      expect(ext1.length, 1);

      final ext2 = world
          .queryExt2Where<PositionComponent, Position, HealthComponent, Health>(
            (final p) => p.y == 0,
          )
          .toList();
      expect(ext2.length, 1);
    });

    test('queryRawExt2 returns entity ids with typed facades', () {
      final rows = world
          .queryRawExt2<PositionComponent, Position, HealthComponent, Health>()
          .toList();
      expect(rows.length, 1);

      final (entity, pos, hp) = rows.single;
      expect(world.entities.isAlive(entity), isTrue);
      expect(pos.x, 0);
      expect(hp.value, 0);
    });

    test('queryRaw2 supports typed-column hot-path components', () {
      final raw = world
          .queryRaw2<PositionComponent, Position, HealthComponent, Health>()
          .single;
      expect(raw.rowCount, 1);

      raw.forEachRow((final row, final entity, final pos, final hp) {
        expect(row, 0);
        expect(world.entities.isAlive(entity), isTrue);
        pos.x = 12;
        pos.y = -3;
        hp.value = 9;
      });

      final (_, pos, hp) = world
          .queryExt2<PositionComponent, Position, HealthComponent, Health>()
          .single;
      expect(pos.x, 12);
      expect(pos.y, -3);
      expect(hp.value, 9);
    });

    test('queryRaw2/queryRaw3/queryRaw4 expose chunked hot-path views', () {
      final raw2 = world.queryRaw2<C1, C1, C2, C2>().single;
      expect(raw2.rowCount, 1);
      raw2.forEachRow((final row, final entity, final c1, final c2) {
        expect(row, 0);
        expect(world.entities.isAlive(entity), isTrue);
        c1.value = 21;
        c2.value = 22;
      });

      final raw3 = world.queryRaw3<C1, C1, C2, C2, C3, C3>().single;
      expect(raw3.rowCount, 1);
      raw3.forEachRow((final _, final _, final c1, final c2, final c3) {
        c1.value = 31;
        c2.value = 32;
        c3.value = 33;
      });

      final raw4 = world.queryRaw4<C1, C1, C2, C2, C3, C3, C4, C4>().single;
      expect(raw4.rowCount, 1);
      raw4.forEachRow((
        final _,
        final _,
        final c1,
        final c2,
        final c3,
        final c4,
      ) {
        c1.value = 41;
        c2.value = 42;
        c3.value = 43;
        c4.value = 44;
      });

      expect(world.query<C1>().single.$2.value, 41);
      expect(world.query<C2>().single.$2.value, 42);
      expect(world.query<C3>().single.$2.value, 43);
      expect(world.query<C4>().single.$2.value, 44);
    });

    test('queryCount/queryAny avoid entity materialization', () {
      expect(world.queryCount<C1>(), 1);
      expect(world.queryCount2<C1, C2>(), 1);
      expect(world.queryCount3<C1, C2, C3>(), 1);
      expect(world.queryCount4<C1, C2, C3, C4>(), 1);

      expect(world.queryAny<C1>(), isTrue);
      expect(world.queryAny2<C1, C2>(), isTrue);
      expect(world.queryAny3<C1, C2, C3>(), isTrue);
      expect(world.queryAny4<C1, C2, C3, C4>(), isTrue);
      expect(world.queryAny2<C1, CAbsent>(), isFalse);
    });

    test('queryMut/queryMut2/queryMut3/queryMut4 mutate in place', () {
      final queryRevision = world.queryRevision;
      final (_, c1) = world.queryMut<C1>().single;
      c1.value = 10;

      final (_, c1b, c2b) = world.queryMut2<C1, C2>().single;
      c1b.value = 11;
      c2b.value = 12;

      final (_, c1c, c2c, c3c) = world.queryMut3<C1, C2, C3>().single;
      c1c.value = 13;
      c2c.value = 14;
      c3c.value = 15;

      final (_, c1d, c2d, c3d, c4d) = world.queryMut4<C1, C2, C3, C4>().single;
      c1d.value = 16;
      c2d.value = 17;
      c3d.value = 18;
      c4d.value = 19;

      expect(world.query<C1>().single.$2.value, 16);
      expect(world.query<C2>().single.$2.value, 17);
      expect(world.query<C3>().single.$2.value, 18);
      expect(world.query<C4>().single.$2.value, 19);
      expect(world.queryRevision, queryRevision);
    });

    test('queryBuilder supports required and excluded component IDs', () {
      final idC1 = world.components.getComponentId<C1>();
      final idHealth = world.components.getComponentId<HealthComponent>();

      final q = world
          .toQueryBuilder()
          .withComponent(idC1)
          .withoutComponent(idHealth)
          .build();

      expect(q.entities, isEmpty);
    });

    test('hot schedule guard rejects object components when enabled', () {
      world.enforceSoAForHotSchedules = true;
      final schedule = Schedule('hot-guard')
        ..hotPath()
        ..add((final w) {
          // C1 is ObjectColumn-backed and should be rejected in hot mode.
          w.query<C1>().length;
        });

      expect(
        () => schedule.run(world),
        throwsA(isA<HotScheduleObjectComponentError>()),
      );
    });
  });
}
