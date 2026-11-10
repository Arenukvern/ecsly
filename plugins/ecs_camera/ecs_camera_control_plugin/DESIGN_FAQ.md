# Design Decisions FAQ - Camera Control Plugin

Quick reference for camera control architectural choices and rationale. Focus: **Why** camera control exists as separate plugin. See main ECS DESIGN_FAQ.md for core ECS architecture.

## Plugin Purpose

**Q: Why camera control plugin separate from camera plugin?**
A: Camera plugin provides pure camera functionality (position, targets, smoothing). Control plugin adds input wiring and presets. Enables camera usage without input dependencies. Trade-off: Separate plugins vs monolithic camera system.

**Q: Why camera control plugin separate from input plugin?**
A: Input plugin provides generic input events (taps, drags, actions). Control plugin maps these to camera-specific behaviors. Enables input reuse across different systems (UI, player, camera). Trade-off: Specialized mapping vs generic input.

## Preset System Design

**Q: Why camera presets instead of manual configuration?**
A: Common camera patterns (RTS, platformer, isometric) have standard configurations. Presets provide battle-tested setups with proper defaults. Reduces boilerplate for common use cases. Trade-off: Preset limitations vs full customization.

**Q: Why enum-based presets with apply() method?**
A: Compile-time safety prevents invalid preset names. Apply method configures camera entity with complete setup (components + input mappings). Single call replaces manual component/input setup. Trade-off: Fixed presets vs dynamic configuration.

**Q: Why presets include input mappings?**
A: Camera behavior requires both camera components AND input bindings. Presets ensure consistent input/camera pairing. Prevents mismatched configurations. Trade-off: Preset rigidity vs flexible input mapping.

## Action Component System

**Q: Why action components (CameraPanAction, CameraZoomAction) instead of direct camera modification?**
A: Decouples input processing from camera movement. Systems can modify actions before applying to camera. Enables camera behavior customization (speed scaling, dead zones). Trade-off: Indirection vs direct control.

**Q: Why separate action components for different camera behaviors?**
A: Enables selective camera control (pan without zoom, zoom without pan). Systems can check for specific actions. Prevents unwanted camera movement. Trade-off: Multiple components vs single action component.

**Q: Why action components use delta values instead of absolute positions?**
A: Enables relative camera movement (pan by X units, zoom by factor). Supports multiple input sources combining (keyboard + mouse). Prevents camera jumping to absolute positions. Trade-off: Relative movement vs absolute positioning.

## System Architecture

**Q: Why separate systems for different input types (keyboard, scroll, pinch)?**
A: Different input types have different processing needs. Keyboard uses polling, scroll uses direct events, pinch uses gesture events. Enables optimization per input type. Trade-off: Multiple systems vs unified input processing.

**Q: Why scroll zoom bypasses action system?**
A: Direct scroll handling provides immediate response. No action pipeline latency for common zoom interaction. Action-based system available for advanced use cases. Trade-off: Direct handling vs consistent action pipeline.

**Q: Why entity dragging system separate from camera pan?**
A: Entity dragging moves entities, not camera. Requires zoom-aware coordinate conversion. Different interaction semantics (drag entity vs move camera). Trade-off: Separate systems vs unified drag handling.

## Interaction Mode System

**Q: Why CameraInteractionMode (editor, cinematic, gameplay)?**
A: Different game states need different camera controls. Editor mode enables free movement, cinematic disables input, gameplay enables standard controls. Mode switching without component changes. Trade-off: Mode complexity vs always-on controls.

**Q: Why interaction mode as resource instead of component?**
A: Global camera behavior affects all cameras. Single mode controls entire camera system. Prevents per-camera mode conflicts. Trade-off: Global state vs per-camera configuration.

## Dependency Management

**Q: Why strict dependency checking (InputPlugin + CameraPlugin required)?**
A: Camera control requires both input events AND camera components. Clear error messages prevent invalid configurations. Prevents runtime crashes from missing dependencies. Trade-off: Strict requirements vs graceful degradation.

**Q: Why plugin installation order enforced?**
A: Control plugin registers action components that depend on base components. Ensures component registration happens in correct order. Prevents component registration conflicts. Trade-off: Installation order vs automatic reordering.

## Performance Decisions

**Q: Why camera control systems run in Input schedule phase?**
A: Input processing should happen together with other input systems. Maintains consistent input-to-camera timing. Prevents frame-delayed camera responses. Trade-off: Schedule ordering vs automatic placement.

**Q: Why zoom-aware entity dragging?**
A: Screen drag distance should map to consistent world movement regardless of zoom. Zoom scaling prevents micro-movements at high zoom. Enables precise entity positioning. Trade-off: Coordinate conversion vs simple drag.

## Key Design Decisions

**Q: Why presets over manual camera setup?**
A: Presets provide complete, tested camera configurations with proper input bindings. Reduces setup complexity for common camera patterns. Enables rapid prototyping. Trade-off: Preset constraints vs unlimited customization.

**Q: Why action components over direct camera modification?**
A: Action components enable input preprocessing and camera behavior customization. Systems can modify actions before applying to camera. Supports advanced camera features (dead zones, speed curves). Trade-off: Component indirection vs direct camera control.

**Q: Why separate input and camera control plugins?**
A: Input plugin provides framework-agnostic input events. Camera control adds camera-specific mappings. Enables input reuse for non-camera features (UI, player movement). Trade-off: Plugin separation vs integrated camera input.