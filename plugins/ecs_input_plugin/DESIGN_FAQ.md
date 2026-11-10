# Design Decisions FAQ - Input System

Quick reference for input system architectural choices and rationale. Focus: **Why** input system exists and key design decisions. See main ECS DESIGN_FAQ.md for core ECS architecture.

**Note:** This package provides pure input functionality with NO camera dependencies. For input-based camera control, see `ecs_camera_control_plugin`.

## Core Architecture

**Q: Why event-driven input instead of polling?**  
A: Zero-overhead when no input active. Events only allocated when input occurs. Frame-bound event lifecycle prevents memory leaks. Trade-off: Event allocation cost vs constant polling overhead.

**Q: Why three-layer input pipeline (Raw → Gesture → Action)?**  
A: Separates platform-specific input (Flutter widgets) from game logic. Raw events (RawPointerDown) → Gesture classification (TapEvent, DragEvent) → Action mapping (InputActionEvent). Enables platform-agnostic game code. Trade-off: Pipeline complexity vs direct input handling.

**Q: Why TypedData events for input?**  
A: Zero-GC storage using FloatColumn/IntColumn for numeric event data. Eliminates heap allocation in hot input loops. Enables efficient event batching and SIMD processing. Trade-off: Factory function complexity vs heap allocation.

**Q: Why RuntimeInputMap resource instead of hardcoded keymaps?**  
A: Enables runtime key rebinding, control scheme switching, and keymap persistence. Supports different input modes (keyboard, mouse, touch) without code changes. Trade-off: Runtime lookup cost vs compile-time constants.

## Input Source Design

**Q: Why sealed class hierarchy for InputSource (KeyboardSource, MouseButtonSource, GestureSource)?**  
A: Type-safe input source representation with pattern matching. Enables serialization/deserialization for keymap persistence. Prevents invalid source combinations. Trade-off: Sealed class complexity vs simple string IDs.

**Q: Why KeyModifiers (Ctrl, Shift, Alt, Meta) as optional parameter?**  
A: Enables input chords (Ctrl+Click, Shift+Drag) without separate action types. Modifiers checked at binding time, not in systems. Supports complex input combinations. Trade-off: Modifier matching overhead vs separate action types.

**Q: Why uniqueId string for InputSource serialization?**  
A: Enables JSON persistence of keymaps. Format: `kb:123+ctrl+shift` for keyboard, `mouse:0` for mouse, `gesture:drag` for gestures. Human-readable and parseable. Trade-off: String parsing vs binary serialization.

**Q: Why GestureSource separate from KeyboardSource/MouseButtonSource?**  
A: Gestures are abstract (drag, pinch, scroll) while keyboard/mouse are concrete (key W, button 0). Gesture classification happens before action mapping. Enables touch-first games with gesture-based controls. Trade-off: Gesture abstraction vs direct pointer events.

## Action System Design

**Q: Why InputAction enum instead of string-based actions?**  
A: Compile-time type safety, efficient comparisons, and IDE autocomplete. Enum values stored as integers in TypedData events. Prevents typos and invalid action names. Trade-off: Enum modification requires code changes vs runtime flexibility.

**Q: Why InputStateTracker resource instead of event-only tracking?**  
A: Enables efficient `isHeld()` queries without scanning all events. Tracks pressed/held/released state transitions. Systems can query action state without event iteration. Trade-off: Resource state vs pure event-driven.

**Q: Why InputState (pressed/held/released) instead of boolean?**  
A: Enables frame-accurate input detection. `justPressed()` detects first frame, `isHeld()` detects continuous input, `justReleased()` detects release. Critical for responsive game controls. Trade-off: State machine complexity vs simple boolean.

**Q: Why InputActionEvent with state + value fields?**  
A: State field enables pressed/held/released detection. Value field enables analog inputs (scroll delta, mouse movement). Single event type covers all input scenarios. Trade-off: Event complexity vs multiple event types.

**Q: Why InputBindingSystem emits events instead of directly modifying game state?**  
A: Decouples input processing from game logic. Systems consume InputActionEvent independently. Enables input replay, debugging, and action filtering. Trade-off: Event allocation vs direct function calls.

## Gesture Classification

**Q: Why GestureClassificationSystem converts raw events to gestures?**  
A: Abstracts platform-specific input (Flutter pointer events) into game-level gestures (tap, drag, pinch). Enables touch-first games with gesture-based controls. Single classification system handles all gesture types. Trade-off: Classification overhead vs direct pointer handling.

**Q: Why GestureClassificationState resource for gesture state machine?**  
A: Tracks gesture lifecycle (start → update → end) across frames. Prevents gesture conflicts (tap vs drag detection). Enables gesture cancellation and timeout handling. Trade-off: State machine complexity vs simple event forwarding.

**Q: Why GestureConsumptionTracker resource?**  
A: Prevents gesture conflicts between systems. Entity dragging consumes drag events, preventing camera pan. Enables priority-based gesture handling. Trade-off: Consumption tracking overhead vs first-come-first-served.

## Entity Interaction

**Q: Why SelectionManager resource instead of component-only selection?**  
A: Single source of truth for selection state. Prevents component/resource desync. Enables bulk selection operations (selectRect, selectAll). Trade-off: Resource overhead vs component-based selection.

**Q: Why SelectionMode (single/multi) in SelectionManager?**  
A: Enables different selection behaviors per game mode. Single mode: one entity at a time. Multi mode: multiple entities. Mode switching without code changes. Trade-off: Mode checking overhead vs separate selection systems.

**Q: Why unified hit testing system?**  
A: Single spatial query for all interaction systems. Prevents duplicate raycasts and spatial queries. Enables efficient entity selection and dragging. Trade-off: Unified system complexity vs per-system hit testing.

**Q: Why entity-specific events (EntityTapEvent, EntityDragEvent)?**  
A: Enables per-entity input handling without system queries. Entities receive events directly after hit testing. Supports component-based input handling. Trade-off: Event allocation vs system-based queries.

## Input Binding System

**Q: Why InputBindingSystem processes keyboard and gestures separately?**  
A: Keyboard uses HardwareKeyboard.instance (polling), gestures use events (push). Different processing paths for different input types. Enables efficient keyboard state queries. Trade-off: Dual processing paths vs unified input handling.

**Q: Why InputBindingSystem emits held events every frame?**  
A: Enables continuous action detection (held keys, ongoing drags). Systems can query `isHeld()` or process held events. Supports frame-accurate input timing. Trade-off: Event allocation vs state-only tracking.

**Q: Why scroll direction mapping in InputBindingSystem?**  
A: Scroll events have direction (positive = zoom out, negative = zoom in). System maps scroll to appropriate InputAction (zoomIn/zoomOut). Prevents action system complexity. Trade-off: Direction mapping in binding system vs action system.

## Optional Camera Integration

**Q: Why input systems optionally query camera components for zoom?**  
A: Enables zoom-aware hit testing and entity dragging. Systems check for camera existence at runtime and use zoom = 1.0 as fallback. Prevents hard dependency on camera plugin. Trade-off: Runtime checking vs compile-time dependency.

**Q: Why entity selection/dragging systems work without camera plugin?**  
A: Enables input plugin to be used independently for UI-only interactions. Systems gracefully handle missing camera by using default zoom. Camera integration is optional, not required. Trade-off: Optional dependency vs hard requirement.

**Note:** Camera action components (CameraPanAction, CameraZoomAction, etc.) and camera control systems are provided by `ecs_camera_control_plugin`, not this package. This keeps the input plugin independent of camera.

## Performance Decisions

**Q: Why frame-bound event lifecycle (clear at end of frame)?**  
A: Events are transient signals, not persistent state. Frame-bound clearing prevents memory leaks. Ensures consistent event iteration semantics. Trade-off: Event clearing overhead vs persistent events.

**Q: Why InputStateTracker.advance() at end of frame?**  
A: Transitions pressed→held, clears released actions. Prevents state accumulation across frames. Enables frame-accurate input timing. Trade-off: State transition overhead vs persistent state.

**Q: Why cached keyboard state (HardwareKeyboard.instance.logicalKeysPressed)?**  
A: Flutter caches keyboard state internally. Direct access avoids event iteration. Enables efficient keyboard state queries. Trade-off: Platform dependency vs event-only input.

## Keymap Persistence

**Q: Why JSON serialization for RuntimeInputMap?**  
A: Human-readable format for debugging and editing. Enables keymap sharing between users. Simple to implement with Dart's JSON support. Trade-off: JSON parsing overhead vs binary format.

**Q: Why LoadResult with error list for JSON deserialization?**  
A: Enables partial keymap loading on errors. Reports all errors, not just first failure. Prevents silent failures from invalid keymaps. Trade-off: Error handling complexity vs fail-fast.

**Q: Why InputSource.fromUniqueId() for deserialization?**  
A: Enables reconstruction of InputSource from stored uniqueId. Supports keymap migration and versioning. Prevents deserialization failures from format changes. Trade-off: String parsing overhead vs binary format.

## Key Design Decisions

**Q: Why event-driven input vs polling?**  
A: Zero-overhead when no input active. Events only allocated when input occurs. Frame-bound lifecycle prevents memory leaks. Trade-off: Event allocation cost vs constant polling overhead.

**Q: Why RuntimeInputMap vs hardcoded keymaps?**  
A: Enables runtime key rebinding, control scheme switching, and keymap persistence. Supports different input modes without code changes. Trade-off: Runtime lookup cost vs compile-time constants.

**Q: Why three-layer pipeline (Raw → Gesture → Action)?**  
A: Separates platform-specific input from game logic. Enables platform-agnostic game code. Supports touch-first games with gesture-based controls. Trade-off: Pipeline complexity vs direct input handling.

**Q: Why InputStateTracker resource vs event-only tracking?**  
A: Enables efficient `isHeld()` queries without event iteration. Tracks state transitions for frame-accurate input. Systems can query action state independently. Trade-off: Resource state vs pure event-driven.

**Q: Why input plugin has NO camera dependencies?**  
A: Enables input to be used independently for UI interactions, entity manipulation, or other non-camera use cases. Camera integration is provided by `ecs_camera_control_plugin`. Trade-off: No camera integration vs optional camera control.
