import 'dart:typed_data';

import 'package:ecs_async_parallel/ecs_async_parallel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DoubleBuffer', () {
    late DoubleBuffer doubleBuffer;

    setUp(() {
      doubleBuffer = DoubleBuffer(512); // 512 bytes per buffer
    });

    test('should initialize with two buffers', () {
      expect(doubleBuffer.readBuffer.byteLength, equals(512));
      expect(doubleBuffer.writeBuffer.byteLength, equals(512));
    });

    test('should create from existing buffers', () {
      final bufferA = Float32List(64);
      final bufferB = Float32List(64);

      // Fill with test data
      for (int i = 0; i < bufferA.length; i++) {
        bufferA[i] = i * 1.0;
        bufferB[i] = i * 2.0;
      }

      final doubleBuffer = DoubleBuffer.fromBuffers(bufferA, bufferB);

      expect(doubleBuffer.readBuffer.byteLength, equals(bufferA.lengthInBytes));
      expect(
        doubleBuffer.writeBuffer.byteLength,
        equals(bufferB.lengthInBytes),
      );
    });

    test('swap should exchange read and write buffers', () {
      // Fill write buffer with known data
      final writeData = doubleBuffer.writeBuffer.data;
      for (int i = 0; i < writeData.length; i++) {
        writeData[i] = i;
      }

      // Mark current state
      final originalReadData = List<int>.from(doubleBuffer.readBuffer.data);
      final originalWriteData = List<int>.from(doubleBuffer.writeBuffer.data);

      // Swap buffers
      doubleBuffer.swap();

      // Verify swap occurred
      for (int i = 0; i < writeData.length; i++) {
        expect(doubleBuffer.readBuffer.data[i], equals(originalWriteData[i]));
        expect(doubleBuffer.writeBuffer.data[i], equals(originalReadData[i]));
      }
    });

    test('multiple swaps should work correctly', () {
      // Initial state
      doubleBuffer.readBuffer.data[0] = 1;
      doubleBuffer.writeBuffer.data[0] = 2;

      expect(doubleBuffer.readBuffer.data[0], equals(1));
      expect(doubleBuffer.writeBuffer.data[0], equals(2));

      // First swap
      doubleBuffer.swap();
      expect(doubleBuffer.readBuffer.data[0], equals(2));
      expect(doubleBuffer.writeBuffer.data[0], equals(1));

      // Second swap - back to original
      doubleBuffer.swap();
      expect(doubleBuffer.readBuffer.data[0], equals(1));
      expect(doubleBuffer.writeBuffer.data[0], equals(2));
    });

    test('should maintain buffer integrity during swap', () {
      // Fill both buffers with different patterns
      for (int i = 0; i < doubleBuffer.readBuffer.data.length; i++) {
        doubleBuffer.readBuffer.data[i] = i * 10;
        doubleBuffer.writeBuffer.data[i] = i * 20;
      }

      final originalReadSum = doubleBuffer.readBuffer.data.reduce(
        (final a, final b) => a + b,
      );
      final originalWriteSum = doubleBuffer.writeBuffer.data.reduce(
        (final a, final b) => a + b,
      );

      doubleBuffer.swap();

      // After swap, the sums should be exchanged
      expect(
        doubleBuffer.readBuffer.data.reduce((final a, final b) => a + b),
        equals(originalWriteSum),
      );
      expect(
        doubleBuffer.writeBuffer.data.reduce((final a, final b) => a + b),
        equals(originalReadSum),
      );
    });

    test('should handle TypedData views correctly', () {
      final floatBuffer = DoubleBuffer(256); // 64 floats

      // Access as Float32List views
      final writeFloats = floatBuffer.writeBuffer.data.buffer.asFloat32List();

      // Fill write buffer with float data
      for (int i = 0; i < writeFloats.length; i++) {
        writeFloats[i] = i * 3.14;
      }

      floatBuffer.swap();

      // After swap, read buffer should contain the float data
      final swappedFloats = floatBuffer.readBuffer.data.buffer.asFloat32List();
      for (int i = 0; i < writeFloats.length; i++) {
        expect(swappedFloats[i], equals(writeFloats[i]));
      }
    });

    test('should handle different buffer sizes', () {
      final smallBuffer = DoubleBuffer(64);
      final largeBuffer = DoubleBuffer(4096);

      expect(smallBuffer.readBuffer.byteLength, equals(64));
      expect(largeBuffer.readBuffer.byteLength, equals(4096));
    });

    test('should be thread-safe for buffer access', () {
      // Test that buffer access doesn't interfere with swap operations
      final buffer = DoubleBuffer(128);

      // Simulate concurrent access patterns
      buffer.readBuffer.data[0] = 42;
      buffer.writeBuffer.data[0] = 84;

      // Swap should be atomic operation
      buffer.swap();

      expect(buffer.readBuffer.data[0], equals(84));
      expect(buffer.writeBuffer.data[0], equals(42));
    });
  });
}
