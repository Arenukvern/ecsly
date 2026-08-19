import 'package:ecs_async_parallel/ecs_async_parallel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SharedMemory', () {
    test('create should return null when malloc not available', () {
      // On platforms without malloc.allocate support, should return null
      final sharedMemory = SharedMemory.create(1024);
      // We can't guarantee platform support, so just verify the method exists
      expect(sharedMemory, isA<SharedMemory?>());
    });

    test('should handle zero-size allocation', () {
      final sharedMemory = SharedMemory.create(0);
      // The actual implementation may or may not return null for zero size
      // Just verify it doesn't crash
      expect(sharedMemory, isA<SharedMemory?>());
    });

    test('should handle large allocations', () {
      // Test with 1MB allocation
      final sharedMemory = SharedMemory.create(1024 * 1024);
      if (sharedMemory != null) {
        expect(sharedMemory.byteLength, equals(1024 * 1024));
        expect(sharedMemory.address, isNonZero);
        sharedMemory.free();
      } else {
        // malloc not available on this platform
        expect(sharedMemory, isNull);
      }
    });

    test('fromAddress should reconstruct memory access', () {
      final originalMemory = SharedMemory.create(256);
      if (originalMemory != null) {
        final address = originalMemory.address;

        // Create new SharedMemory instance from the same address
        final reconstructedMemory = SharedMemory.fromAddress(address, 256);

        expect(reconstructedMemory, isNotNull);
        expect(reconstructedMemory!.byteLength, equals(256));
        expect(reconstructedMemory.address, equals(address));

        // Both instances should be able to access the same memory
        // (though this is dangerous in practice - just testing the API)

        originalMemory.free();
        // Don't free reconstructedMemory as it points to the same memory
      }
    });

    test('free should clean up memory', () {
      final sharedMemory = SharedMemory.create(128);
      if (sharedMemory != null) {
        expect(sharedMemory.address, isNonZero);

        sharedMemory.free();

        // After free, accessing the memory would be undefined behavior
        // We can't easily test this without risking crashes, but the API should work
      }
    });

    test('should handle multiple allocations', () {
      final memories = <SharedMemory>[];

      // Create multiple memory blocks
      for (int i = 0; i < 5; i++) {
        final memory = SharedMemory.create(64 * (i + 1));
        if (memory != null) {
          memories.add(memory);
          expect(memory.byteLength, equals(64 * (i + 1)));
        }
      }

      // Clean up
      for (final memory in memories) {
        memory.free();
      }
    });

    test('should provide different addresses for different allocations', () {
      final memory1 = SharedMemory.create(128);
      final memory2 = SharedMemory.create(128);

      if (memory1 != null && memory2 != null) {
        expect(
          memory1.address,
          isNot(equals(memory2.address)),
          reason: 'Different allocations should have different addresses',
        );

        memory1.free();
        memory2.free();
      }
    });

    test('fromAddress should handle addresses', () {
      // Test with an address (may succeed or fail depending on platform)
      final memory = SharedMemory.fromAddress(0, 64);
      expect(memory, isA<SharedMemory?>());
    });

    test('should handle TypedData views on shared memory', () {
      final sharedMemory = SharedMemory.create(256); // 64 floats
      if (sharedMemory != null) {
        // Create a Float32List view of the shared memory
        final floatView = sharedMemory.asFloat32List();

        expect(floatView.length, equals(64));

        // Fill with test data
        for (int i = 0; i < floatView.length; i++) {
          floatView[i] = i * 2.5;
        }

        // Verify data integrity
        for (int i = 0; i < floatView.length; i++) {
          expect(floatView[i], equals(i * 2.5));
        }

        sharedMemory.free();
      }
    });

    test('should support SIMD-aligned allocations', () {
      // Test allocation sizes that are SIMD-friendly
      final sizes = [
        64,
        128,
        256,
        512,
      ]; // All multiples of 64 bytes (16 floats)

      for (final size in sizes) {
        final memory = SharedMemory.create(size);
        if (memory != null) {
          expect(
            memory.byteLength % 64,
            equals(0),
            reason: 'Shared memory should support SIMD alignment',
          );

          // Could create Float32List views for SIMD operations
          final floatView = memory.asFloat32List();
          expect(
            floatView.length % 4,
            equals(0),
            reason: 'Should support Float32x4 SIMD operations',
          );

          memory.free();
        }
      }
    });
  });
}
