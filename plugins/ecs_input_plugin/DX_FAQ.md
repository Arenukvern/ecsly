# ECS Input Plugin DX_FAQ - Memory Palace

_Spatial organization for AI agent memory retention. Event-driven input system with gesture classification._

## 🎛️ Setup Station

```dart
import 'package:ecs_input_plugin/ecs_input_plugin.dart';

// Install input plugin
world.addPlugin(const InputPlugin(
  tapCapacity: 200,
  dragCapacity: 200,
  pinchCapacity: 50,
  scrollCapacity: 50,
));

// Components registered automatically:
// - InteractiveElement
// - SelectableComponent
// - SelectionHighlightComponent
// - DraggableComponent
```

## 🎮 Action Mapping

```dart
// Configure key bindings at runtime
final inputMap = world.getResource<RuntimeInputMap>();

// Map keyboard keys to actions
inputMap.bind(
  InputSource.keyboard(LogicalKeyboardKey.keyW),
  InputAction.moveUp,
);

// Map gestures to actions
inputMap.bind(
  InputSource.gesture(GestureType.pinch),
  InputAction.zoomIn,
);

// Save/load keymaps
final json = inputMap.toJson();
final loadedMap = RuntimeInputMap.fromJson(json);
```

## 👆 Entity Interaction

```dart
// Make entity interactive
world.getEntity(entity).insert(InteractiveElement(
  hitRadius: 50.0,
  priority: 100,
  supportedGestures: {GestureType.tap, GestureType.drag},
));

// Make entity selectable
world.getEntity(entity).insert(SelectableComponent());

// Make entity draggable
world.getEntity(entity).insert(DraggableComponent(
  dragPlane: DragPlane.xy,
));
```

## 🎭 Gesture Processing

```dart
// Handle tap events
void handleTaps(World world) {
  final reader = world.events.reader<TapEvent>();
  for (final event in reader.iter()) {
    // Process tap at event.worldPosition
  }
}

// Handle drag events
void handleDrags(World world) {
  final reader = world.events.reader<DragEvent>();
  for (final event in reader.iter()) {
    // event.delta contains movement
    // event.startPosition vs event.position
  }
}

// Handle entity-specific events
void handleEntityTaps(World world) {
  final reader = world.events.reader<EntityTapEvent>();
  for (final event in reader.iter()) {
    final entity = event.entity;
    // Direct entity interaction
  }
}
```

## 🎯 State Tracking

```dart
// Query action state
final tracker = world.getResource<InputStateTracker>();

if (tracker.isHeld(InputAction.moveUp)) {
  // Move player up
}

if (tracker.justPressed(InputAction.jump)) {
  // Start jump animation
}

if (tracker.justReleased(InputAction.attack)) {
  // End attack sequence
}
```

## 📋 Selection Management

```dart
// Access selection manager
final selection = world.getResource<SelectionManager>();

// Single selection mode
selection.mode = SelectionMode.single;
selection.select(entity);

// Multi selection mode
selection.mode = SelectionMode.multi;
selection.select(entity1);
selection.select(entity2);

// Query selection
final selected = selection.selectedEntities;
final primary = selection.primaryEntity;
```

## 🎨 Unified Input Widget

```dart
// Flutter widget integration
Widget build(BuildContext context) => UnifiedInputWidget(
  world: world,
  child: GameWidget(world),
);

// Access cursor position
final cursor = world.getResource<CursorPositionResource>();
final screenPos = cursor.position;
final worldPos = cursor.worldPosition;
```

## 🚨 Safety Zone

- ✅ Install InputPlugin for event registration
- ✅ Bind actions before using them in systems
- ✅ Add InteractiveElement for entity interaction
- ✅ Use tracker for state queries, events for transitions
- ✅ Handle entity events for direct interaction
- ✅ Configure capacities based on expected input frequency
- ✅ Process input events in dedicated schedule phase

**Memory Hook:** "Setup → Action → Entity → Gesture → State → Selection → Widget"