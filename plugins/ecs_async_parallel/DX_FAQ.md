# Game Isolates DX_FAQ - Memory Palace
_Spatial organization for AI agent memory retention. Isolate management for concurrency._

## 🏃‍♂️ Isolate Factory
```dart
import 'package:ecs_async_parallel/ecs_async_parallel.dart';

// Create isolate pool
final pool = IsolatePool(size: 4);
await pool.start();

// Execute work
final result = await pool.execute((data) {
  // Heavy computation here
  return processedData;
});
```

## 📊 Task Management
```dart
// Batch processing
final tasks = entities.map((e) => Task(e, processEntity));
final results = await pool.executeBatch(tasks);

// Priority scheduling
pool.scheduleHighPriority(() => expensiveCalculation());
pool.scheduleLowPriority(() => backgroundTask());
```

## 🔄 Data Transfer
```dart
// Transferable objects for zero-copy
final transferable = TransferableTypedData.fromList([data]);
final result = await pool.executeWithTransfer(transferable, processFn);

// Automatic serialization for complex objects
final complexResult = await pool.executeComplex((input) => process(input));
```

## 🚨 Safety Zone
- ✅ Start pool before submitting work
- ✅ Use transferable data for performance
- ✅ Handle isolate errors gracefully
- ✅ Shutdown pool when done

**Memory Hook:** "Factory → Tasks → Transfer → Shutdown"