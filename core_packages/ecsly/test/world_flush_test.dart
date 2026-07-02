import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

class TickResource extends Resource {
  TickResource(this.value);
  final int value;
}

class UnregisteredComponent extends Component {
  const UnregisteredComponent();
}

void main() {
  group('World flush semantics', () {
    test(
      'ensureFlushed only flushes when needed and respects re-entrancy guard',
      () {
        final world = buildTestWorld();

        world.ensureFlushed();
        expect(world.commandQueue.needsFlush, isFalse);
        expect(world.resources.doesNeedFlush, isFalse);

        world.upsertResource(TickResource(1));
        expect(world.resources.doesNeedFlush, isTrue);
        world.ensureFlushed();
        expect(world.resources.doesNeedFlush, isFalse);

        final e = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          e,
          ComponentBundle.fromLists(const [NameComponent('x')]),
        );
        expect(world.commandQueue.needsFlush, isTrue);

        world.isFlushing = true;
        world.ensureFlushed();
        expect(world.commandQueue.needsFlush, isTrue);
        world.isFlushing = false;

        world.ensureFlushed();
        expect(world.commandQueue.needsFlush, isFalse);
      },
    );

    test('world query revisions describe structural flushes only', () {
      final world = buildTestWorld();

      expect(world.queryRevision, 0);

      world.ensureFlushed();
      expect(world.queryRevision, 0);

      world.upsertResource(TickResource(1));
      world.ensureFlushed();

      expect(world.queryRevision, 0);

      final entity = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        entity,
        ComponentBundle.fromLists(const [NameComponent('tracked')]),
      );
      world.ensureFlushed();

      expect(world.queryRevision, 1);
    });

    test('query revision is one topology epoch per structural flush', () {
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
      world.ensureFlushed();

      expect(world.queryRevision, 1);

      world.removeComponent<NameComponent>(e1);
      world.despawnEntity(e2);
      world.ensureFlushed();

      expect(world.queryRevision, 2);
    });

    test('in-place component updates do not bump query revision', () {
      final world = buildTestWorld();
      final entity = world.reserveEmptyEntity().entity;

      world.spawnBundle(
        entity,
        ComponentBundle.fromLists(const [NameComponent('before')]),
      );
      world.ensureFlushed();
      final revision = world.queryRevision;

      world.upsertComponent<NameComponent>(
        entity,
        const NameComponent('after'),
      );
      world.ensureFlushed();

      expect(world.getComponent<NameComponent>(entity).value, 'after');
      expect(world.queryRevision, revision);
    });

    test('flush resets isFlushing even when execution throws', () {
      final world = buildTestWorld();
      final e = world.reserveEmptyEntity().entity;
      final queryRevision = world.queryRevision;

      world.upsertComponent<UnregisteredComponent>(
        e,
        const UnregisteredComponent(),
      );

      expect(world.flush, throwsA(isA<ComponentNotRegisteredError>()));
      expect(world.isFlushing, isFalse);
      expect(world.queryRevision, queryRevision);
    });

    test('partial structural flush failure still records one epoch', () {
      final world = buildTestWorld();
      final live = world.reserveEmptyEntity().entity;
      final missing = world.entities.create();
      world.entities.destroy(missing);

      world.spawnBundle(
        live,
        ComponentBundle.fromLists(const [NameComponent('ok')]),
      );
      world.spawnBundle(
        missing,
        ComponentBundle.fromLists(const [NameComponent('missing')]),
      );

      expect(world.flush, throwsA(isA<EntityNotFoundError>()));
      expect(world.queryRevision, 1);
      expect(world.getComponent<NameComponent>(live).value, 'ok');
    });

    test('query/getComponent auto-flush pending writes before reads', () {
      final world = buildTestWorld();
      final e = world.reserveEmptyEntity().entity;

      world
          .spawnBundle(e, ComponentBundle.fromLists(const [NameComponent('n')]))
          .upsert(const HealthComponent());

      expect(world.commandQueue.needsFlush, isTrue);

      final name = world.getComponent<NameComponent>(e);
      expect(name.value, 'n');
      expect(world.commandQueue.needsFlush, isFalse);

      final healthRows = world.queryExt<HealthComponent, Health>().toList();
      expect(healthRows.length, 1);
    });
  });
}
