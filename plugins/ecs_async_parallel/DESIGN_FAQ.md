# Design Decisions FAQ - ecs_async_parallel

Quick reference for ecs_async_parallel architectural choices and rationale. Focus: **Why** isolate management exists and key design decisions. See main ECS DESIGN_FAQ.md for core ECS architecture.

## Package Purpose

**Q: Why does ecs_async_parallel exist as a separate package?**  
A: Provides zero-cost isolate management for high-performance Dart applications. Enables concurrent computation without GC pressure. Decouples execution model from algorithm implementations. Trade-off: Isolate complexity vs single-threaded simplicity.

**Q: Why isolate management instead of async/await?**  
A: Isolates enable true parallelism on multi-core CPUs. Async/await is concurrent but single-threaded. Isolates prevent main thread blocking for heavy computations. Trade-off: Message passing overhead vs CPU utilization.

## Double Buffering Strategy

**Q: Why double buffering instead of single shared buffer?**  
A: Eliminates synchronization overhead. Main isolate reads from one buffer while compute isolate writes to another. Zero-copy ownership transfer via TransferableTypedData. Trade-off: 2x memory vs lock-free operation.

**Q: Why TransferableTypedData for buffer transfer?**  
A: Zero-copy ownership transfer between isolates. Preserves SIMD layout (Float32x4). No serialization overhead. Trade-off: Ownership transfer vs shared memory access.

**Q: Why swap buffers after each frame?**  
A: Maintains consistent read/write separation. Main isolate always reads stable data. Compute isolate always writes to fresh buffer. Prevents race conditions without locks. Trade-off: One-frame latency vs real-time access.

## Shared Memory Strategy

**Q: Why optional shared memory in addition to double buffering?**  
A: Enables zero-latency access for read-only data (collision meshes, static world data). Double buffering for dynamic state. Trade-off: Manual synchronization vs automatic ownership transfer.

**Q: Why malloc.allocate for shared memory?**  
A: Enables true shared memory across isolates (platform-dependent). Zero-copy access for both isolates. Trade-off: Platform limitations vs performance gain.

**Q: When should I use shared memory vs double buffering?**  
A: Shared memory for static/read-only data accessed frequently. Double buffering for dynamic state updated each frame. Trade-off: Synchronization complexity vs transfer overhead.

## Isolate Manager Design

**Q: Why IsolateManager abstraction instead of direct isolate usage?**  
A: Encapsulates double buffering protocol, message handling, and lifecycle management. Prevents buffer ownership bugs. Simplifies integration with game loops. Trade-off: Abstraction overhead vs manual coordination.

**Q: Why message-based communication instead of shared state?**  
A: Dart isolates are memory-isolated by design. Message passing is the only safe communication mechanism. Prevents data races and memory corruption. Trade-off: Message overhead vs memory safety.

**Q: Why automatic buffer swapping in IsolateManager?**  
A: Eliminates manual buffer coordination errors. Ensures correct read/write separation. Handles ownership transfer automatically. Trade-off: Less control vs safety guarantees.

## Performance Characteristics

**Q: Why zero-copy buffer transfer?**  
A: Eliminates GC pressure from buffer copying. Enables SIMD operations across isolate boundaries. Critical for 60fps with large entity counts. Trade-off: Ownership complexity vs allocation overhead.

**Q: Why one-frame latency acceptable?**  
A: Standard trade-off for concurrent processing. Main isolate renders previous frame while compute processes current frame. Prevents frame drops from heavy computation. Trade-off: Latency vs throughput.

**Q: Why buffer pooling not included?**  
A: Double buffering provides sufficient buffer reuse. Pooling adds complexity without clear benefit for frame-based updates. Trade-off: Pool management vs simple double buffer.

## Integration with Game Algorithms

**Q: Why designed for game_algorithms package?**  
A: Pure algorithms (TypedData buffers) are isolate-portable. Enables algorithm execution in background isolates. Maintains performance while offloading computation. Trade-off: Algorithm constraints vs concurrent execution.

**Q: Why not ECS-integrated isolate management?**  
A: Decouples execution model from data model. Algorithms can run in isolates without ECS knowledge. Enables algorithm libraries to evolve independently. Trade-off: Manual integration vs automatic ECS wiring.

## Platform Support

**Q: Why limited shared memory support?**  
A: Shared memory requires dart:ffi and platform-specific APIs. Not available on all Dart platforms (web, some mobile). Double buffering works everywhere. Trade-off: Platform coverage vs zero-latency access.

**Q: Why TransferableTypedData as primary strategy?**  
A: Works on all Dart platforms (web, mobile, desktop). Zero-copy transfer without platform dependencies. Reliable fallback when shared memory unavailable. Trade-off: One-frame latency vs universal support.

## Error Handling

**Q: Why no automatic error recovery?**  
A: Isolate failures indicate serious bugs (algorithm errors, memory issues). Automatic recovery could mask problems. Manual restart enables debugging. Trade-off: Convenience vs error visibility.

**Q: Why explicit shutdown required?**  
A: Ensures proper cleanup of isolate resources. Prevents resource leaks. Enables controlled shutdown sequence. Trade-off: Manual management vs automatic cleanup.

