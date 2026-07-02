import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

class CounterResource extends Resource {
  CounterResource(this.value);
  final int value;
}

class MarkerResource extends Resource {
  MarkerResource();
}

class LabelResource extends Resource {
  LabelResource(this.label);
  final String label;
}

void main() {
  group('ResourceRegistry semantics', () {
    test(
      'push/remove are deferred and get<T>() auto-flushes resources only',
      () {
        final world = World();

        world.upsertResource(CounterResource(1));
        expect(world.resources.doesNeedFlush, isTrue);

        final resource = world.getResource<CounterResource>();
        expect(resource.value, 1);
        expect(world.resources.doesNeedFlush, isFalse);

        world.removeResource<CounterResource>();
        expect(world.resources.doesNeedFlush, isTrue);
        expect(
          () => world.getResource<CounterResource>(),
          throwsA(isA<StateError>()),
        );
        expect(world.resources.doesNeedFlush, isFalse);
      },
    );

    test('getById returns null for invalid IDs or missing resources', () {
      final world = World();

      expect(
        world.getResourceById<CounterResource>(const ResourceId(-1)),
        isNull,
      );
      expect(
        world.getResourceById<CounterResource>(const ResourceId(999)),
        isNull,
      );

      final id = world.resources.registerResource<CounterResource>();
      expect(world.getResourceById<CounterResource>(id), isNull);

      world.upsertResource(CounterResource(7));
      expect(world.getResourceById<CounterResource>(id)?.value, 7);
    });

    test('has<T>() reflects actual presence after deferred operations', () {
      final world = World();

      expect(world.resources.has<MarkerResource>(), isFalse);
      world.upsertResource(MarkerResource());
      expect(world.resources.has<MarkerResource>(), isTrue);

      world.removeResource<MarkerResource>();
      expect(world.resources.has<MarkerResource>(), isFalse);
    });

    test('addResourceIfAbsent creates once and returns existing resource', () {
      final world = World();
      var creates = 0;

      final created = world.addResourceIfAbsent<CounterResource>(() {
        creates += 1;
        return CounterResource(1);
      });
      final existing = world.addResourceIfAbsent<CounterResource>(() {
        creates += 1;
        return CounterResource(2);
      });

      expect(creates, 1);
      expect(created.value, 1);
      expect(identical(existing, created), isTrue);
      expect(world.getResource<CounterResource>().value, 1);
    });

    test('removing a type frees and reuses ResourceId slots', () {
      final world = World();
      final firstId = world.resources.registerResource<CounterResource>();
      world.upsertResource(CounterResource(1));
      world.flushResourcesOnly();

      world.removeResource<CounterResource>();
      world.flushResourcesOnly();

      final reusedId = world.resources.registerResource<LabelResource>();
      expect(reusedId.value, firstId.value);
    });

    test('iter/iterDense skip null holes without whereType scan semantics', () {
      final world = World();
      world.upsertResource(CounterResource(1));
      world.upsertResource(LabelResource('x'));
      world.flushResourcesOnly();

      world.removeResource<LabelResource>();
      world.flushResourcesOnly();

      final typed = world.resources.iter<CounterResource>().toList();
      expect(typed.length, 1);
      expect(typed.single.value, 1);

      final dense = world.resources.iterDense().toList();
      // World() initializes with system resources; verify user resource present.
      expect(dense.whereType<CounterResource>().length, 1);
      expect(dense.whereType<CounterResource>().single.value, 1);
    });
  });
}
