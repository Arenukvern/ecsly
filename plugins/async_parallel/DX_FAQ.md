# Game Isolates DX_FAQ - Memory Palace
_Spatial organization for AI agent memory retention. Isolate management for concurrency._

## 🏃‍♂️ Isolate Manager
```dart
import 'package:async_parallel/async_parallel.dart';

// Create an isolate manager with a compute entry point
final isolateManager = IsolateManager(_computeFunction);

// Start with a 64KB double-buffered workspace
await isolateManager.start(64 * 1024);

// Submit a frame's input for background computation
isolateManager.computeFrame(playerInput);

// Read the render buffer (safe from the owner isolate)
final renderData = isolateManager.renderBuffer?.asFloat32List();

// Cleanup
await isolateManager.shutdown();
```

## 🔄 Double Buffering
```dart
import 'package:async_parallel/async_parallel.dart';

// Two buffers with zero-copy ownership transfer between isolates
final buffer = DoubleBuffer(512);

// Write to the buffer the compute isolate owns
final writeData = buffer.writeBuffer.data;
writeData[0] = 42;

// Swap ownership after the compute isolate finishes
buffer.swap();

// Read the stable buffer from the owner isolate
final readData = buffer.readBuffer.data;
```

## 📦 Buffer Pool
```dart
import 'package:async_parallel/async_parallel.dart';

// Reusable buffers to cut GC pressure during rapid swapping
final pool = BufferPool(
  bufferSizeBytes: 256,
  initialPoolSize: 4,
  maxPoolSize: 16,
);

final buffer = pool.getBuffer();
// ... use buffer ...
pool.returnBuffer(buffer);
```

## ⚙️ Pluggable Isolate Backend
```dart
import 'package:async_parallel/async_parallel.dart';

// Swap the execution strategy without touching callers
const executor = IsolateExecutorDart();

final result = await executor.compute<int, int>(
  (final message) => message * 2,
  21,
);
```

## 🚨 Safety Zone
- ✅ Start the manager before submitting frames
- ✅ Use `TransferableBuffer` for zero-copy transfer
- ✅ Handle isolate errors gracefully
- ✅ Shutdown the manager when done
- ⚠️ `IsolateExecutorDart` spawns a fresh isolate per call — prefer a pooled
  implementation for hot paths

**Memory Hook:** "Factory → Tasks → Transfer → Shutdown"