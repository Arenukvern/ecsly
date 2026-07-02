import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  group('SparseColumnList', () {
    late SparseColumnList list;
    late IntColumn column1;
    late IntColumn column2;
    late IntColumn column3;

    setUp(() {
      list = SparseColumnList();
      column1 = IntColumn();
      column2 = IntColumn();
      column3 = IntColumn();
    });

    test('starts empty', () {
      expect(list.length, 0);
      expect(list.values.isEmpty, isTrue);
      expect(list.entries.isEmpty, isTrue);
    });

    test('can add and retrieve columns', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      list.add(id1, column1);
      list.add(id2, column2);

      expect(list.length, 2);
      expect(list.getColumn(id1), same(column1));
      expect(list.getColumn(id2), same(column2));
      expect(list.getColumn(const ComponentId(3)), isNull);
      expect(list.contains(id1), isTrue);
      expect(list.contains(const ComponentId(3)), isFalse);
    });

    test('handles duplicate adds gracefully', () {
      const id = ComponentId(1);

      list.add(id, column1);
      list.add(id, column2); // Should not add again

      expect(list.length, 1);
      expect(list.getColumn(id), same(column1)); // Original column preserved
    });

    test('can remove columns', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      list.add(id1, column1);
      list.add(id2, column2);

      list.remove(id1);

      expect(list.length, 1);
      expect(list.getColumn(id1), isNull);
      expect(list.getColumn(id2), same(column2));
      expect(list.contains(id1), isFalse);
      expect(list.contains(id2), isTrue);
    });

    test('swap-with-last removal maintains correct mapping', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);
      const id3 = ComponentId(3);

      list.add(id1, column1);
      list.add(id2, column2);
      list.add(id3, column3);

      // Remove middle element (id2)
      list.remove(id2);

      expect(list.length, 2);
      expect(list.getColumn(id1), same(column1));
      expect(list.getColumn(id2), isNull);
      expect(list.getColumn(id3), same(column3));
    });

    test('values iteration works correctly', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      list.add(id1, column1);
      list.add(id2, column2);

      final values = list.values.toList();
      expect(values.length, 2);
      expect(values, contains(column1));
      expect(values, contains(column2));
    });

    test('entries iteration works correctly', () {
      const id1 = ComponentId(1);
      const id2 = ComponentId(2);

      list.add(id1, column1);
      list.add(id2, column2);

      final entries = list.entries.toList();
      expect(entries.length, 2);

      // Check that entries contain the expected pairs
      var found1 = false;
      var found2 = false;
      for (final (id, column) in entries) {
        if (id == id1 && column == column1) found1 = true;
        if (id == id2 && column == column2) found2 = true;
      }
      expect(found1, isTrue);
      expect(found2, isTrue);
    });

    test('rejects invalid component IDs', () {
      const invalidId = ComponentId(999); // > maxValue

      expect(() => list.add(invalidId, column1), throwsArgumentError);
      expect(list.getColumn(invalidId), isNull);
      expect(list.contains(invalidId), isFalse);
      expect(
        () => list.remove(invalidId),
        returnsNormally,
      ); // No-op for invalid
    });
  });
}

// /// Mock column for testing - just an object that implements the basic interface
// class MockColumn implements Column {
//   MockColumn(this.id);
//   final int id;

//   @override
//   int get hashCode => id.hashCode;

//   @override
//   bool operator ==(final Object other) => other is MockColumn && other.id == id;
// }
