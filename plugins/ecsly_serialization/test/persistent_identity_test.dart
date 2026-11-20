import 'package:ecsly/ecsly.dart';
import 'package:ecsly_serialization/ecsly_serialization.dart';
import 'package:test/test.dart';

import 'serialization_test_components.dart';

class RefComponent extends Component {
  const RefComponent(this.target);
  final Entity target;
}

/// Codec for [RefComponent] — the reference-aware codec contract demo.
class RefCodec extends ObjectComponentCodec<RefComponent> {
  const RefCodec();

  @override
  Object? toJson(RefComponent component, EntityRefEncoder refs) =>
      refs.encode(component.target);

  @override
  RefComponent fromJson(Object? value, EntityRefResolver refs) =>
      RefComponent(refs.resolve(value));
}

class GadgetComponent extends Component {
  const GadgetComponent(this.label);
  final String label;
}

class GadgetCodec extends ObjectComponentCodec<GadgetComponent> {
  const GadgetCodec();

  @override
  Object? toJson(GadgetComponent component, EntityRefEncoder refs) =>
      component.label;

  @override
  GadgetComponent fromJson(Object? value, EntityRefResolver refs) =>
      GadgetComponent(value as String? ?? '');
}

void main() {
  group('PersistentEntity value type', () {
    test('sequence encodes decimal and parses back', () {
      final identity = PersistentEntity.sequence(42);
      expect(identity.value, '42');
      expect(identity.sequenceValue, 42);
      expect(identity.namespace, isNull);
      expect(PersistentEntity.fromJson('42'), identity);
    });

    test('sequence accepts namespaces and rejects bad ones', () {
      final identity = PersistentEntity.sequence(7, namespace: 'shard-3');
      expect(identity.value, 'shard-3:7');
      expect(identity.namespace, 'shard-3');
      expect(identity.sequenceValue, isNull);
      expect(
        () => PersistentEntity.sequence(1, namespace: 'a:b'),
        throwsArgumentError,
      );
      expect(
        () => PersistentEntity.sequence(1, namespace: ''),
        throwsArgumentError,
      );
      expect(
        () => PersistentEntity.sequence(-1),
        throwsArgumentError,
      );
    });

    test('zero is the null identity and random ids never parse', () {
      expect(PersistentEntity.zero.isZero, isTrue);
      final random = PersistentEntity.create();
      expect(random.isZero, isFalse);
      expect(random.sequenceValue, isNull);
      expect(random.value, isNot(contains(':')));
      // Value equality through the erased String representation.
      expect(PersistentEntity.fromJson(random.value), random);
    });
  });

  group('allocators', () {
    test('sequence allocator is deterministic and adoptable', () {
      final allocator = SequencePersistentEntityAllocator();
      expect(allocator.next().value, '1');
      expect(allocator.next().value, '2');

      allocator.adoptMax([
        PersistentEntity.sequence(10),
        PersistentEntity.sequence(3),
        PersistentEntity.create(),
        PersistentEntity.zero,
      ]);
      expect(allocator.next().value, '11');
    });

    test('allocator state round-trips through a snapshot payload', () {
      final allocator = SequencePersistentEntityAllocator();
      allocator.next();
      allocator.next();

      final restored = SequencePersistentEntityAllocator()
        ..restoreState(allocator.snapshotState());
      expect(restored.next().value, '3');

      // Random allocator state is empty but stable.
      const random = RandomPersistentEntityAllocator();
      expect(random.mode, 'random');
      random.restoreState(random.snapshotState());
      expect(random.snapshotState()['mode'], 'random');
    });
  });

  group('spawnPersistent + manageIds', () {
    World pluginWorld() =>
        buildSerializationTestWorld()
          ..addPlugin(const SerializationPlugin(manageIds: true));

    test('spawnPersistent allocates through the installed allocator', () {
      final world = pluginWorld();
      final a = world.spawnPersistent([const PositionComponent()]);
      final b = world.spawnPersistent([const PositionComponent()]);
      world.flush();

      expect(persistentEntityOf(world, a)!.value, '1');
      expect(persistentEntityOf(world, b)!.value, '2');
      expect(
        world.getResource<PersistentEntityIndex>().lookup(
              PersistentEntity.sequence(1),
            ),
        a,
      );
    });

    test('spawnPersistent throws without an allocator', () {
      final world = World();
      expect(
        () => world.spawnPersistent([const PositionComponent()]),
        throwsStateError,
      );
    });

    test('plugin uninstall removes the identity layer', () {
      final world = pluginWorld();
      world.removePlugin('ecsly_serialization');
      expect(
        world.maybeGetResource<PersistentEntityAllocatorResource>(),
        isNull,
      );
      expect(world.maybeGetResource<PersistentEntityIndex>(), isNull);
    });
  });

  group('reference-aware codecs', () {
    World buildWorld() {
      final world = buildSerializationTestWorld();
      registerPersistentEntity(world);
      world.upsertResource(
        PersistentEntityAllocatorResource(SequencePersistentEntityAllocator()),
      );
      world.components.registerObjectComponent<RefComponent>(
        sample: const RefComponent(Entity.nullEntity),
      );
      world.components.registerObjectComponent<GadgetComponent>(
        sample: const GadgetComponent(''),
      );
      return world;
    }

    ObjectComponentCodecRegistry buildCodecs() =>
        ObjectComponentCodecRegistry()
          ..register(const RefCodec())
          ..register(const GadgetCodec());

    test('references travel as identities and resolve on restore', () {
      final codecs = buildCodecs();
      final options = WorldSnapshotOptions(codecs: codecs);

      final source = buildWorld();
      final gadget = source.spawnPersistent([const GadgetComponent('gear')]);
      final holder = source.spawnPersistent([
        RefComponent(gadget),
      ]);
      source.flush();

      final snapshot = captureWorldSnapshot(source, options: options);
      // The payload carries the identity string, not a runtime handle.
      expect(snapshot.entities.map((e) => e.identity), contains('2'));

      final target = buildWorld();
      final mapping = restoreWorldSnapshot(
        target,
        snapshot,
        options: options,
        resourceRegistry: SnapshotResourceRegistry(),
      );
      expect(mapping.length, 2);

      // The restored reference points at the live gadget entity.
      final holderEntity = mapping['2']!;
      final ref = target
          .getEntity(holderEntity)
          .$1
          .get<RefComponent>()!
          .target;
      expect(persistentEntityOf(target, ref)!.value, '1');
    });

    test('a reference to a non-persisted entity throws at capture', () {
      final codecs = buildCodecs();
      final options = WorldSnapshotOptions(codecs: codecs);
      final world = buildWorld();
      world.spawnPersistent([const GadgetComponent('gear')]);
      final transient = world.spawnComponents([const PositionComponent()]);
      world.spawnPersistent([RefComponent(transient)]);
      world.flush();

      expect(
        () => captureWorldSnapshot(world, options: options),
        throwsStateError,
      );
    });
  });

  group('v3 compatibility', () {
    test('pre-v4 int identities normalize on decode', () {
      final legacy = <String, Object?>{
        'version': 3,
        'schemaVersion': 1,
        'componentIds': <String, Object?>{},
        'resources': <String, Object?>{},
        'entities': <Object?>[
          <String, Object?>{
            'persistentId': 5,
            'components': <Object?>[],
            'columns': <String, Object?>{},
          },
          <String, Object?>{
            'persistentId': '7',
            'components': <Object?>[],
            'columns': <String, Object?>{},
          },
        ],
      };
      final snapshot = WorldSnapshot.fromJson(legacy);
      expect(snapshot.entities[0].identity, '5');
      expect(snapshot.entities[1].identity, '7');
    });

    test('a v3 snapshot restores into a v4 world', () {
      final source = buildSerializationTestWorld();
      registerPersistentEntity(source);
      source.spawnComponents([
        PersistentEntityComponent(PersistentEntity.sequence(4)),
        const PositionComponent(),
      ]);
      source.flush();
      final raw = captureWorldSnapshot(source).toJson();

      // Downgrade the envelope to the v3 wire form.
      final legacy = <String, Object?>{...raw, 'version': 3};
      final entities = (legacy['entities']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((e) => <String, Object?>{
            ...e,
            'persistentId': int.parse(e['identity']! as String),
          }.remove('identity') == null
              ? <String, Object?>{
                'persistentId': int.parse(e['identity']! as String),
                'components': e['components'],
                'columns': e['columns'],
              }
              : e)
          .toList();
      legacy['entities'] = entities;

      final target = buildSerializationTestWorld();
      registerPersistentEntity(target);
      final mapping = restoreWorldSnapshot(target, WorldSnapshot.fromJson(legacy));
      expect(mapping.length, 1);
      expect(mapping.keys.first, '4');
      expect(persistentEntityOf(target, mapping['4']!)!.value, '4');
    });
  });

  group('named registration', () {
    test('snapshots prefer registered component names', () {
      final world = World();
      registerPersistentEntity(world);
      world.upsertResource(
        PersistentEntityAllocatorResource(SequencePersistentEntityAllocator()),
      );
      world.components.registerObjectComponent<GadgetComponent>(
        name: 'gadget.cool_gadget',
        sample: const GadgetComponent(''),
      );
      world.spawnPersistent([const GadgetComponent('x')]);
      world.flush();

      final options = WorldSnapshotOptions(
        codecs: ObjectComponentCodecRegistry()..register(const GadgetCodec()),
      );
      final snapshot = captureWorldSnapshot(world, options: options);
      expect(snapshot.componentIds.containsKey('gadget.cool_gadget'), isTrue);

      // Restore resolves through the stable name even if the class is
      // registered under a different local name layout.
      final target = World();
      registerPersistentEntity(target);
      target.components.registerObjectComponent<GadgetComponent>(
        name: 'gadget.cool_gadget',
        sample: const GadgetComponent(''),
      );
      final mapping = restoreWorldSnapshot(target, snapshot, options: options);
      expect(mapping.length, 1);
    });

    test('duplicate stable names are rejected', () {
      final world = World();
      world.components.registerObjectComponent<GadgetComponent>(
        name: 'gadget.thing',
        sample: const GadgetComponent(''),
      );
      expect(
        () => world.components.registerObjectComponent<PositionComponent>(
          name: 'gadget.thing',
        ),
        throwsStateError,
      );
    });
  });

  group('index + auto-adopt', () {
    test('restore grows the allocator past live entities on partial reconcile',
        () {
      // World A: identities 1..3. World B (same): reconcile with a snapshot
      // that only contains identity 1, keeping 2 and 3 alive. The allocator
      // must mint 4 next — adopt covers LIVE entities, not just the mapping.
      World build() {
        final world = buildSerializationTestWorld()
          ..addPlugin(const SerializationPlugin(manageIds: true));
        for (var i = 0; i < 3; i++) {
          world.spawnPersistent([const PositionComponent()]);
        }
        world.flush();
        return world;
      }

      final source = build();
      final full = captureWorldSnapshot(source);
      final partial = WorldSnapshot(
        version: full.version,
        schemaVersion: full.schemaVersion,
        componentIds: full.componentIds,
        resources: full.resources,
        entities: full.entities.take(1).toList(),
      );

      final target = build();
      reconcileWorldSnapshot(target, partial, despawnAbsent: false);

      final minted = target.spawnPersistent([const PositionComponent()]);
      target.flush();
      expect(persistentEntityOf(target, minted)!.value, '4');
    });

    test('allocator snapshot state restores through resource snapshot', () {
      final world = buildSerializationTestWorld()
        ..addPlugin(const SerializationPlugin(manageIds: true));
      world.spawnPersistent([const PositionComponent()]);
      world.spawnPersistent([const PositionComponent()]);
      world.flush();

      final snapshot = captureWorldSnapshot(world);
      expect(snapshot.resources['PersistentEntityAllocatorResource'], {
        'mode': 'sequence',
        'next': 3,
      });

      final target = buildSerializationTestWorld()
        ..addPlugin(const SerializationPlugin(manageIds: true));
      restoreWorldSnapshot(target, snapshot);
      final minted = target.spawnPersistent([const PositionComponent()]);
      target.flush();
      expect(persistentEntityOf(target, minted)!.value, '3');
    });
  });
}
