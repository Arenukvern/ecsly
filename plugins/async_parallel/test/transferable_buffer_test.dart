import 'dart:isolate';
import 'dart:typed_data';

import 'package:async_parallel/async_parallel.dart';
import 'package:test/test.dart';

void main() {
  group('TransferableBuffer', () {
    late TransferableBuffer buffer;

    setUp(() {
      buffer = TransferableBuffer(1024); // 1KB buffer
    });

    test('should create buffer with correct size', () {
      expect(buffer.byteLength, equals(1024));
      expect(buffer.data.lengthInBytes, equals(1024));
    });

    test('should create buffer from existing TypedData', () {
      final originalData = Float32List(100);
      for (int i = 0; i < originalData.length; i++) {
        originalData[i] = i * 1.5;
      }

      final buffer = TransferableBuffer.fromTypedData(originalData);
      expect(buffer.byteLength, equals(originalData.lengthInBytes));
      expect(buffer.data, isNot(same(originalData.buffer.asUint8List())));

      // Verify data was copied
      final copiedFloats = buffer.data.buffer.asFloat32List();
      for (int i = 0; i < originalData.length; i++) {
        expect(copiedFloats[i], equals(originalData[i]));
      }
    });

    test('should maintain SIMD compatibility', () {
      // Test with SIMD-aligned buffer (multiple of 16 bytes for Float32x4)
      final simdBuffer = TransferableBuffer(64); // 64 bytes = 16 * 4 floats
      expect(
        simdBuffer.byteLength % 16,
        equals(0),
        reason: 'Buffer should be SIMD-aligned',
      );
    });

    test('transfer should create TransferableTypedData', () {
      final transferable = buffer.transfer();
      expect(transferable, isA<TransferableTypedData>());
    });

    test('receive should restore buffer ownership', () {
      final transferable = buffer.transfer();

      // After transfer, original buffer should be cleared
      expect(buffer.data.length, equals(0));

      // Create new buffer and receive the data
      final newBuffer = TransferableBuffer(0);
      newBuffer.receive(transferable);

      expect(newBuffer.byteLength, equals(1024));
      expect(newBuffer.data.length, equals(1024));
    });

    test('should handle different TypedData types', () {
      final intData = Int32List(50);
      for (int i = 0; i < intData.length; i++) {
        intData[i] = i * 42;
      }

      final buffer = TransferableBuffer.fromTypedData(intData);
      final transferable = buffer.transfer();

      final newBuffer = TransferableBuffer(0);
      newBuffer.receive(transferable);

      final restoredInts = newBuffer.data.buffer.asInt32List();
      for (int i = 0; i < intData.length; i++) {
        expect(restoredInts[i], equals(intData[i]));
      }
    });

    test('should handle large buffers efficiently', () {
      // Test with 1MB buffer
      final largeBuffer = TransferableBuffer(1024 * 1024);
      expect(largeBuffer.byteLength, equals(1024 * 1024));

      final transferable = largeBuffer.transfer();
      expect(transferable, isA<TransferableTypedData>());
    });

    test('transfer should isolate data ownership', () {
      final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final buffer = TransferableBuffer.fromTypedData(originalData);

      // Modify original data before transfer
      originalData[0] = 99;

      final transferable = buffer.transfer();
      final newBuffer = TransferableBuffer(0);
      newBuffer.receive(transferable);

      // Transferred data should not reflect the modification
      expect(newBuffer.data[0], equals(1), reason: 'Transfer should copy data');
    });
  });
}
