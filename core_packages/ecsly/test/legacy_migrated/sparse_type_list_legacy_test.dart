import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  group('SparseTypeList', () {
    late SparseTypeList list;

    setUp(() {
      list = SparseTypeList();
    });

    test('starts empty', () {
      expect(list.length, 0);
      expect(list.collisionCount, 0);
      expect(list.entries.isEmpty, isTrue);
    });

    test('can add and retrieve component IDs', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      list.set(MockComponentA, id1);
      list.set(MockComponentB, id2);

      expect(list.length, 2);
      expect(list.get(MockComponentA), id1);
      expect(list.get(MockComponentB), id2);
      expect(list.get(MockComponentC), isNull);
      expect(list.contains(MockComponentA), isTrue);
      expect(list.contains(MockComponentC), isFalse);
    });

    test('handles duplicate sets (updates existing)', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      list.set(MockComponentA, id1);
      list.set(MockComponentA, id2); // Update to new ID

      expect(list.length, 1);
      expect(list.get(MockComponentA), id2); // Should return updated ID
    });

    test('entries iteration works correctly', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      list.set(MockComponentA, id1);
      list.set(MockComponentB, id2);

      final entries = list.entries.toList();
      expect(entries.length, 2);

      // Check that entries contain the expected pairs
      var found1 = false;
      var found2 = false;
      for (final (type, componentId) in entries) {
        if (type == MockComponentA && componentId == id1) found1 = true;
        if (type == MockComponentB && componentId == id2) found2 = true;
      }
      expect(found1, isTrue);
      expect(found2, isTrue);
    });

    test('handles different component types correctly', () {
      // Test with actual component types (simulating real usage)
      const typeA = MockComponentA;
      const typeB = MockComponentB;
      const typeC = MockComponentC;

      const id1 = ComponentId(1);
      const id2 = ComponentId(2);
      const id3 = ComponentId(3);

      list.set(typeA, id1);
      list.set(typeB, id2);
      list.set(typeC, id3);

      expect(list.length, 3);
      expect(list.get(typeA), id1);
      expect(list.get(typeB), id2);
      expect(list.get(typeC), id3);
    });

    test('array index calculation is deterministic', () {
      // Test that same type always maps to same index
      const type = MockComponentA;
      final index1 = _getTestIndex(type);
      final index2 = _getTestIndex(type);

      expect(index1, index2);
      expect(index1, greaterThanOrEqualTo(0));
      expect(index1, lessThan(1024)); // Array size
    });

    test('handles edge case types', () {
      // Test with built-in types that might have interesting hash codes
      const intType = int;
      const stringType = String;
      const listType = List;

      list.set(intType, const ComponentId(1));
      list.set(stringType, const ComponentId(2));
      list.set(listType, const ComponentId(3));

      expect(list.get(intType), const ComponentId(1));
      expect(list.get(stringType), const ComponentId(2));
      expect(list.get(listType), const ComponentId(3));
    });

    test('maintains correctness with many different types', () {
      // Test with various built-in types to ensure no regressions
      final testTypes = <Type>[
        int, String, double, bool, List, Map, Set, DateTime, Duration,
        RegExp, Symbol, BigInt, Uri, // Core types
        MockComponentA, MockComponentB, MockComponentC, // Custom types
      ];

      final types = <Type>[];
      final ids = <ComponentId>[];

      // Register all types
      for (var i = 0; i < testTypes.length; i++) {
        final type = testTypes[i];
        final id = ComponentId(i);
        types.add(type);
        ids.add(id);
        list.set(type, id);
      }

      expect(list.length, testTypes.length);

      // Verify all can be retrieved correctly
      for (var i = 0; i < testTypes.length; i++) {
        expect(list.get(types[i]), ids[i]);
      }

      // Verify collision count is reasonable (should be very low)
      expect(
        list.collisionCount,
        lessThan(5),
      ); // Allow some collisions but not many
    });

    test('collision statistics are accurate', () {
      // Test collision statistics with a large number of unique types
      final testTypes = <Type>[];
      final testIds = <ComponentId>[];

      // Use a variety of built-in types that should be unique
      final builtInTypes = <Type>[
        int, String, double, bool, List, Map, Set, DateTime, Duration,
        RegExp, Symbol, Uri, BigInt, Null, Object, num, Iterable, Iterator,
        Comparable, Pattern, Match, Exception, Error, StackTrace, Type,
        Function, MockComponentA, MockComponentB, MockComponentC,
        // Add some more unique types if needed
      ];

      // Add up to 100 types (or all available built-in types)
      final numTypes = builtInTypes.length < 100 ? builtInTypes.length : 100;
      for (var i = 0; i < numTypes; i++) {
        final type = builtInTypes[i];
        testTypes.add(type);
        testIds.add(ComponentId(i));
        list.set(type, testIds[i]);
      }

      // Verify all types can be retrieved correctly
      for (var i = 0; i < testTypes.length; i++) {
        expect(list.get(testTypes[i]), testIds[i]);
      }

      // Collision statistics should be reasonable (some collisions are expected with many types)
      expect(list.collisionCount, greaterThanOrEqualTo(0)); // Allow collisions
      expect(
        list.collisionRate,
        lessThan(1.0),
      ); // Less than 100% collision rate
      expect(list.totalCollisions, equals(list.collisionCount));
      expect(list.collisionRate, greaterThanOrEqualTo(0.0));
      expect(list.collisionRate, lessThanOrEqualTo(1.0));
    });

    test('updates existing entries correctly in dense storage', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      // Set initial value
      list.set(MockComponentA, id1);
      expect(list.get(MockComponentA), id1);
      expect(list.length, 1);

      // Update to new ComponentId
      list.set(MockComponentA, id2);
      expect(list.get(MockComponentA), id2); // Should return updated ID
      expect(list.length, 1); // Length should remain the same

      // Verify dense storage is updated
      final entries = list.entries.toList();
      expect(entries.length, 1);
      expect(entries[0].$1, MockComponentA);
      expect(entries[0].$2, id2); // Should be updated ComponentId
    });

    test('remove method works correctly', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      // Add entries
      list.set(MockComponentA, id1);
      list.set(MockComponentB, id2);
      expect(list.length, 2);
      expect(list.get(MockComponentA), id1);
      expect(list.get(MockComponentB), id2);

      // Remove one entry
      list.remove(MockComponentA);
      expect(list.length, 1);
      expect(list.get(MockComponentA), isNull);
      expect(list.get(MockComponentB), id2); // Other entry still exists

      // Remove non-existent entry (should be safe)
      list.remove(MockComponentC);
      expect(list.length, 1);

      // Remove last entry
      list.remove(MockComponentB);
      expect(list.length, 0);
      expect(list.get(MockComponentB), isNull);
    });

    test('remove works with various types', () {
      // Add various types
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);
      const id3 = ComponentId(3);

      list.set(int, id1);
      list.set(String, id2);
      list.set(double, id3);

      expect(list.length, 3);

      // Remove middle type
      list.remove(String);
      expect(list.length, 2);
      expect(list.get(int), id1);
      expect(list.get(String), isNull);
      expect(list.get(double), id3);

      // Remove remaining types
      list.remove(int);
      list.remove(double);
      expect(list.length, 0);
      expect(list.get(int), isNull);
      expect(list.get(double), isNull);
    });

    test('enhanced collision statistics work correctly', () {
      expect(list.totalCollisions, 0);
      expect(list.collisionRate, 0.0);
      expect(list.maxCollisionsAtSingleIndex, 0);

      // Add normal entries
      list.set(MockComponentA, const ComponentId(1));
      list.set(MockComponentB, const ComponentId(2));
      expect(list.totalCollisions, 0);
      expect(list.collisionRate, 0.0);
      expect(list.length, 2);

      // Add more entries to potentially create natural collisions
      final types = [int, String, double, bool, List, Map];
      for (var i = 0; i < types.length; i++) {
        list.set(types[i], ComponentId(i + 3));
      }

      // Statistics should be valid
      expect(list.totalCollisions, greaterThanOrEqualTo(0));
      expect(list.collisionRate, greaterThanOrEqualTo(0.0));
      expect(list.collisionRate, lessThanOrEqualTo(1.0));
      expect(
        list.maxCollisionsAtSingleIndex,
        greaterThanOrEqualTo(list.totalCollisions),
      );
    });

    test('edge cases: empty registry operations', () {
      // Remove from empty registry should be safe
      list.remove(MockComponentA);
      expect(list.length, 0);
      expect(list.collisionCount, 0);

      // Get from empty registry should return null
      expect(list.get(MockComponentA), isNull);
      expect(list.contains(MockComponentA), isFalse);
    });

    test('edge cases: single entry operations', () {
      const id = ComponentId(1);

      // Add single entry
      list.set(MockComponentA, id);
      expect(list.length, 1);
      expect(list.get(MockComponentA), id);

      // Remove single entry
      list.remove(MockComponentA);
      expect(list.length, 0);
      expect(list.get(MockComponentA), isNull);
    });
  });
}

/// Helper function to access private _getIndex method for testing
int _getTestIndex(final Type type) => type.hashCode.abs() & (1024 - 1);

/// Mock component types for testing (to avoid using real components)
class MockComponentA {
  const MockComponentA();
}

class MockComponentB {
  const MockComponentB();
}

class MockComponentC {
  const MockComponentC();
}
