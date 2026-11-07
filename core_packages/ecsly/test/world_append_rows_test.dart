import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

/// A bulk-append ingest component: one SoA int column, written directly
/// after [World.appendRows] reserves the rows.
final class IngestValueComponent extends Component {
  const IngestValueComponent();
}

final class _IngestValueColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
}

/// An object-column component: the verbatim-payload path (a string column
/// with per-row wrapper is how a data plane keeps text in the World).
final class IngestLabelComponent extends Component {
  const IngestLabelComponent(this.label);
  final String label;
}

World buildWorld() {
  final world = World();
  world.components
    ..registerSoAComponent<IngestValueComponent>(
      columnFactory: _IngestValueColumnFactory(),
    )
    ..registerObjectComponent<IngestLabelComponent>();
  return world;
}

ArchetypeSignature ingestSignature(final World world) => ArchetypeSignature.fromIds([
  world.components.getComponentId<IngestValueComponent>(),
  world.components.getComponentId<IngestLabelComponent>(),
]);

void main() {
  group('World.appendRows', () {
    test('reserves dense rows and returns them for direct column fill', () {
      final world = buildWorld();
      final signature = ingestSignature(world);
      final valueId = world.components
          .getComponentId<IngestValueComponent>();
      final labelId = world.components
          .getComponentId<IngestLabelComponent>();

      final appended = world.appendRows(signature, 1000);
      expect(appended.count, 1000);
      expect(appended.firstRow, 0);
      expect(appended.archetype.entityCount, 1000);

      final values =
          appended.archetype.getColumn(valueId)! as IntColumn;
      final labels = appended.archetype.getColumn(labelId)!
          as ObjectColumn<IngestLabelComponent>;
      for (var row = appended.firstRow; row < 1000; row++) {
        values.setValueAt(row, row * 3);
        labels.setValue(row, IngestLabelComponent('label $row'));
      }

      // The fill is visible through the ordinary read paths.
      expect(values.getValueAt(999), 2997);
      expect(labels.getValue(7)!.label, 'label 7');
      expect(
        world.getComponent<IngestLabelComponent>(appended.entities[7]).label,
        'label 7',
      );
    });

    test('keeps entities alive and located at their rows', () {
      final world = buildWorld();
      final appended = world.appendRows(ingestSignature(world), 3);
      for (var i = 0; i < appended.entities.length; i++) {
        final entity = appended.entities[i];
        expect(world.entities.isAlive(entity), isTrue);
        final location = world.entities.getLocation(entity);
        expect(location.archetypeId, appended.archetype.archetypeId);
        expect(location.archetypeRow, appended.firstRow + i);
      }
    });

    test('is visible to queries: structural revision bumped, cache evicted', () {
      final world = buildWorld();
      final signature = ingestSignature(world);
      final query = ComponentQuery.fromWorld(world).withType<
          IngestValueComponent>();
      // Materialize an empty result BEFORE the append so a stale cache
      // would be observable.
      expect(query.count(), 0);
      expect(query.entities.length, 0);

      final revisionBefore = world.structuralRevision;
      world.appendRows(signature, 5);
      expect(world.structuralRevision, greaterThan(revisionBefore));
      expect(query.count(), 5);
      expect(query.entities.length, 5);

      world.appendRows(signature, 4);
      expect(query.count(), 9);
      expect(query.entities.length, 9);
    });

    test('a second append continues the row space densely', () {
      final world = buildWorld();
      final signature = ingestSignature(world);
      final first = world.appendRows(signature, 10);
      final second = world.appendRows(signature, 5);
      expect(second.firstRow, 10);
      expect(first.archetype, same(second.archetype));
      expect(second.archetype.entityCount, 15);
    });

    test('count 0 creates the archetype and appends nothing', () {
      final world = buildWorld();
      final appended = world.appendRows(ingestSignature(world), 0);
      expect(appended.count, 0);
      expect(appended.entities, isEmpty);
      expect(appended.archetype.entityCount, 0);
      expect(appended.firstRow, 0);
    });

    test('negative count is refused', () {
      final world = buildWorld();
      expect(
        () => world.appendRows(ingestSignature(world), -1),
        throwsA(isA<RangeError>()),
      );
    });

    test('coexists with command-queue spawns in both orders', () {
      final world = buildWorld();
      final signature = ingestSignature(world);
      final appended = world.appendRows(signature, 2);
      expect(appended.count, 2);

      // A queued spawn lands through the ordinary command path (its own
      // archetype when the component set differs); the appended rows are
      // untouched and stay query-visible alongside it.
      final spawned = world.spawnComponents(<Component>[
        const IngestLabelComponent('queued'),
      ]);
      world.flush();
      expect(world.entities.isAlive(spawned), isTrue);
      expect(appended.archetype.entityCount, 2);
      expect(
        ComponentQuery.fromWorld(
          world,
        ).withType<IngestLabelComponent>().count(),
        3,
      );
      expect(
        ComponentQuery.fromWorld(
          world,
        ).withType<IngestValueComponent>().count(),
        2,
      );

      // And appendRows after a flush keeps dense rows.
      final more = world.appendRows(signature, 2);
      expect(more.firstRow, 2);
      expect(appended.archetype.entityCount, 4);
    });

    test('append-only rows stay stable under repeated tail ingest', () {
      // The fold-from-cursor contract: ingest the same log tail shape
      // repeatedly; earlier rows never move, so a caller-owned row-id
      // identity (row == domain id - 1) holds for the life of the world.
      final world = buildWorld();
      final signature = ingestSignature(world);
      final valueId = world.components
          .getComponentId<IngestValueComponent>();
      var ingested = 0;
      for (var batch = 0; batch < 5; batch++) {
        final count = 100 * (batch + 1);
        final appended = world.appendRows(signature, count);
        expect(appended.firstRow, ingested);
        final values =
            appended.archetype.getColumn(valueId)! as IntColumn;
        for (var row = 0; row < count; row++) {
          values.setValueAt(appended.firstRow + row, ingested + row);
        }
        ingested += count;
      }
      final values = world.appendRows(
        signature,
        0,
      ).archetype.getColumn(valueId)! as IntColumn;
      for (var id = 0; id < ingested; id++) {
        expect(values.getValueAt(id), id);
      }
      expect(world.entities.count, ingested);
    });
  });
}
