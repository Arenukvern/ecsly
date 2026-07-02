import 'package:ecsly/src/archetypes/archetype.dart';
import 'package:ecsly/src/entities/entities.dart';
import 'package:test/test.dart';

void main() {
  group('Entities', () {
    test('create/destroy updates count and generations', () {
      final entities = Entities();

      final e1 = entities.create();
      final e2 = entities.create();
      expect(entities.count, 2);
      expect(entities.isAlive(e1), isTrue);
      expect(entities.isAlive(e2), isTrue);

      entities.destroy(e1);
      expect(entities.count, 1);
      expect(entities.isAlive(e1), isFalse);

      final reused = entities.create();
      expect(entities.count, 2);

      // ID reuse happens via free-list: index should be recycled, generation bumped.
      expect(reused.indexValue, e1.indexValue);
      expect(reused.generation, greaterThan(e1.generation));
      expect(entities.isAlive(reused), isTrue);
      expect(entities.isAlive(e1), isFalse); // stale handle stays invalid
    });

    test('location defaults to null/empty archetype and resets on reuse', () {
      final entities = Entities();

      final e1 = entities.create();
      final loc1 = entities.getLocation(e1);
      expect(loc1.archetypeId.value, 0);
      expect(loc1.archetypeRow, 0);

      // Mutate location and ensure it is reset on reuse.
      entities.setLocation(e1, const EntityLocation(ArchetypeId(123), 77));
      expect(entities.getLocation(e1).archetypeId.value, 123);

      entities.destroy(e1);
      final reused = entities.create();
      final loc2 = entities.getLocation(reused);
      expect(loc2.archetypeId.value, 0);
      expect(loc2.archetypeRow, 0);
    });
  });
}
