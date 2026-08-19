import 'transferable_buffer.dart';

/// Pool of reusable TransferableBuffers to reduce allocation overhead.
///
/// Pre-allocates buffers and recycles them to minimize GC pressure
/// during rapid buffer swapping operations.
class BufferPool {
  /// Creates a buffer pool with the specified configuration.
  BufferPool({
    required this.bufferSizeBytes,
    this.initialPoolSize = 4,
    this.maxPoolSize = 16,
  }) {
    _growPool(initialPoolSize);
  }

  /// Size in bytes for each pooled buffer.
  final int bufferSizeBytes;

  /// Number of buffers allocated during pool startup.
  final int initialPoolSize;

  /// Maximum number of retained pooled buffers.
  final int maxPoolSize;

  final List<TransferableBuffer> _allBuffers = [];

  final List<TransferableBuffer> _available = [];

  /// Clears all buffers and resets the pool.
  void clear() {
    _available.clear();
    _allBuffers.clear();
  }

  /// Gets a buffer from the pool or creates a new one if needed.
  TransferableBuffer getBuffer() {
    if (_available.isNotEmpty) {
      return _available.removeLast();
    }

    if (_allBuffers.length < maxPoolSize) {
      _growPool(1);
      return _available.removeLast();
    }

    // Pool exhausted, create temporary buffer
    return TransferableBuffer(bufferSizeBytes);
  }

  /// Returns a buffer to the pool for reuse.
  ///
  /// The buffer must be reinitialized by the caller before reuse.
  void returnBuffer(final TransferableBuffer buffer) {
    if (_allBuffers.contains(buffer) && !_available.contains(buffer)) {
      _available.add(buffer);
    }
  }

  void _growPool(final int count) {
    for (var i = 0; i < count; i++) {
      final buffer = TransferableBuffer(bufferSizeBytes);
      _allBuffers.add(buffer);
      _available.add(buffer);
    }
  }
}
