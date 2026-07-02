import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

void main() {
  group('Entity value object', () {
    test('packing/unpacking and helpers', () {
      final e = Entity.create(123, 9);
      expect(e.indexValue, 123);
      expect(e.generation, 9);
      expect(e.isNull, isFalse);
      expect(e.isNotNull, isTrue);
      expect(e.entityToString(), contains('Entity(index: 123'));
      expect(e.toJson(), '123-9');

      const n = Entity.nullEntity;
      expect(n.isNull, isTrue);
      expect(n.isZero, isTrue);
      expect(n.whenNullUse(e), e);
      expect(e.whenNullUse(n), e);

      expect(EntityGeneration.zero.isZero, isTrue);
      expect(EntityGeneration.zero.next(), 1);
      expect(EntityGeneration.initial.next().next().isNotZero, isTrue);
      expect(EntityIndex.fromJson(7), 7);
      expect(EntityIndex.zero.isNotZero, isFalse);
    });
  });

  group('ComponentBundle and typed component lists', () {
    test('from/add APIs retain component tuples', () {
      final b = ComponentBundle.fromLists(
        const [_C1(1)],
        [(PositionComponent, Position)],
      );
      expect(b.components.items, hasLength(1));
      expect(b.extensionComponents.items, hasLength(1));

      expect(b.add(const _C2(2)), same(b));
      expect(b.addExtension<_C3, Health>(), same(b));
      expect(b.components.items, hasLength(2));
      expect(b.extensionComponents.items, hasLength(2));

      final extOnly = ComponentBundle.fromExtensionList([
        (HealthComponent, Health),
      ]);
      expect(extOnly.components.items, isEmpty);
      expect(extOnly.extensionComponents.items, hasLength(1));
    });

    test('ComponentsBatchList2/3 constructors and metadata paths', () {
      final b2 = ComponentsBatchList2<_C1, _C2>(
        component1: const _C1(1),
        component2: const _C2(2),
      );
      expect(b2.component1Type, _C1);
      expect(b2.component2Type, _C2);
      expect(() => b2.component1, throwsA(isA<TypeError>()));
      expect(() => b2.component2, throwsA(isA<TypeError>()));

      final b3 = ComponentsBatchList3<_C1, _C2, _C3>(
        component1: const _C1(1),
        component2: const _C2(2),
        component3: const _C3(3),
      );
      expect(() => b3.component1, throwsA(isA<TypeError>()));
      expect(() => b3.component2, throwsA(isA<TypeError>()));
      expect(() => b3.component3, throwsA(isA<TypeError>()));
      expect(b3.component3Type, _C3);
    });
  });

  group('WorldCommands wrappers', () {
    test('empty batches are no-op, non-empty push commands', () {
      final world = buildTestWorld();
      final commands = world.commands;
      expect(commands, isA<WorldCommands>());

      commands.batchAddClassComponents(const [], const [_C1(1)]);
      commands.batchAddClassComponents([Entity.create(1, 1)], const []);
      commands.batchAddExtensionComponents(const [], const [
        (PositionComponent, Position),
      ]);
      commands.batchAddExtensionComponents([Entity.create(1, 1)], const []);
      commands.batchRemoveComponents(const [], const [ComponentId(1)]);
      commands.batchRemoveComponents([Entity.create(1, 1)], const []);
      commands.batchSpawn(ComponentBundle.fromLists(const []), 0);
      expect(world.commandQueue.commandCount, 0);

      final e = world.entities.create();
      final bundle = ComponentBundle.fromLists(const [NameComponent('n')]);
      final chain = commands.spawnBundle(e, bundle);
      expect(chain.entity, e);

      commands.batchSpawn(bundle, 2);
      commands.upsert(e, const NameComponent('x'));
      commands.remove<NameComponent>(e);
      commands.removeResource(_R1(1));
      commands.upsertResource(_R1(2));
      commands.despawn(e);

      expect(world.commandQueue.commandCount, 7);
    });
  });

  group('World extensions wrappers and no-op flush helpers', () {
    test(
      'resource/schedule/plugin wrappers and command execution paths',
      () async {
        final world = buildTestWorld();

        world.flushEntitiesOnly();
        world.flushComponentsOnly();
        world.executeCommands();

        world.upsertResource(_R1(5));
        expect(world.getResource<_R1>().value, 5);
        final rid = world.resources.getResourceId<_R1>()!;
        expect(world.getResourceById<_R1>(rid)?.value, 5);

        world.removeResource<_R1>();
        world.flushResourcesOnly();
        expect(world.getResourceById<_R1>(rid), isNull);

        final ran = <String>[];
        world.createSchedule('A').add((final w) => ran.add('A'));
        expect(world.hasSchedule('A'), isTrue);
        expect(world.schedule('A').name, 'A');
        world.runSchedule('A');
        expect(ran, ['A']);

        await world.runScheduleAsync('A');
        expect(ran, ['A', 'A']);

        world.runSystem((final w) => ran.add('sys'));
        await world.runSystemAsync((final w) async => ran.add('asyncSys'));
        expect(ran, containsAllInOrder(['sys', 'asyncSys']));

        final b = world.getOrCreateSchedule('B', trigger: const EveryFrame());
        expect(b.name, 'B');
        expect(world.removeSchedule('B'), isTrue);
        expect(world.removeSchedule('B'), isFalse);

        var installs = 0;
        var uninstalls = 0;
        final plugin = _TestPlugin(
          'p',
          (final w) => installs++,
          (final w) => uninstalls++,
        );
        world.addPlugin(plugin);
        expect(world.hasPlugin('p'), isTrue);
        expect(world.getPlugin('p'), plugin);
        expect(world.removePlugin('p'), isTrue);
        expect(world.removePlugin('p'), isFalse);
        expect(installs, 1);
        expect(uninstalls, 1);

        final e = world.reserveEmptyEntity().entity;
        world.upsertComponent(e, const NameComponent('name'));
        world.flush();
        expect(world.getComponent<NameComponent>(e).value, 'name');

        final entityData = world.getEntity(e);
        final extData = world.getEntityExtension(e);
        final mutData = world.getEntityMut(e);
        expect(entityData.$2, isTrue);
        expect(extData.$2, isTrue);
        expect(mutData.$2, isTrue);

        world.removeComponent<NameComponent>(e);
        world.despawnEntity(e);
        world.executeCommands();
        world.flush();
        expect(world.getEntity(e).$2, isFalse);

        world.clear();
        expect(world.commandQueue.commandCount, 0);
        expect(world.systems.scheduleNames, isEmpty);
      },
    );
  });

  group('SparseTypeList and Uint8/Factory/Facade registries', () {
    test('sparse type list basic operations and stats', () {
      final list = SparseTypeList();
      expect(list.length, 0);
      expect(list.collisionCount, 0);
      expect(list.totalCollisions, 0);
      expect(list.maxCollisionsAtSingleIndex, 0);
      expect(list.collisionRate, 0);

      list.set(_C1, const ComponentId(1));
      list.set(_C2, const ComponentId(2));
      expect(list.length, 2);
      expect(list.contains(_C1), isTrue);
      expect(list.get(_C2), const ComponentId(2));

      list.set(_C1, const ComponentId(9));
      expect(list.get(_C1), const ComponentId(9));

      final entries = list.entries.toList();
      expect(entries, hasLength(2));
      expect(entries.map((final e) => e.$1), containsAll([_C1, _C2]));

      list.remove(_C2);
      list.remove(_C3); // remove missing path
      expect(list.get(_C2), isNull);
      expect(list.length, 1);
    });

    test('Uint8Column methods and bounds behavior', () {
      final col = Uint8Column(initialCapacity: 1);
      col.addBlank();
      col.setValue(0, 999);
      expect(col.getValue(0), 255);

      col.addBlank(); // resize path
      col.setValue(1, -10);
      expect(col.getValue(1), 0);

      final dest = Uint8Column(initialCapacity: 2)
        ..addBlank()
        ..addBlank();
      col.copyTo(0, dest, 1);
      expect(dest.getValue(1), 255);

      col.moveTo(1, dest, 0);
      expect(col.getValue(1), 0);

      col.swap(0, 1);
      col.swapRemove(0);
      expect(col.length, 1);

      col.resize(1); // no-op path
      final one = Uint8Column(initialCapacity: 1)..addBlank();
      expect(
        () => one.copyTo(0, FloatColumn(stride: 1), 0),
        throwsA(isA<ArgumentError>()),
      );
      col.clear();
      expect(col.length, 0);
    });

    test('column factory and facade registry edge paths', () {
      final cfr = ColumnFactoryRegistry();
      const id = ComponentId(7);
      expect(cfr.hasFactory(id), isFalse);
      expect(
        () => cfr.createColumn(id, type: _C1),
        throwsA(isA<EcsStateError>()),
      );

      cfr.registerFactory(id, _C1Factory());
      expect(cfr.hasFactory(id), isTrue);
      final created = cfr.createColumn(id, type: _C1, initialCapacity: 3);
      expect(created, isA<ObjectColumn<_C1>>());
      cfr.unregisterFactory(id);
      expect(cfr.hasFactory(id), isFalse);

      expect(
        ColumnFactoryRegistry.createFloatColumn(stride: 2),
        isA<FloatColumn>(),
      );
      expect(ColumnFactoryRegistry.createIntColumn(), isA<IntColumn>());
      expect(
        ColumnFactoryRegistry.createObjectColumn<_C1>(),
        isA<ObjectColumn<_C1>>(),
      );
      expect(ColumnFactoryRegistry.createUint8Column(), isA<Uint8Column>());

      final facades = ComponentFacadeRegistry();
      const invalidId = ComponentId(-1);
      expect(facades.hasFactory(invalidId), isFalse);
      expect(facades.getFactory(invalidId), isNull);
      expect(facades.getExtensionType(invalidId), isNull);
      expect(
        () => facades.createFacade<_C1>(invalidId, 0, ObjectColumn<_C1>()),
        throwsA(isA<ArgumentError>()),
      );

      const regId = ComponentId(8);
      facades.registerFactory<_C1>(regId, _C1FacadeFactory());
      final col = ObjectColumn<_C1>(initialCapacity: 2)..addBlank();
      col.setValue(0, const _C1(11));
      facades.initializeColumn(regId, col);
      expect(facades.createFacadeWithoutInit<_C1>(regId, 0).v, 11);
      expect(facades.createFacadeForQuery(regId, 0, _C1) as _C1, const _C1(11));

      facades.unregisterFactory(regId);
      expect(facades.hasFactory(regId), isFalse);

      const autoId = ComponentId(9);
      final autoCol = ObjectColumn<_C1>(initialCapacity: 1)..addBlank();
      autoCol.setValue(0, const _C1(42));
      facades.initializeColumn(autoId, autoCol);
      expect(facades.getExtensionType(autoId), Object);
      final autoFacade = facades.createFacadeForQuery(autoId, 0, _C1);
      expect((autoFacade as _C1).v, 42);

      expect(
        () => facades.createFacadeWithoutInit<_C1>(const ComponentId(10), 0),
        throwsA(isA<EcsStateError>()),
      );
    });
  });
}

class _C1 extends Component {
  const _C1(this.v);
  final int v;
}

final class _C1FacadeFactory extends ComponentFacadeFactory<_C1> {
  static late ObjectColumn<_C1> _column;

  @override
  _C1 create(final int index) => _column.getValue(index)!;

  @override
  void initialize(final DataColumn column) {
    _column = column as ObjectColumn<_C1>;
  }
}

final class _C1Factory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => ObjectColumn<_C1>(initialCapacity: initialCapacity);
}

class _C2 extends Component {
  const _C2(this.v);
  final int v;
}

class _C3 extends Component {
  const _C3(this.v);
  final int v;
}

class _R1 extends Resource {
  _R1(this.value);
  final int value;
}

class _TestPlugin extends Plugin {
  _TestPlugin(this.name, this.onInstall, this.onUninstall);

  @override
  final String name;

  final void Function(World world) onInstall;
  final void Function(World world) onUninstall;

  @override
  void install(final World world) => onInstall(world);

  @override
  void uninstall(final World world) => onUninstall(world);
}
