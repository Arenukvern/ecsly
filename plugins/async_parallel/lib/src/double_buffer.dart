import 'dart:typed_data';

import 'transferable_buffer.dart';

/// Double buffer implementation for zero-copy isolate communication.
///
/// Maintains two buffers: one owned by the main isolate (for reading/rendering)
/// and one owned by the compute isolate (for writing/updating).
///
/// This eliminates GC pressure and enables SIMD operations across isolate boundaries.
class DoubleBuffer {
  /// Creates a double buffer with the specified size.
  DoubleBuffer(final int byteLength) {
    _buffers = [TransferableBuffer(byteLength), TransferableBuffer(byteLength)];
    _readIndex = 0;
    _writeIndex = 1;
  }

  /// Creates a double buffer from existing TypedData buffers.
  DoubleBuffer.fromBuffers(final TypedData bufferA, final TypedData bufferB) {
    _buffers = [
      TransferableBuffer.fromTypedData(bufferA),
      TransferableBuffer.fromTypedData(bufferB),
    ];
    _readIndex = 0;
    _writeIndex = 1;
  }

  late final List<TransferableBuffer> _buffers;

  late int _readIndex;

  late int _writeIndex;

  /// Gets the buffer currently owned by the reading isolate.
  TransferableBuffer get readBuffer => _buffers[_readIndex];

  /// Gets the buffer currently owned by the writing isolate.
  TransferableBuffer get writeBuffer => _buffers[_writeIndex];

  /// Gets a view of the read buffer as Float32List.
  Float32List asFloat32List() => readBuffer.data.buffer.asFloat32List();

  /// Gets SIMD view of the read buffer (if stride allows).
  Float32x4List? asFloat32x4List() {
    final data = readBuffer.data;
    if (data.lengthInBytes % 16 != 0) return null;
    return data.buffer.asFloat32x4List();
  }

  /// Gets a view of the read buffer as Int32List.
  Int32List asInt32List() => readBuffer.data.buffer.asInt32List();

  /// Swaps the read and write buffers.
  ///
  /// Call this after transferring the write buffer to the other isolate
  /// and receiving the old read buffer back.
  void swap() {
    final temp = _readIndex;
    _readIndex = _writeIndex;
    _writeIndex = temp;
  }
}
