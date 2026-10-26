import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';
import 'component_query_deep_paths_test.dart' show D1, D2, D3, D4, D5, D6;

class SplitMarker extends Component {}

World fixture() {
  final w = buildTestWorld();
  w.components.registerObjectComponent<D1>();
  w.components.registerObjectComponent<D2>();
  w.components.registerObjectComponent<D3>();
  w.components.registerObjectComponent<D4>();
  w.components.registerObjectComponent<D5>();
  w.components.registerObjectComponent<D6>();
  w.components.registerObjectComponent<SplitMarker>();
  for (var i = 0; i < 4; i++) {
    w.spawnComponents([
      NameComponent('row$i'),
      D1(i),
      D2(i),
      D3(i),
      D4(i),
      D5(i),
      D6(i),
      if (i == 3) SplitMarker(),
    ]);
  }
  w.flush();
  return w;
}

World typedFixture(final double offset) {
  final w = fixture();
  for (final row in w.query<NameComponent>().toList()) {
    row.$1.insert(const PositionComponent());
    row.$1.insert(const HealthComponent());
  }
  w.flush();
  var i = 0;
  for (final row in w.queryExt<PositionComponent, Position>()) {
    row.$2.x = offset + i++;
  }
  return w;
}

void main() {
  test('nested query preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.query<NameComponent>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested query2 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.query2<NameComponent, D1>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested query3 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.query3<NameComponent, D1, D2>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested query4 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.query4<NameComponent, D1, D2, D3>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested query5 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.query5<NameComponent, D1, D2, D3, D4>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested query6 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.query6<NameComponent, D1, D2, D3, D4, D5>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested queryMut preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.queryMut<NameComponent>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested queryMut2 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.queryMut2<NameComponent, D1>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested queryMut3 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.queryMut3<NameComponent, D1, D2>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested queryMut4 preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final r in w.queryMut4<NameComponent, D1, D2, D3>()) {
      seen.add(r.$2.value);
      w.query<NameComponent>().toList();
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested raw2 callback preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final chunk in w.queryRaw2<NameComponent, NameComponent, D1, D1>()) {
      chunk.forEachRow((final row, final entity, final a, final b) {
        seen.add(a.value);
        w.query<NameComponent>().toList();
      });
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested raw3 callback preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final chunk
        in w.queryRaw3<NameComponent, NameComponent, D1, D1, D2, D2>()) {
      chunk.forEachRow((final row, final entity, final a, final b, final c) {
        seen.add(a.value);
        w.query<NameComponent>().toList();
      });
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested raw4 callback preserves rows', () {
    final w = fixture();
    final seen = <String>[];
    for (final chunk
        in w
            .queryRaw4<
              NameComponent,
              NameComponent,
              D1,
              D1,
              D2,
              D2,
              D3,
              D3
            >()) {
      chunk.forEachRow((
        final row,
        final entity,
        final a,
        final b,
        final c,
        final d,
      ) {
        seen.add(a.value);
        w.query<NameComponent>().toList();
      });
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('raw column callback survives inner early break', () {
    final w = fixture();
    final seen = <String>[];
    for (final chunk in w.queryRaw2<NameComponent, NameComponent, D1, D1>()) {
      chunk.column1.forEachIndexed((final row, final name) {
        seen.add(name.value);
        for (final inner in w.query<NameComponent>()) {
          if (inner.$2.value == 'row3') break;
        }
      });
    }
    expect(seen, ['row0', 'row1', 'row2', 'row3']);
  });
  test('nested typed queryExt restores column each row', () {
    final w = typedFixture(10);
    final seen = <double>[];
    for (final row in w.queryExt<PositionComponent, Position>()) {
      seen.add(row.$2.x);
      w.queryExt<PositionComponent, Position>().toList();
    }
    expect(seen, [10, 11, 12, 13]);
  });
  test('nested typed queryExt2 restores column each row', () {
    final w = typedFixture(10);
    final seen = <double>[];
    for (final row
        in w
            .queryExt2<
              PositionComponent,
              Position,
              HealthComponent,
              Health
            >()) {
      seen.add(row.$2.x);
      w.queryExt<PositionComponent, Position>().toList();
    }
    expect(seen, [10, 11, 12, 13]);
  });
  test('nested typed queryExt3 restores column each row', () {
    final w = typedFixture(10);
    final seen = <double>[];
    for (final row
        in w
            .queryExt3<
              PositionComponent,
              Position,
              HealthComponent,
              Health,
              NameComponent,
              NameComponent
            >()) {
      seen.add(row.$2.x);
      w.queryExt<PositionComponent, Position>().toList();
    }
    expect(seen, [10, 11, 12, 13]);
  });
  test('nested typed queryExt4 restores column each row', () {
    final w = typedFixture(10);
    final seen = <double>[];
    for (final row
        in w
            .queryExt4<
              PositionComponent,
              Position,
              HealthComponent,
              Health,
              NameComponent,
              NameComponent,
              D1,
              D1
            >()) {
      seen.add(row.$2.x);
      w.queryExt<PositionComponent, Position>().toList();
    }
    expect(seen, [10, 11, 12, 13]);
  });
  test('nested raw extension iterator restores columns', () {
    final w = typedFixture(10);
    final seen = <double>[];
    for (final row
        in w
            .queryRawExt2<
              PositionComponent,
              Position,
              HealthComponent,
              Health
            >()) {
      seen.add(row.$2.x);
      w.queryExt<PositionComponent, Position>().toList();
    }
    expect(seen, [10, 11, 12, 13]);
  });
  test('typed queries across worlds restore local column', () {
    final a = typedFixture(10);
    final b = typedFixture(20);
    final seen = <double>[];
    for (final row in a.queryExt<PositionComponent, Position>()) {
      seen.add(row.$2.x);
      b.queryExt<PositionComponent, Position>().toList();
    }
    expect(seen, [10, 11, 12, 13]);
    for (final row in a.query<NameComponent>()) {
      final value = row.$1
          .toExtension()
          .getExtension<PositionComponent, Position>()!
          .x;
      expect(value, greaterThanOrEqualTo(10));
      expect(value, lessThan(20));
      b.queryExt<PositionComponent, Position>().toList();
    }
  });
  test('nested typed queryExtWhere restores predicate result', () {
    final w = typedFixture(10);
    final seen = <double>[];
    for (final row in w.queryExtWhere<PositionComponent, Position>((
      final value,
    ) {
      w.queryExt<PositionComponent, Position>().toList();
      return true;
    })) {
      seen.add(row.$2.x);
    }
    expect(seen, [10, 11, 12, 13]);
  });
  test('nested typed queryExt2Where restores predicate result', () {
    final w = typedFixture(10);
    final seen = <double>[];
    for (final row
        in w.queryExt2Where<
          PositionComponent,
          Position,
          HealthComponent,
          Health
        >((final value) {
          w.queryExt<PositionComponent, Position>().toList();
          return true;
        })) {
      seen.add(row.$2.x);
    }
    expect(seen, [10, 11, 12, 13]);
  });
}
