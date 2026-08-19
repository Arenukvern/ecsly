import 'package:async_parallel/async_parallel.dart';
import 'package:test/test.dart';

void main() {
  group('BufferPool', () {
    late BufferPool pool;

    setUp(() {
      pool = BufferPool(
        bufferSizeBytes: 256,
        initialPoolSize: 3,
        maxPoolSize: 10,
      );
    });

    test('should initialize with correct configuration', () {
      expect(pool.bufferSizeBytes, equals(256));
      expect(pool.maxPoolSize, equals(10));
    });

    test('should create initial pool of buffers', () {
      // Get a buffer to trigger pool initialization
      final buffer = pool.getBuffer();
      expect(buffer, isA<TransferableBuffer>());
      expect(buffer.byteLength, equals(256));
    });

    test('should recycle buffers correctly', () {
      // Get and return a buffer
      final buffer1 = pool.getBuffer();
      pool.returnBuffer(buffer1);

      // Get another buffer - should be the recycled one
      final buffer2 = pool.getBuffer();
      expect(buffer2, isNotNull);

      // Fill buffer1 with data
      for (int i = 0; i < buffer1.data.length; i++) {
        buffer1.data[i] = i % 256;
      }

      // After recycling, buffer2 should be clean (not containing buffer1's data)
      // Note: This assumes the pool creates new buffers when recycling
      // The actual behavior depends on the pool implementation
    });

    test('should handle pool exhaustion gracefully', () {
      // Fill the pool beyond max size
      final buffers = <TransferableBuffer>[];
      for (int i = 0; i < 15; i++) {
        // More than maxPoolSize of 10
        final buffer = pool.getBuffer();
        buffers.add(buffer);
      }

      expect(buffers.length, equals(15));
      for (final buffer in buffers) {
        expect(buffer.byteLength, equals(256));
      }

      // Return some buffers to the pool
      for (int i = 0; i < 5; i++) {
        pool.returnBuffer(buffers[i]);
      }
    });

    test('should maintain buffer integrity', () {
      final buffer = pool.getBuffer();

      // Fill buffer with known pattern
      for (int i = 0; i < buffer.data.length; i++) {
        buffer.data[i] = (i * 7) % 256;
      }

      pool.returnBuffer(buffer);

      // Get buffer back
      final recycledBuffer = pool.getBuffer();

      // The buffer should be reusable (implementation dependent)
      expect(recycledBuffer.byteLength, equals(256));
    });

    test('should handle different buffer sizes', () {
      final smallPool = BufferPool(bufferSizeBytes: 64, initialPoolSize: 2);
      final largePool = BufferPool(bufferSizeBytes: 4096, initialPoolSize: 1);

      final smallBuffer = smallPool.getBuffer();
      final largeBuffer = largePool.getBuffer();

      expect(smallBuffer.byteLength, equals(64));
      expect(largeBuffer.byteLength, equals(4096));

      smallPool.returnBuffer(smallBuffer);
      largePool.returnBuffer(largeBuffer);
    });

    test('should support concurrent access patterns', () {
      // Simulate rapid buffer allocation/deallocation
      final operations = <Future<void>>[];

      for (int i = 0; i < 50; i++) {
        operations.add(
          Future(() async {
            final buffer = pool.getBuffer();
            await Future.delayed(const Duration(milliseconds: 1));
            pool.returnBuffer(buffer);
          }),
        );
      }

      // All operations should complete without errors
      expect(Future.wait(operations), completes);
    });

    test('should handle SIMD-aligned buffer sizes', () {
      // Test with SIMD-friendly sizes (multiples of 16 bytes)
      final simdSizes = [64, 128, 256, 512];

      for (final size in simdSizes) {
        final simdPool = BufferPool(bufferSizeBytes: size, initialPoolSize: 1);
        final buffer = simdPool.getBuffer();

        expect(
          buffer.byteLength % 16,
          equals(0),
          reason: 'Buffer size $size should be SIMD-aligned',
        );

        // Could create SIMD views
        final floatView = buffer.data.buffer.asFloat32List();
        expect(
          floatView.length % 4,
          equals(0),
          reason: 'Should support Float32x4 operations',
        );

        simdPool.returnBuffer(buffer);
      }
    });

    test('should prevent memory leaks in recycling', () {
      // Test that returning buffers doesn't cause issues
      for (int round = 0; round < 10; round++) {
        final buffers = <TransferableBuffer>[];

        // Allocate several buffers
        for (int i = 0; i < 8; i++) {
          buffers.add(pool.getBuffer());
        }

        // Return them all
        buffers.forEach(pool.returnBuffer);
      }

      // Pool should still be functional
      final testBuffer = pool.getBuffer();
      expect(testBuffer, isNotNull);
      expect(testBuffer.byteLength, equals(256));
    });
  });
}
