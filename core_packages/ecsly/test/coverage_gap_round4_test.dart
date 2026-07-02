import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('Coverage round4 event/query/world wrappers', () {
    test('EventRegistry validates stride/sample/factory error paths', () {
      final world = World();

      expect(
        () => world.events.register<_PlainEvent>(
          fromDoubleFieldsFactory: (final f) => _PlainEvent(f[0]),
          stride: 0,
        ),
        throwsA(isA<EventRegistrationException>()),
      );

      expect(
        () => world.events.register<_PlainEvent>(
          fromDoubleFieldsFactory: (final f) => _PlainEvent(f[0]),
        ),
        throwsA(isA<EventRegistrationException>()),
      );

      expect(
        () => world.events.register<_PlainEvent>(
          fromDoubleFieldsFactory: (final f) => _PlainEvent(f[0]),
          sampleEvent: const _PlainEvent(1),
        ),
        throwsA(isA<EventRegistrationException>()),
      );

      expect(
        () => world.events.register<_BaseMaybeTypedEvent>(
          fromDoubleFieldsFactory: (final _) => throw StateError('boom'),
          sampleEvent: const _TypedVariant(1, 2),
        ),
        throwsA(isA<EventFactoryValidationError>()),
      );

      expect(
        () => world.events.register<_BaseMaybeTypedEvent>(
          fromDoubleFieldsFactory: (final f) => _UntypedVariant(f[0]),
          sampleEvent: const _TypedVariant(1, 2),
        ),
        throwsA(isA<EventRegistrationException>()),
      );

      expect(
        () => world.events.register<_BaseMaybeTypedEvent>(
          fromDoubleFieldsFactory: (final f) => _TypedVariant3(f[0], f[1], 0),
          sampleEvent: const _TypedVariant(1, 2),
        ),
        throwsA(isA<EventFactoryValidationError>()),
      );
    });

    test(
      'queryExtWhere/queryExt3/queryExt4 wrappers run through world API',
      () {
        final world = buildTestWorld();
        world.components.registerObjectComponent<_Q4a>();

        final e = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          e,
          ComponentBundle.fromLists(
            [const NameComponent('q4'), const _Q4a(7)],
            const [(PositionComponent, Position), (HealthComponent, Health)],
          ),
        );
        world.flush();

        final extWhere = world
            .queryExtWhere<PositionComponent, Position>((final p) => p.x == 0)
            .toList();
        expect(extWhere.length, 1);

        final ext3 = world
            .queryExt3<
              PositionComponent,
              Position,
              HealthComponent,
              Health,
              NameComponent,
              NameComponent
            >()
            .toList();
        expect(ext3.length, 1);

        final ext4 = world
            .queryExt4<
              PositionComponent,
              Position,
              HealthComponent,
              Health,
              NameComponent,
              NameComponent,
              _Q4a,
              _Q4a
            >()
            .toList();
        expect(ext4.length, 1);
      },
    );

    test(
      'WorldEntityMut location/toEntity/toExtension and missing getMut2/3',
      () {
        final world = buildTestWorld();
        world.components.registerObjectComponent<_Q4a>();
        final e = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          e,
          ComponentBundle.fromLists(const [NameComponent('m')]),
        );
        world.flush();

        final (entityMut, isValid) = world.getEntityMut(e);
        expect(isValid, isTrue);
        expect(entityMut.location.archetypeId, isNot(ArchetypeId.zero));
        expect(entityMut.toEntity().entity, e);
        expect(entityMut.toExtension().entity, e);

        expect(
          () => entityMut.getMut2<NameComponent, _Q4a>(),
          throwsA(isA<ComponentNotFoundError>()),
        );
        expect(
          () => entityMut.getMut3<NameComponent, _Q4a, HealthComponent>(),
          throwsA(isA<ComponentNotFoundError>()),
        );
      },
    );
  });

  group('Coverage round4 registries/command queue/archetype/simd', () {
    test(
      'ResourceRegistry getByIdOrThrow/getType/register existing branches',
      () {
        final world = World();
        final resources = world.resources;

        final id1 = resources.registerResource<_DummyRes4>();
        expect(resources.registerResource<_DummyRes4>(), id1);

        final id2 = resources.registerResourceByType(_DummyRes4);
        expect(resources.registerResourceByType(_DummyRes4), id2);

        expect(resources.getType(const ResourceId(999)), isNull);
        expect(
          () => resources.getByIdOrThrow<_DummyRes4>(const ResourceId(999)),
          throwsArgumentError,
        );
      },
    );

    test(
      'CommandQueue migration class write path and null-archetype upsert path',
      () {
        final world = buildTestWorld();

        final existing = world.reserveEmptyEntity().entity;
        world.spawnBundle(
          existing,
          ComponentBundle.fromLists(const [NameComponent('old')]),
        );
        world.flush();

        world.commandQueue
          ..push(
            BatchAddClassComponentsCommand(
              [existing],
              const [NameComponent('new')],
            ),
          )
          ..execute();
        expect(world.getComponent<NameComponent>(existing).value, 'new');

        final weird = world.entities.create();
        world.entities.setLocation(
          weird,
          const EntityLocation(ArchetypeId(777), 0),
        );
        world.commandQueue
          ..push(UpsertComponentCommand(weird, const NameComponent('late')))
          ..execute();
        expect(world.getComponent<NameComponent>(weird).value, 'late');
      },
    );

    test(
      'Archetype bulk ops addEntities/removeEntities and isEmpty getter',
      () {
        const componentId = ComponentId(1);
        final signature = ArchetypeSignature.fromIds(const [componentId]);
        final archetype = Archetype(
          archetypeId: const ArchetypeId(1),
          signature: signature,
        );
        final entities = Entities();

        archetype.addColumn(componentId, ObjectColumn<Object>());
        expect(archetype.isEmpty, isTrue);

        final e1 = entities.create();
        final e2 = entities.create();
        archetype.addEntities([e1, e2]);
        entities.setLocation(e1, const EntityLocation(ArchetypeId(1), 0));
        entities.setLocation(e2, const EntityLocation(ArchetypeId(1), 1));
        expect(archetype.entityCount, 2);

        archetype.removeEntities([e1, e2], entities);
        expect(archetype.isEmpty, isTrue);
      },
    );

    test('scalePositionsSimd uses SIMD branch for stride-4 float columns', () {
      final col = FloatColumn(stride: 4, initialCapacity: 2)
        ..addBlank()
        ..setValue(0, 0, 1)
        ..setValue(0, 1, 2)
        ..setValue(0, 2, 3)
        ..setValue(0, 3, 4);

      scalePositionsSimd(col, 2);
      expect(col.getValue(0, 0), 2);
      expect(col.getValue(0, 1), 4);
      expect(col.getValue(0, 2), 6);
      expect(col.getValue(0, 3), 8);
    });

    test(
      'World.evictQueriesForStructuralComponent delegates to query cache',
      () {
        final world = World();
        world.evictQueriesForStructuralComponent(const ComponentId(12));
        expect(world.queryCache.stats.resultCacheSize, 0);
      },
    );
  });
}

abstract class _BaseMaybeTypedEvent extends EcsEvent {
  const _BaseMaybeTypedEvent();
}

class _DummyRes4 extends Resource {
  _DummyRes4(this.value);
  final int value;
}

class _PlainEvent extends EcsEvent {
  const _PlainEvent(this.value);
  final double value;
}

class _Q4a extends Component {
  const _Q4a(this.value);
  final int value;
}

class _TypedVariant extends _BaseMaybeTypedEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  const _TypedVariant(this.a, this.b);
  final double a;
  final double b;

  @override
  List<double> get numericFields => [a, b];
}

class _TypedVariant3 extends _BaseMaybeTypedEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  const _TypedVariant3(this.a, this.b, this.c);
  final double a;
  final double b;
  final double c;

  @override
  List<double> get numericFields => [a, b, c];
}

class _UntypedVariant extends _BaseMaybeTypedEvent {
  const _UntypedVariant(this.a);
  final double a;
}
