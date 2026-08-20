/// Zero-cost isolate management for high-performance Dart applications.
///
/// Provides TransferableTypedData double buffering and malloc.allocate shared memory
/// abstractions for concurrent computing without GC pressure.
///
/// ## Core Concepts
///
/// - **Double Buffering**: Automatic ownership transfer between isolates
/// - **Shared Memory**: Optional malloc.allocate for zero-latency access
/// - **Zero-Cost**: Minimal abstraction overhead, direct TypedData operations
///
library;

export 'src/buffer_pool.dart';
export 'src/double_buffer.dart';
export 'src/isolate_executor.dart';
export 'src/isolate_manager.dart';
export 'src/isolate_pool.dart';
export 'src/shared_memory.dart';
export 'src/transferable_buffer.dart';
