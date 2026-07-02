import 'package:ecsly/src/archetypes/archetype.dart';
import 'package:ecsly/src/archetypes/archetype_signature.dart';
import 'package:ecsly/src/components/columns/columns.dart';
import 'package:ecsly/src/components/component.dart';
import 'package:ecsly/src/entities/entities.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('Archetype SoA storage invariants', () {
    test('addColumn back-fills blanks to existing entity count', () {
      final entities = Entities();
      final archetype = Archetype(
        archetypeId: const ArchetypeId(1),
        signature: ArchetypeSignature.empty,
      );

      final e1 = entities.create();
      final e2 = entities.create();
      archetype.addEntity(e1);
      entities.setLocation(e1, const EntityLocation(ArchetypeId(1), 0));
      archetype.addEntity(e2);
      entities.setLocation(e2, const EntityLocation(ArchetypeId(1), 1));

      final column = FloatColumn(stride: 2);
      archetype.addColumn(const ComponentId(1), column);

      expect(column.length, 2);
      expect(archetype.entityCount, 2);
    });

    test('addEntity grows all columns exactly once per entity', () {
      final entities = Entities();
      final archetype = Archetype(
        archetypeId: const ArchetypeId(2),
        signature: ArchetypeSignature.fromIds(const [
          ComponentId(1),
          ComponentId(2),
        ]),
      );

      final fCol = FloatColumn(stride: 2);
      final hCol = Uint8Column();
      archetype.addColumn(const ComponentId(1), fCol);
      archetype.addColumn(const ComponentId(2), hCol);

      final e1 = entities.create();
      final e2 = entities.create();

      expect(archetype.addEntity(e1), 0);
      entities.setLocation(e1, const EntityLocation(ArchetypeId(2), 0));
      expect(archetype.addEntity(e2), 1);
      entities.setLocation(e2, const EntityLocation(ArchetypeId(2), 1));

      expect(archetype.entityCount, 2);
      expect(fCol.length, 2);
      expect(hCol.length, 2);
    });

    test(
      'removeEntity swap-remove updates locations and keeps columns synced',
      () {
        final entities = Entities();
        final archetype = Archetype(
          archetypeId: const ArchetypeId(3),
          signature: ArchetypeSignature.fromIds(const [
            ComponentId(1),
            ComponentId(2),
          ]),
        );

        final pos = FloatColumn(stride: 2);
        final hp = Uint8Column();
        archetype.addColumn(const ComponentId(1), pos);
        archetype.addColumn(const ComponentId(2), hp);

        final e1 = entities.create();
        final e2 = entities.create();
        final e3 = entities.create();

        archetype.addEntity(e1);
        entities.setLocation(e1, const EntityLocation(ArchetypeId(3), 0));
        archetype.addEntity(e2);
        entities.setLocation(e2, const EntityLocation(ArchetypeId(3), 1));
        archetype.addEntity(e3);
        entities.setLocation(e3, const EntityLocation(ArchetypeId(3), 2));

        pos.set(0, f2(1, 1));
        pos.set(1, f2(2, 2));
        pos.set(2, f2(3, 3));
        hp.setValue(0, 10);
        hp.setValue(1, 20);
        hp.setValue(2, 30);

        archetype.removeEntity(e2, entities);

        expect(archetype.entityCount, 2);
        expect(pos.length, 2);
        expect(hp.length, 2);
        expect(archetype.entities, [e1, e3]);
        expect(entities.getLocation(e3).archetypeRow, 1);
        expect(pos.getValue(1, 0), 3);
        expect(hp.getValue(1), 30);
      },
    );

    test(
      'moveEntity copies overlap, removes source, fills destination row',
      () {
        final entities = Entities();
        final source = Archetype(
          archetypeId: const ArchetypeId(4),
          signature: ArchetypeSignature.fromIds(const [
            ComponentId(1),
            ComponentId(2),
          ]),
        );
        final destination = Archetype(
          archetypeId: const ArchetypeId(5),
          signature: ArchetypeSignature.fromIds(const [ComponentId(1)]),
        );

        final srcPos = FloatColumn(stride: 2);
        final srcHp = Uint8Column();
        final dstPos = FloatColumn(stride: 2);
        source.addColumn(const ComponentId(1), srcPos);
        source.addColumn(const ComponentId(2), srcHp);
        destination.addColumn(const ComponentId(1), dstPos);

        final e = entities.create();
        source.addEntity(e);
        entities.setLocation(e, const EntityLocation(ArchetypeId(4), 0));
        srcPos.set(0, f2(9, 4));
        srcHp.setValue(0, 77);

        source.moveEntity(e, destination, entities);

        expect(source.entityCount, 0);
        expect(destination.entityCount, 1);
        expect(dstPos.getValue(0, 0), 9);
        expect(dstPos.getValue(0, 1), 4);
      },
    );

    test('moveEntityExcluding does not copy excluded component', () {
      final entities = Entities();
      final source = Archetype(
        archetypeId: const ArchetypeId(6),
        signature: ArchetypeSignature.fromIds(const [
          ComponentId(1),
          ComponentId(2),
        ]),
      );
      final destination = Archetype(
        archetypeId: const ArchetypeId(7),
        signature: ArchetypeSignature.fromIds(const [
          ComponentId(1),
          ComponentId(2),
        ]),
      );

      final srcPos = FloatColumn(stride: 2);
      final srcHp = Uint8Column();
      final dstPos = FloatColumn(stride: 2);
      final dstHp = Uint8Column();
      source.addColumn(const ComponentId(1), srcPos);
      source.addColumn(const ComponentId(2), srcHp);
      destination.addColumn(const ComponentId(1), dstPos);
      destination.addColumn(const ComponentId(2), dstHp);

      final e = entities.create();
      source.addEntity(e);
      entities.setLocation(e, const EntityLocation(ArchetypeId(6), 0));
      srcPos.set(0, f2(5, 6));
      srcHp.setValue(0, 99);

      source.moveEntityExcluding(
        e,
        destination,
        const ComponentId(2),
        entities,
      );

      expect(destination.entityCount, 1);
      expect(dstPos.getValue(0, 0), 5);
      expect(dstPos.getValue(0, 1), 6);
      expect(dstHp.getValue(0), 0);
    });
  });
}
