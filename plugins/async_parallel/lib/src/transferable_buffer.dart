import 'dart:isolate';
import 'dart:typed_data';

/// A buffer that can be transferred between isolates with zero-copy semantics.
///
/// When transferred, the sending isolate loses access to the data until it
/// receives the buffer back. This enables double-buffering patterns for
/// concurrent processing without GC pressure.
class TransferableBuffer {
  /// Creates a buffer with the specified size in bytes.
  TransferableBuffer(this.byteLength) : _data = Uint8List(byteLength);

  /// Creates a buffer from existing TypedData.
  ///
  /// The buffer takes ownership of the data - the caller should not
  /// modify it after creation.
  TransferableBuffer.fromTypedData(final TypedData data)
    : byteLength = data.lengthInBytes,
      _data = Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );

  /// Size of the buffer in bytes.
  int byteLength;

  Uint8List _data;

  /// The underlying data buffer.
  Uint8List get data => _data;

  /// Whether this isolate currently owns the buffer.
  bool get isOwned => byteLength > 0;

  /// Receives ownership from a transfer.
  ///
  /// Call this when receiving a TransferableTypedData to regain access.
  void receive(final TransferableTypedData transferable) {
    final materialized = transferable.materialize();
    // The ByteBuffer should contain our original data
    // Since we transferred a single Uint8List, we can view the entire buffer
    _data = Uint8List.view(materialized);
    byteLength = _data.length;
  }

  /// Transfers ownership to another isolate.
  ///
  /// After calling this, the current isolate loses access to the data.
  /// Returns a TransferableTypedData that can be sent via SendPort.
  ///
  /// Note: [byteLength] is reset to 0 alongside [data] so the buffer cannot
  /// report a stale size while holding no data. Capture the size first if you
  /// need it after transfer.
  TransferableTypedData transfer() {
    final transferable = TransferableTypedData.fromList([_data]);
    // Clear local reference after transfer. byteLength must be reset too,
    // otherwise the buffer lies about its size while owning no data.
    _data = Uint8List(0);
    byteLength = 0;
    return transferable;
  }
}
