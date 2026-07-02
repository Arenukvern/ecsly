import 'dart:typed_data';

import 'package:ecsly/ecsly.dart';
import 'package:test/test.dart';

void main() {
  group('deterministic extraction helpers', () {
    test(
      'deterministicSortedIndices follows primary-secondary-tertiary-tie',
      () {
        final primary = [1, 0, 0, 1, 0];
        final secondary = [5, 3, 3, 1, 3];
        final tertiary = [0, 7, 2, 2, 2];
        final tie = [2, 8, 1, 4, 3];

        final order = deterministicSortedIndices(
          primary.length,
          primary: (final i) => primary[i],
          secondary: (final i) => secondary[i],
          tertiary: (final i) => tertiary[i],
          tieBreaker: (final i) => tie[i],
        );

        expect(order, equals([2, 4, 1, 3, 0]));
      },
    );

    test('section hashing is deterministic for same payload', () {
      final a = Float32List.fromList([1, 2, 3, 4]);
      final b = Float32List.fromList([1, 2, 3, 4]);
      expect(
        DeterministicSectionHashing.hashFloat32Section(a, a.length),
        DeterministicSectionHashing.hashFloat32Section(b, b.length),
      );
    });

    test('section hashing changes when order changes', () {
      final a = Int32List.fromList([1, 2, 3, 4]);
      final b = Int32List.fromList([1, 3, 2, 4]);
      expect(
        DeterministicSectionHashing.hashInt32Section(a, a.length),
        isNot(DeterministicSectionHashing.hashInt32Section(b, b.length)),
      );
    });

    test('world determinism resource stores frame diagnostics', () {
      final resource = WorldDeterminismResource(
        frameId: 7,
        worldHash64: 11,
        packetHash64: 13,
        orderViolationCount: 2,
        sectionHashes64: [1, 2, 3],
      );

      expect(resource.frameId, 7);
      expect(resource.worldHash64, 11);
      expect(resource.packetHash64, 13);
      expect(resource.orderViolationCount, 2);
      expect(resource.sectionHashes64, [1, 2, 3]);
    });
  });
}
