import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('Coverage round3 component query paths', () {
    late World world;
    late Entity deadEntity;
    late Entity validEntity;
    late Entity mislocatedEntity;

    setUp(() {
      world = buildTestWorld();
      world.components.registerObjectComponent<_Q1>();
      world.components.registerObjectComponent<_Q2>();
      world.components.registerObjectComponent<_Q3>();
      world.components.registerObjectComponent<_Q4>();
      world.components.registerObjectComponent<_Q5>();
      world.components.registerObjectComponent<_Q6>();

      deadEntity = world.reserveEmptyEntity().entity;
      validEntity = world.reserveEmptyEntity().entity;
      mislocatedEntity = world.reserveEmptyEntity().entity;

      final bundle = ComponentBundle.fromLists(
        [
          const _Q1(1),
          const _Q2(2),
          const _Q3(3),
          const _Q4(4),
          const _Q5(5),
          const _Q6(6),
          const NameComponent('n'),
        ],
        const [(PositionComponent, Position), (HealthComponent, Health)],
      );

      world.spawnBundle(deadEntity, bundle);
      world.spawnBundle(validEntity, bundle);
      world.spawnBundle(mislocatedEntity, bundle);
      world.flush();

      // Intentionally leave stale rows in archetype lists for skip branches.
      world.entities.destroy(deadEntity);
      world.entities.setLocation(mislocatedEntity, EntityLocation.nullLocation);
    });

    test('iterExt1 same-type fast path and query.matches false branches', () {
      final q = ComponentQuery.fromWorld(world);
      final sameType = q.iterExt1<NameComponent, NameComponent>().toList();
      expect(sameType, isNotEmpty);

      expect(
        () => q
            .iterExt1Where<NameComponent, NameComponent>(
              (final n) => n.value == 'n',
            )
            .toList(),
        throwsA(isA<StateError>()),
      );

      final qRequired = ComponentQuery(
        world: world,
        required: [world.components.getComponentId<_Q1>()],
      );
      final sigMissing = ArchetypeSignature.fromIds([
        world.components.getComponentId<NameComponent>(),
      ]);
      expect(qRequired.matches(sigMissing), isFalse);

      final qExcluded = ComponentQuery(
        world: world,
        required: [world.components.getComponentId<NameComponent>()],
        excluded: [world.components.getComponentId<NameComponent>()],
      );
      final sigIntersect = ArchetypeSignature.fromIds([
        world.components.getComponentId<NameComponent>(),
      ]);
      expect(qExcluded.matches(sigIntersect), isFalse);
    });

    test('iterExt3/iterExt4 validation branches', () {
      final q = ComponentQuery.fromWorld(world);

      expect(
        () => q.iterExt3<_Q1, String, _Q2, _Q2, _Q3, _Q3>().toList(),
        throwsA(isA<ExtensionTypeNotRegisteredError>()),
      );

      expect(
        () => q
            .iterExt4<
              PositionComponent,
              String,
              HealthComponent,
              Health,
              NameComponent,
              NameComponent,
              _Q1,
              _Q1
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
              String,
              NameComponent,
              NameComponent,
              _Q1,
              _Q1
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
              NameComponent,
              String,
              _Q1,
              _Q1
            >()
            .toList(),
        throwsA(isA<ExtensionTypeNotRegisteredError>()),
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
              _Q4,
              String
            >()
            .toList(),
        throwsA(isA<ExtensionTypeNotRegisteredError>()),
      );
    });

    test(
      'iterator current and stale/null-skipping branches across families',
      () {
        final q = ComponentQuery.fromWorld(world);

        final i2 = q.iter2<_Q1, _Q2>().iterator;
        expect(i2.moveNext(), isTrue);
        expect(i2.current.$2, isA<_Q1>());

        final i3 = q.iter3<_Q1, _Q2, _Q3>().iterator;
        expect(i3.moveNext(), isTrue);
        expect(i3.current.$3, isA<_Q2>());

        final i4 = q.iter4<_Q1, _Q2, _Q3, _Q4>().iterator;
        expect(i4.moveNext(), isTrue);
        expect(i4.current.$4, isA<_Q3>());

        final i5 = q.iter5<_Q1, _Q2, _Q3, _Q4, _Q5>().iterator;
        expect(i5.moveNext(), isTrue);
        expect(i5.current.$5, isA<_Q4>());

        final i6 = q.iter6<_Q1, _Q2, _Q3, _Q4, _Q5, _Q6>().iterator;
        expect(i6.moveNext(), isTrue);
        expect(i6.current.$6, isA<_Q5>());

        final ie3 = q
            .iterExt3<
              PositionComponent,
              Position,
              HealthComponent,
              Health,
              NameComponent,
              NameComponent
            >()
            .iterator;
        expect(ie3.moveNext(), isTrue);
        expect(ie3.current.$2, isA<Position>());

        final ie4 = q
            .iterExt4<
              PositionComponent,
              Position,
              HealthComponent,
              Health,
              NameComponent,
              NameComponent,
              _Q1,
              _Q1
            >()
            .iterator;
        expect(ie4.moveNext(), isTrue);
        expect(ie4.current.$3, isA<Health>());

        // Consume full iterators to hit invalid/null skip branches.
        expect(q.iterMut1<_Q1>().toList(), hasLength(1));
        expect(q.iterMut2<_Q1, _Q2>().toList(), hasLength(1));
        expect(q.iterMut3<_Q1, _Q2, _Q3>().toList(), hasLength(1));
        expect(q.iterMut4<_Q1, _Q2, _Q3, _Q4>().toList(), hasLength(1));
      },
    );
  });

  group('Coverage round3 cache/registry/entities/errors', () {
    test('query cache branches, debug getters, and key/entry formatting', () {
      final tracker = QueryStructuralTouchTracker();
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);
      tracker.markTouched(id1);
      expect(tracker.wasTouched(id1), isTrue);
      expect(tracker.touchedComponents, contains(id1));
      expect(tracker.maskWasTouched(createComponentMask([id1, id2])), isTrue);
      tracker.clear();
      expect(tracker.wasTouched(id1), isFalse);

      final cacheDisabled = QueryCache(enableResultCaching: false);
      expect(
        cacheDisabled.getCachedResult(
          QueryCacheKey(emptyComponentMask),
          ArchetypeRegistry(),
          () => const [],
        ),
        isNull,
      );
      cacheDisabled.onArchetypeChange();
      cacheDisabled.onWorldFlush();
      expect(cacheDisabled.stats.resultCacheSize, 0);

      final resultCache = QueryResultCache(
        maxSize: 1,
        enableStructuralTouchTracking: false,
      );
      final k1 = QueryCacheKey(emptyComponentMask, 'p1');
      final k2 = QueryCacheKey(emptyComponentMask, 'p2');
      resultCache.put(k1, const []);
      resultCache.put(k2, const []);
      expect(resultCache.debugCache.length, 1);
      resultCache.markStructurallyTouched(const ComponentId(9));
      expect(resultCache.debugCache, isEmpty);
      resultCache.onArchetypeChange();
      resultCache.onWorldFlush();
      expect(resultCache.debugStructurallyTouchedComponents, isEmpty);

      final entry = QueryCacheEntry(const [], 1, 2);
      expect(entry.toString(), contains('flush: 1'));

      final keyA = QueryCacheKey(emptyComponentMask, 'x');
      final keyB = QueryCacheKey(emptyComponentMask, 'x');
      expect(keyA == keyA, isTrue);
      expect(keyA == keyB, isTrue);
      expect(keyA.toString(), contains('predicate: x'));
    });

    test('archetype registry clear/count/operator and index failures', () {
      final registry = ArchetypeRegistry();
      expect(registry.count, 1);
      expect(() => registry[const ArchetypeIndex(99)], throwsRangeError);

      final id = registry.getOrCreateArchetype(
        ArchetypeSignature.fromIds(const [ComponentId(1)]),
      );
      expect(id, isNot(ArchetypeId.zero));
      expect(registry.count, 2);
      registry.clear();
      expect(registry.count, 1);
      expect(
        registry.findArchetype(ArchetypeSignature.empty),
        ArchetypeId.zero,
      );
      expect(
        () => registry.findArchetypeIndex(const ArchetypeId(77)),
        throwsA(isA<ArchetypeNotFoundError>()),
      );
    });

    test('entities resize and invalid index checks', () {
      final entities = Entities();
      Entity last = entities.create();
      for (var i = 0; i < 1100; i++) {
        last = entities.create();
      }
      entities.setLocation(last, const EntityLocation(ArchetypeId(7), 3));
      final location = entities.getLocation(last);
      expect(location.archetypeId, const ArchetypeId(7));
      expect(location.archetypeRow, 3);
      expect(entities.isAlive(Entity.create(999999, 1)), isFalse);
    });

    test('error constructors and message formatting', () {
      final cre = ComponentRegistrationException(_Q1, 'boom');
      expect(cre.toString(), contains('boom'));
      expect(EcsException('x').toString(), 'x');
      expect(
        EntityNotFoundError(Entity.create(1, 1)).message,
        contains('not found'),
      );
      expect(
        EventColumnUnsupportedError(String, 'store').message,
        contains('not supported'),
      );
      expect(
        EventStrideCalculationError(_Q1).message,
        contains('stride calculation failed'),
      );
    });
  });

  group('Coverage round3 world/command/schedule branches', () {
    test('world preRegisterArchetypesForBundles and getComponent errors', () {
      final world = buildTestWorld();

      world.preRegisterArchetypesForBundles([
        ComponentBundle.fromLists([const _UnregisteredComp()]),
        ComponentBundle.fromLists(
          [const NameComponent('x')],
          const [(PositionComponent, Position)],
        ),
      ]);

      final dead = world.entities.create();
      world.entities.destroy(dead);
      expect(
        () => world.getComponent<NameComponent>(dead),
        throwsA(isA<EntityNotFoundError>()),
      );

      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromLists(const [], const [
          (PositionComponent, Position),
        ]),
      );
      world.flush();
      expect(
        () => world.getComponent<NameComponent>(e),
        throwsA(isA<ComponentNotFoundError>()),
      );
    });

    test('world entity extension getters and create/getOrCreate', () {
      final world = buildTestWorld();
      final e = world.reserveEmptyEntity().entity;
      world.resources.push(_DummyResource(1)); // pending flush path

      final (ext, isValid) = world.getEntityExtension(e);
      expect(isValid, isTrue);
      expect(ext.entity, e);
      expect(ext.world, same(world));
      expect(ext.location.archetypeId, ArchetypeId.zero);
      expect(ext.archetype.archetypeId, ArchetypeId.zero);
      expect(ext.isValid, isTrue);

      final pos = ext.create<PositionComponent, Position>();
      pos.x = 3;
      expect(pos.x, 3);

      final hp = ext.getOrCreate<HealthComponent, Health>();
      hp.value = 9;
      expect(hp.value, 9);
      expect(ext.toEntity().entity, e);
      expect(ext.toMut().entity, e);
    });

    test('command queue command variants and error branches', () {
      final world = buildTestWorld();
      world.components.registerObjectComponent<_CmdComp>();
      final e = world.reserveEmptyEntity().entity;

      world.commandQueue
        ..push(BatchAddClassComponentsCommand([e], const [_CmdComp(7)]))
        ..push(UpsertResourceCommand(_DummyResource(5)))
        ..execute();

      expect(world.getComponent<_CmdComp>(e).value, 7);
      expect(world.getResource<Resource>(), isA<_DummyResource>());

      world.commandQueue
        ..push(DeleteResourceCommand(_DummyResource(0)))
        ..execute();

      world.commandQueue.push(
        BatchSpawnCommand(ComponentBundle.fromLists(const []), 1),
      );
      expect(() => world.commandQueue.execute(), throwsArgumentError);

      world.commandQueue.push(
        BatchSpawnCommand(
          ComponentBundle.fromLists(const [_UnregisteredComp()]),
          1,
        ),
      );
      expect(
        () => world.commandQueue.execute(),
        throwsA(isA<ComponentNotRegisteredError>()),
      );

      final dead = world.entities.create();
      world.entities.destroy(dead);
      world.commandQueue.push(
        SpawnEntityComponentsCommand(
          ComponentBundle.fromLists(const [NameComponent('x')]),
          dead,
        ),
      );
      expect(
        () => world.commandQueue.execute(),
        throwsA(isA<EntityNotFoundError>()),
      );
      final failure = world.commandQueue.failures.last;
      expect(failure.commandType, SpawnEntityComponentsCommand);
      expect(failure.error, isA<EntityNotFoundError>());

      world.commandQueue.push(
        UpsertComponentCommand(dead, const NameComponent('x')),
      );
      expect(
        () => world.commandQueue.execute(),
        throwsA(isA<EntityNotFoundError>()),
      );

      world.commandQueue.push(
        BatchAddExtensionComponentsCommand(
          [dead],
          const [(PositionComponent, Position)],
        ),
      );
      expect(
        () => world.commandQueue.execute(),
        throwsA(isA<EntityNotFoundError>()),
      );
    });

    test(
      'EveryNSeconds without resource throws deterministic source error',
      () {
        final trigger = EveryNSeconds(0);
        expect(
          () => trigger.shouldRun(World()),
          throwsA(isA<ScheduleTimeSourceMissingError>()),
        );
      },
    );
  });
}

class _CmdComp extends Component {
  const _CmdComp(this.value);
  final int value;
}

class _DummyResource extends Resource {
  _DummyResource(this.value);
  final int value;
}

class _Q1 extends Component {
  const _Q1(this.value);
  final int value;
}

class _Q2 extends Component {
  const _Q2(this.value);
  final int value;
}

class _Q3 extends Component {
  const _Q3(this.value);
  final int value;
}

class _Q4 extends Component {
  const _Q4(this.value);
  final int value;
}

class _Q5 extends Component {
  const _Q5(this.value);
  final int value;
}

class _Q6 extends Component {
  const _Q6(this.value);
  final int value;
}

class _UnregisteredComp extends Component {
  const _UnregisteredComp();
}
