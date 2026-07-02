# ECS Event System

A type-safe, allocation-light event system integrated with the ECS framework. Events use pooled ring buffers with SoA storage for optimal performance.

## Features

- **Type-safe**: Compile-time guarantees for event types
- **Column-based Storage**: Uses ECS DataColumns (FloatColumn, IntColumn, ObjectColumn) for SoA layout
- **SIMD Support**: Automatic vectorization via FloatColumn.simdView for math-heavy events
- **Zero GC Hot Loop**: TypedData storage eliminates heap allocations
- **Resource-based**: Events integrate with existing ResourceRegistry
- **Schedule-aware**: Automatic clearing at frame/schedule boundaries
- **Capacity management**: Configurable overflow policies with metrics

## Quick Start

```dart
import 'package:ecsly/ecsly.dart';

// 1. Install the event plugin
class MyGamePlugin extends Plugin {
  @override
  void install(World world) {
    world.plugins.add(EventPlugin());

    // Register event types
    world.events.register<DamageEvent>(
      fromNumericFieldsFactory: (fields) => DamageEvent(
        targetEntity: fields[0].toInt(),
        sourceEntity: fields[1].toInt(),
        amount: fields[2],
      ),
      sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0.0),
    );
    world.events.register<PlayerInputEvent>(); // Uses ObjectColumn for complex events
  }
}

// 2. Define event types
class DamageEvent with TypedDataEventMixin implements TypedDataEvent {
  const DamageEvent({
    required this.targetEntity,
    required this.sourceEntity,
    required this.amount,
  });

  final int targetEntity;
  final int sourceEntity;
  final double amount;

  @override
  List<num> get numericFields => [targetEntity, sourceEntity, amount];
}

// 3. Use in systems
void damageSystem(World world) {
  final writer = world.events.writer<DamageEvent>();
  final reader = world.events.reader<DamageEvent>();

  // Send events
  writer.send(DamageEvent(target: enemy, amount: 25.0));

  // Read events
  for (final event in reader.iter()) {
    // Process damage
    applyDamage(event.target, event.amount);
  }
}

// 4. Add to schedule with clearing
world.schedule('Update')
  .add(damageSystem)
  .then(eventClearSystem); // Clear events at frame end
```

## API Reference

### EventChannel<T>

Core storage for events of type `T`. Uses ring buffers with configurable capacity.

```dart
// Manual channel creation
final channel = EventChannel<DamageEvent>(
  capacity: 100,
  capacityPolicy: EventCapacityPolicy.dropNew,
  metricsHook: (overflow) => print('Event overflow: $overflow'),
);
```

### EventWriter<T>

Interface for sending events to a channel.

```dart
final writer = world.events.writer<DamageEvent>();

// Fire-and-forget sending
writer.send(DamageEvent(target: enemy, amount: 10));

// Check if event was sent (useful for capacity management)
if (writer.trySend(DamageEvent(target: enemy, amount: 10))) {
  print('Damage event sent');
} else {
  print('Channel full, event dropped');
}
```

### EventReader<T>

Interface for reading events from a channel. Provides snapshot semantics.

```dart
final reader = world.events.reader<DamageEvent>();

// Check if events exist
if (reader.isNotEmpty) {
  print('${reader.length} damage events');
}

// Peek at first event without consuming
final nextDamage = reader.peek();

// Iterate over all events
for (final event in reader.iter()) {
  handleDamage(event);
}
```

### EventRegistry

Manages event channels as world resources.

```dart
// Register TypedDataEvent channels (zero-GC storage)
world.events.register<DamageEvent>(
  capacity: 64,
  fromNumericFieldsFactory: (fields) => DamageEvent(
    targetEntity: fields[0].toInt(),
    sourceEntity: fields[1].toInt(),
    amount: fields[2],
  ),
  sampleEvent: DamageEvent(targetEntity: 0, sourceEntity: 0, amount: 0.0),
);

// Register complex event channels (ObjectColumn storage)
world.events.register<LogEvent>(capacity: 32);

// Check registration status
if (world.events.hasRegistered<DamageEvent>()) {
  final writer = world.events.writer<DamageEvent>();
}

// Unregister channels (removes from resources and clears)
world.events.unregister<DamageEvent>();

// Stride is calculated automatically from sampleEvent.numericFields.length
// DamageEvent stride = 3 (targetEntity, sourceEntity, amount)

// Access channels (throws if not registered)
final writer = world.events.writer<DamageEvent>();
final reader = world.events.reader<DamageEvent>();
```

## Capacity Management

Events use ring buffers with configurable overflow policies:

- **`EventCapacityPolicy.dropNew`**: Drop new events when full (default)
- **`EventCapacityPolicy.dropOld`**: Drop oldest event, send new event
- **`EventCapacityPolicy.throwOnOverflow`**: Throw `EventCapacityOverflow` exception when full

**Note**: Overflow policies are deterministic and documented. The `dropOld` policy correctly removes the oldest event and sends the new one, preventing silent fallthrough behavior.

```dart
world.events.register<DamageEvent>(
  capacity: 100,
  capacityPolicy: EventCapacityPolicy.dropOld,
  metricsHook: (overflow) {
    // Monitor capacity issues
    analytics.recordEventOverflow(overflow);
  },
);
```

## Lifecycle

Events follow a strict frame-based lifecycle:

1. **Send Phase**: Systems send events during frame execution
2. **Read Phase**: Systems read events during frame execution
3. **Clear Phase**: All events cleared at frame/schedule end

The event registry tracks all registered channels and provides `clearAll()` for reliable frame-bound clearing:

```dart
world.schedule('Update')
  .add(inputSystem)      // Send input events
  .then(physicsSystem)   // Send collision events
  .then(damageSystem)    // Read collision events, send damage
  .then(renderSystem)    // Read damage events for effects
  .then(eventClearSystem); // Clear all events via registry

// eventClearSystem calls world.events.clearAll() which iterates
// all tracked channels and calls clear() on each
```

## Performance Characteristics

- **Memory**: O(capacity × stride) per event type, TypedData for primitives, ObjectColumn for complex types
- **Send**: O(1) amortized, ring buffer operations on dense arrays
- **Read**: O(event_count) for iteration, SIMD-accelerated for FloatColumn events
- **Clear**: O(length) for actual events, not O(capacity) - optimized for sparse clearing
- **GC Pressure**: Zero in hot loop for primitive events, minimal for complex events
- **SIMD**: Automatic vectorization via FloatColumn.simdView for math-heavy event processing

## Column-Based Storage

Events use ECS DataColumns for optimal memory layout and performance:

### Storage Types

- **FloatColumn**: For events with mixed numeric fields or double-only fields (Position, Velocity, Damage)
- **IntColumn**: For events with integer-only fields (Entity IDs, enum indices)
- **ObjectColumn**: For events with complex fields (Strings, Lists, custom objects)

### Automatic Mapping

The system automatically selects the best column type based on event field analysis:

```dart
// Uses IntColumn (all fields are integers, stride: 3)
class EntityEvent with TypedDataEventMixin implements TypedDataEvent {
  final int entityA;
  final int entityB;
  final int eventType;

  @override
  List<num> get numericFields => [entityA, entityB, eventType];
}

// Uses FloatColumn (mixed int/double fields, stride: 3)
class DamageEvent with TypedDataEventMixin implements TypedDataEvent {
  final int targetEntity;  // Stored as double in FloatColumn
  final int sourceEntity;  // Stored as double in FloatColumn
  final double amount;     // Native double storage

  @override
  List<num> get numericFields => [targetEntity, sourceEntity, amount];
}

// Uses ObjectColumn (complex string field)
class LogEvent {
  final String message;  // Requires heap allocation
  final int level;       // Could be stored as double, but string forces ObjectColumn
}
```

### SIMD Benefits

Events stored in FloatColumn automatically benefit from SIMD operations:

```dart
// Standard iteration (object reconstruction)
final damageReader = world.events.reader<DamageEvent>();
for (final event in damageReader.iter()) {
  handleDamage(event.target, event.amount);
}

// SIMD iteration (direct field access, zero allocations)
final simdIter = damageReader.iterSimd();
if (simdIter != null) {
  for (final fields in simdIter) {
    // fields is Float32List with [targetEntity, sourceEntity, amount]
    final target = fields[0].toInt();
    final source = fields[1].toInt();
    final amount = fields[2];
    handleDamage(target, amount);
  }
}
```

SIMD iteration is available when:

- Event uses FloatColumn storage (mixed numeric types or double-only)
- Event stride is divisible by 4 (for Float32x4 vector alignment)
- Example: Events with 4, 8, 12+ numeric fields get SIMD acceleration

Use SIMD iteration for bulk math operations where object allocation overhead is significant.

### Memory Layout

Events use ring buffers on dense column arrays:

```
Column: [event0, event1, event2, ..., eventN]
Ring:   head ────▶ data ────▶ tail
              ▲           ▲
              └── ring ───┘
```

This provides O(1) send/read with zero reallocation in the hot loop.

## Best Practices

### Event Design

- Keep events small and focused
- For TypedData events: implement `TypedDataEventMixin` and provide `numericFields`
- Use primitive types (int, double) for hot path events - IntColumn for int-only, FloatColumn for mixed
- Store complex types (String, List, Map) in ObjectColumn only for cold data
- Prefer flat structures over nested objects for TypedData compatibility
- Use enum indices instead of enum objects
- Design for SIMD: events with multiple doubles get automatic vectorization
- Always register TypedData events with `fromNumericFieldsFactory` and `sampleEvent`

### Capacity Planning

- Size channels based on expected peak load
- Monitor overflow metrics in development
- Use `dropNew` for fire-and-forget events

### System Organization

- Send events early in frame, read later
- Group event-producing systems together
- Always include `eventClearSystem` at schedule end

### Threading Considerations

- Event channels are per-world
- Isolate execution copies channel snapshots
- Cross-isolate events require explicit copying

## Migration from Input Resources

When moving input state from resources to events, keep the adapter in the owning
input package or application layer. The core package only owns event channels and
schedule triggers; it does not prescribe a specific input action vocabulary.

```dart
void inputEventSystem(World world) {
  final reader = world.events.reader<InputEvent>();
  for (final event in reader.iter()) {
    handleInput(event);
  }
}
```

## Event-Driven Schedules

Schedules can be triggered by events using `EventTrigger`. This allows systems to run only when events are present, avoiding unnecessary per-frame checks:

```dart
// Only run when damage events exist
world.createSchedule(
  'DamageHandler',
  trigger: EventTrigger((world) => world.events.reader<DamageEvent>().isNotEmpty),
)
  .add(processDamageSystem)
  .then(eventClearSystem);

// Combine with throttling for rate limiting
world.createSchedule(
  'InputHandler',
  trigger: ThrottledTrigger(
    EventTrigger((world) => world.events.reader<InputEvent>().isNotEmpty),
    minIntervalSeconds: 0.016, // Max 60 FPS
  ),
)
  .add(inputSystem)
  .then(eventClearSystem);
```

**Benefits**:

- **Performance**: O(1) check via `channel.length > 0`, no iteration needed
- **Efficiency**: Systems only run when events exist, skipping empty frames
- **Composable**: Works with `ThrottledTrigger` and other trigger types

Event channels must be explicitly registered before use in triggers.

## Integration with Plugins

Events work seamlessly with the plugin system:

```dart
class PhysicsPlugin extends Plugin {
  @override
  void install(World world) {
    // Register physics events
    world.events.register<CollisionEvent>();
    world.events.register<ForceEvent>();

    // Add physics systems (can use event triggers for efficiency)
    world.createSchedule(
      'Physics',
      trigger: EventTrigger((world) => world.events.reader<CollisionEvent>().isNotEmpty),
    )
      .add(collisionDetectionSystem)
      .then(collisionResponseSystem)
      .then(eventClearSystem);
  }
}
```

## Troubleshooting

### Events Not Received

- Check schedule ordering (send before read)
- Verify `eventClearSystem` placement
- Ensure channel registration

### Performance Issues

- Profile with benchmarks
- Check capacity overflow metrics
- Consider smaller event types

### Memory Leaks

- Events are cleared automatically
- Check for lingering references in complex events
- Monitor channel capacity vs usage
