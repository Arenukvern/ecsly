# Design Decisions FAQ - Camera System

Quick reference for camera architectural choices and rationale. Focus: **Why** camera system exists and key design decisions. See main ECS DESIGN_FAQ.md for core ECS architecture.

**Note:** This package provides pure camera functionality with NO input dependencies. For input-based camera control, see `ecs_camera_control_plugin`.

## Core Architecture

**Q: Why component-based camera instead of resource-only?**  
A: Enables multiple cameras, camera-specific behaviors (follow, fixed, free), and camera shake effects. Component system allows cameras to be entities with full ECS integration. Trade-off: Component overhead vs simple resource.

**Q: Why composable camera architecture (Target + Control + Effects + Core)?**  
A: Enables flexible camera behaviors through component composition. Target layer (FollowTarget, FixedTarget, FreeTarget) defines what to follow. Control layer (CameraController, CameraZoom, CameraSmoothing) handles movement configuration. Effects layer (CameraShake, CameraBlend, CameraConstraints) adds visual feedback. Trade-off: Configuration complexity vs hardcoded camera types.

**Q: Why separate target/current position and zoom values?**  
A: Enables smooth interpolation without frame-rate dependent movement. Systems set target values, lerp systems smoothly animate to targets. Prevents jarring camera jumps in games. Trade-off: Extra computation vs immediate response.

**Q: Why TypedData extension types for camera components?**  
A: Zero-GC storage using FloatColumn for position/zoom data. Eliminates heap allocation in hot camera loops. Enables SIMD for camera math. Trade-off: Extension type complexity vs simple class components.

## Component Design

**Q: Why CameraPosition with stride 6 (x,y,targetX,targetY,zoom,targetZoom)?**  
A: Packs related values into single Float32List for cache locality. Target/current separation enables smooth following. Stride 6 optimizes memory layout for SIMD. Trade-off: Packed data vs separate components.

**Q: Why CameraVelocity component separate from CameraPosition?**  
A: Enables physics-based camera movement (momentum, damping). Separate velocity allows different interpolation speeds for position vs velocity. Trade-off: Extra component vs position-only camera.

**Q: Why mutually exclusive target components (FollowTarget, FixedTarget, FreeTarget)?**  
A: Clear semantics - camera can only follow one thing at a time. Prevents conflicting target behaviors. Systems query specific targets for focused logic. Trade-off: Mutually exclusive vs additive behaviors.

**Q: Why composable control components (CameraController, CameraZoom, CameraSmoothing)?**  
A: Enables flexible camera behavior mixing. Camera can have zoom without pan, or smoothing without controller. Systems additively apply behaviors. Trade-off: System coordination vs monolithic camera.

**Q: Why CameraZoomToFit component instead of system-only zoom calculation?**  
A: Enables per-camera zoom-to-fit configuration. Each camera can have different targets, padding, and zoom limits. Component-based enables easy addition/removal. Trade-off: Component overhead vs global zoom-to-fit system.

**Note:** Camera action components (CameraPanAction, CameraZoomAction, etc.) are provided by `ecs_camera_control_plugin`, not this package. This keeps the camera plugin independent of input.

## System Architecture

**Q: Why separate systems for different camera behaviors?**  
A: Enables independent enable/disable and different update frequencies. Camera physics runs every frame, target following runs when needed. Prevents monolithic update loops. Trade-off: Multiple systems vs single camera system.

**Q: Why add `CameraProjectionModeResource` with frame latching?**  
A: It unifies 2D/2.5D/3D camera projection contracts and guarantees deterministic mode switching only at frame boundaries (`cameraProjectionModeLatchSystem`). This avoids mid-frame host/state divergence.

**Q: Why lerp-based smoothing instead of velocity-based?**  
A: Exponential interpolation (1.0 - exp(-speed \* dt)) provides natural, frame-rate independent movement. Used in games for smooth camera following. Trade-off: Math complexity vs linear interpolation.

**Q: Why camera constraints system?**  
A: Prevents camera from going out of bounds or violating game rules. Separate system enables pluggable constraint logic (screen bounds, level bounds, etc.). Trade-off: Constraint complexity vs unconstrained camera.

**Q: Why camera blend system?**  
A: Enables smooth transitions between different camera behaviors. Useful for cutscenes or state changes. Blend factor controls interpolation speed. Trade-off: Blend logic vs instant switching.

**Note:** Input-based camera control systems (genericCameraPanSystem, genericCameraZoomSystem, scrollZoomSystem) are provided by `ecs_camera_control_plugin`, not this package. Camera systems in this package are pure - they operate on camera components without input dependencies.

## Performance Decisions

**Q: Why command queue for camera entity spawning?**  
A: Defers structural changes to prevent iterator invalidation during camera processing. CameraPlugin spawns default camera via commands. Trade-off: Deferred spawning vs immediate availability.

**Q: Why camera priority system?**  
A: Enables multiple cameras with render ordering. Higher priority cameras render first. Supports minimaps, split-screen, UI layering. Trade-off: Priority management vs single camera.

**Q: Why camera culling bounds calculation?**  
A: Enables entity culling for off-screen objects. getViewBounds() calculates visible world rectangle. Critical for 60fps with 100k+ entities. Trade-off: Culling math vs rendering everything.

## Plugin Design

**Q: Why CameraPlugin spawns default camera entity?**  
A: Provides working camera out-of-box for developers. Default setup (FreeTarget + Controller + Zoom + Smoothing) covers most use cases. Trade-off: Opinionated defaults vs manual setup.

**Q: Why camera components registered in plugin instead of global?**  
A: Ensures camera components available when plugin installed. Prevents missing component errors. Trade-off: Plugin dependency vs global registration.

**Note:** Camera presets (CameraPreset.rts, CameraPreset.platformer) and input bindings are provided by `ecs_camera_control_plugin`, not this package. This keeps camera plugin independent of input.

## Integration Decisions

**Q: Why camera coordinate transformation at canvas level?**  
A: More efficient than widget-level transformations. Applies once per frame instead of per-entity. Enables world-coordinate painting in painters. Trade-off: Canvas math vs widget transformations.

**Q: Why SwarmFollowingCamera adapter class?**  
A: Bridges ECS camera components with Camera interface expected by painters. Enables painters to work in world coordinates while camera handles screen transformation. Trade-off: Adapter pattern vs direct component access.

**Q: Why camera shake component instead of resource?**  
A: Each camera can have independent shake effects. Component-based enables per-camera shake configuration and easy addition/removal. Applied during rendering via camera adapter. Trade-off: Component complexity vs global shake resource.

## Optional Dependencies

**Q: Why camera systems optionally use ViewportSizeResource from input plugin?**  
A: Enables zoom-to-fit system to work without requiring input plugin. Camera systems check for resource existence at runtime. Prevents hard dependency on input plugin. Trade-off: Runtime checking vs compile-time dependency.

**Q: Why camera systems optionally use PositionConfigResource for entity position?**  
A: Enables camera blend system to extract positions from entities without requiring input plugin. Systems gracefully handle missing resource. Trade-off: Optional dependency vs hard requirement.

## Key Design Decisions

**Q: Why camera as entity vs global resource?**  
A: Enables multiple cameras, camera-specific behaviors, and ECS integration. Cameras can be queried, filtered, and processed like other entities. Trade-off: Entity overhead vs simple global state.

**Q: Why target/current separation vs immediate updates?**  
A: Enables smooth following without frame-rate dependency. Games set target positions, lerp systems handle smooth animation. Prevents jarring movement in variable frame rates. Trade-off: Extra computation vs instant camera response.

**Q: Why composable component layers vs monolithic camera types?**  
A: Enables flexible camera behaviors through component mixing. Developers combine target + control + effects as needed. Supports complex camera requirements (follow with shake, zoom with constraints). Trade-off: Configuration complexity vs simple camera types.

**Q: Why TypedData storage vs regular Dart objects?**  
A: Zero-GC performance critical for camera processing every frame. Camera position/zoom accessed in hot loops for entity culling and rendering. SIMD compatibility for camera math. Trade-off: Extension type complexity vs ergonomic objects.

**Q: Why camera plugin has NO input dependencies?**  
A: Enables camera to be controlled programmatically without requiring input plugin. Camera can be used in headless servers, scripted cutscenes, or AI-controlled scenarios. Input-based control is provided by `ecs_camera_control_plugin`. Trade-off: No input integration vs optional input control.
