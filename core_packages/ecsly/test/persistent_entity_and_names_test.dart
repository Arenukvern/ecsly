import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

class _Probe extends Component {
  const _Probe();
}

class _Other extends Component {
  const _Other();
}

void main() {
  group('PersistentEntity', () {
    test('sequence identities encode decimal, reversibly', () {
      final identity = PersistentEntity.sequence(42);
      expect(identity.value, '42');
      expect(identity.sequenceValue, 42);
      expect(identity.namespace, isNull);
      expect(identity.isZero, isFalse);
      expect(PersistentEntity.fromJson('42'), identity);
    });

    test('namespaced identities compose and reject bad namespaces', () {
      final identity = PersistentEntity.sequence(9, namespace: 'shard-1');
      expect(identity.value, 'shard-1:9');
      expect(identity.namespace, 'shard-1');
      expect(identity.sequenceValue, isNull);
      expect(
        () => PersistentEntity.sequence(1, namespace: 'bad:name'),
        throwsArgumentError,
      );
      expect(
        () => PersistentEntity.sequence(1, namespace: ''),
        throwsArgumentError,
      );
      expect(() => PersistentEntity.sequence(-1), throwsArgumentError);
    });

    test('zero is the null identity', () {
      expect(PersistentEntity.zero.value, '');
      expect(PersistentEntity.zero.isZero, isTrue);
      expect(PersistentEntity.zero.sequenceValue, isNull);
    });

    test('random identities are unique, colon-free, unparseable', () {
      final seen = <String>{};
      for (var i = 0; i < 100; i++) {
        final identity = PersistentEntity.create();
        expect(identity.isZero, isFalse);
        expect(identity.value, isNot(contains(':')));
        expect(identity.sequenceValue, isNull);
        seen.add(identity.value);
      }
      expect(seen.length, 100);
    });

    test('fromJson accepts ints for pre-v4 payloads', () {
      expect(PersistentEntity.fromJson(5).value, '5');
      expect(() => PersistentEntity.fromJson(1.5), throwsArgumentError);
      expect(() => PersistentEntity.fromJson(null), throwsArgumentError);
    });
  });

  group('component stable names', () {
    test('nameOf and componentIdByName round-trip', () {
      final world = World();
      world.components.registerObjectComponent<_Probe>(
        name: 'probe.probe',
        sample: const _Probe(),
      );
      final id = world.components.getComponentId<_Probe>();
      expect(world.components.nameOf(id), 'probe.probe');
      expect(world.components.componentIdByName('probe.probe'), id);
      expect(world.components.nameOf(id) == '_Probe', isFalse);
    });

    test('unnamed components have null names', () {
      final world = World();
      world.components.registerObjectComponent<_Other>(sample: const _Other());
      final id = world.components.getComponentId<_Other>();
      expect(world.components.nameOf(id), isNull);
      expect(world.components.componentIdByName('_Other'), isNull);
    });

    test('duplicate names are rejected loudly', () {
      final world = World();
      world.components.registerObjectComponent<_Probe>(
        name: 'dup.name',
        sample: const _Probe(),
      );
      expect(
        () => world.components.registerObjectComponent<_Other>(
          name: 'dup.name',
          sample: const _Other(),
        ),
        throwsStateError,
      );
    });

    test('re-registering the same type keeps its name', () {
      final world = World();
      world.components.registerObjectComponent<_Probe>(
        name: 'probe.probe',
        sample: const _Probe(),
      );
      final idAgain = world.components.registerObjectComponent<_Probe>(
        name: 'probe.probe',
        sample: const _Probe(),
      );
      expect(world.components.nameOf(idAgain), 'probe.probe');
    });
  });
}
