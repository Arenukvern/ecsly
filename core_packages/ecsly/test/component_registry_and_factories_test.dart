import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

import '_test_components.dart';

class ExtraComponent extends Component {
  const ExtraComponent();
}

class SoAComponent extends Component {
  const SoAComponent();
}

class TagOnlyComponent extends Component {
  const TagOnlyComponent();
}

final class _SoAIntColumnFactory extends ColumnFactory {
  @override
  DataColumn createColumn(
    final ComponentId componentId, {
    final int initialCapacity = 8,
  }) => IntColumn(initialCapacity: initialCapacity);
}

void main() {
  group('ComponentRegistry + factories', () {
    test('registering same object component is idempotent', () {
      final registry = ComponentRegistry();
      final id1 = registry.registerObjectComponent<NameComponent>();
      final id2 = registry.registerObjectComponent<NameComponent>();
      expect(id2, id1);
      expect(registry.getComponentId<NameComponent>(), id1);
    });

    test('createColumnFor throws for unregistered type', () {
      final registry = ComponentRegistry();
      expect(
        () => registry.createColumnFor(ExtraComponent),
        throwsA(isA<ComponentNotRegisteredError>()),
      );
    });

    test('createColumnFor returns correct column type after registration', () {
      final registry = ComponentRegistry();
      registry.registerObjectComponent<NameComponent>();
      final column = registry.createColumnFor(NameComponent);
      expect(column, isA<ObjectColumn<NameComponent>>());
    });

    test(
      'registerSoA/registerObject track storage tier and reject mismatch',
      () {
        final registry = ComponentRegistry();
        final soaId = registry.registerSoAComponent<SoAComponent>(
          columnFactory: _SoAIntColumnFactory(),
        );
        final objectId = registry.registerObjectComponent<NameComponent>();

        expect(registry.getStorageTier(soaId), ComponentStorageTier.soa);
        expect(registry.getStorageTier(objectId), ComponentStorageTier.object);
        expect(registry.isObjectComponent(objectId), isTrue);
        expect(registry.isObjectComponent(soaId), isFalse);

        expect(
          () => registry.registerObjectComponent<SoAComponent>(),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('registerTagComponent uses compact SoA storage', () {
      final registry = ComponentRegistry();
      final tagId = registry.registerTagComponent<TagOnlyComponent>();

      expect(registry.getStorageTier(tagId), ComponentStorageTier.soa);
      expect(registry.isObjectComponent(tagId), isFalse);
      expect(registry.createColumnFor(TagOnlyComponent), isA<Uint8Column>());
    });

    test('extension registration wiring supports typed facade queries', () {
      final world = buildTestWorld();
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromExtensionList(const [
          (PositionComponent, Position),
          (HealthComponent, Health),
        ]),
      );

      final rows = world
          .queryExt2<PositionComponent, Position, HealthComponent, Health>()
          .toList();

      expect(rows.length, 1);
      final (_, pos, hp) = rows.single;
      pos.x = 11;
      hp.value = 7;
      expect(pos.x, 11);
      expect(hp.value, 7);
    });

    test('extension type mismatch throws expected error', () {
      final world = buildTestWorld();
      final e = world.reserveEmptyEntity().entity;
      world.spawnBundle(
        e,
        ComponentBundle.fromExtensionList(const [
          (PositionComponent, Position),
        ]),
      );

      expect(
        () => world.queryExt<PositionComponent, String>().toList(),
        throwsA(anyOf(isA<ExtensionTypeMismatchError>(), isA<TypeError>())),
      );
    });
  });
}
