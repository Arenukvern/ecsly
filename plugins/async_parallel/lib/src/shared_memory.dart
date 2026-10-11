import 'dart:ffi';
import 'dart:typed_data';

// Define malloc/free for platforms that support it
/// Standard library handle used for malloc/free lookup.
final DynamicLibrary stdlib = DynamicLibrary.process();

/// Bound native free() function.
final FreeDart _free = stdlib.lookupFunction<FreeNative, FreeDart>('free');

/// Bound native malloc() function.
final MallocDart _malloc = stdlib.lookupFunction<MallocNative, MallocDart>(
  'malloc',
);

/// Dart signature of free().
typedef FreeDart = void Function(Pointer<Void>);

/// Native signature of free().
typedef FreeNative = Void Function(Pointer<Void>);

/// Dart signature of malloc().
typedef MallocDart = Pointer<Void> Function(int size);
// Native function signatures
/// Native signature of malloc().
typedef MallocNative = Pointer<Void> Function(IntPtr size);

/// Shared memory buffer using malloc.allocate for zero-latency cross-isolate access.
///
/// This provides direct memory access without ownership transfer, but requires
/// careful synchronization to avoid race conditions. Use only for read-only
/// or carefully synchronized data.
///
/// Note: This is platform-dependent (dart:ffi) and therefore native-only —
/// import this library on the VM, never in web or desktop-web builds.
class SharedMemory {
  SharedMemory._(this._pointer, this.byteLength);

  final Pointer<Uint8> _pointer;

  /// Backing allocation length in bytes.
  final int byteLength;

  bool _freed = false;

  /// Whether [free] has been called. Views taken before [free] alias freed
  /// memory — stop using them.
  bool get isFreed => _freed;

  /// Gets the memory address for sharing with other isolates.
  int get address => _pointer.address;

  /// Gets a Float32List view of the shared memory.
  Float32List asFloat32List() =>
      _pointer.cast<Float>().asTypedList(byteLength ~/ 4);

  /// Gets an Int32List view of the shared memory.
  Int32List asInt32List() =>
      _pointer.cast<Int32>().asTypedList(byteLength ~/ 4);

  /// Gets a TypedData view of the shared memory.
  ///
  /// Note: Creating views allocates Dart objects, so do this sparingly.
  Uint8List asUint8List() => _pointer.asTypedList(byteLength);

  /// Frees the shared memory.
  ///
  /// Call this when the memory is no longer needed. Double-free is a no-op
  /// (freeing twice is almost always a lifecycle bug; the guard makes the
  /// second call observable via [isFreed] instead of a native crash).
  void free() {
    if (_freed) return;
    _freed = true;
    _free(_pointer.cast<Void>());
  }

  /// Creates shared memory with the specified size.
  ///
  /// Returns null if malloc is not available on this platform.
  static SharedMemory? create(final int byteLength) {
    try {
      final pointer = _malloc(byteLength).cast<Uint8>();
      return SharedMemory._(pointer, byteLength);
    } on Object {
      return null; // malloc not available
    }
  }

  /// Reconstructs shared memory from an address.
  ///
  /// Use this in another isolate to access the same memory.
  static SharedMemory? fromAddress(final int address, final int byteLength) {
    try {
      final pointer = Pointer<Uint8>.fromAddress(address);
      return SharedMemory._(pointer, byteLength);
    } on Object {
      return null;
    }
  }
}
