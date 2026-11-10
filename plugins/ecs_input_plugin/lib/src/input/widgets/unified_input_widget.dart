/// Unified input widget that captures all pointer and gesture events at the top level.
///
/// This widget serves as the single source of input for the entire application.
/// It sends raw pointer events to the ECS event system without any gesture classification.
/// Gesture classification is handled by gestureClassificationSystem in the Input schedule.
///
/// Should be placed at the top of the widget tree, typically wrapping
/// the main game renderer or canvas.
library;

import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;

import '../gesture_events.dart';
import '../raw_input_events.dart';

/// {@template unified_input_widget}
/// Unified input widget that sends raw events only.
///
/// **Coordinate Conversion:**
/// For camera-aware coordinate conversion, provide [toWorldCoords] callback.
/// Camera plugin provides `createCameraToWorldConverter` helper function.
///
/// **Viewport Size Updates:**
/// For type-safe viewport size updates, provide [onViewportSizeChanged] callback.
/// Camera plugin provides `createViewportSizeUpdater` helper function.
///
/// **Example (Flutter host with camera):**
/// ```dart
/// import 'package:ecs_camera_plugin/ecs_camera_plugin.dart';
///
/// UnifiedInputWidget(
///   world: world,
///   toWorldCoords: createCameraToWorldConverter(world, cameraEntity),
///   onViewportSizeChanged: createViewportSizeUpdater(world),
///   child: GameLoopWidget(...),
/// )
/// ```
///
/// **Example (headless/test host):**
/// ```dart
/// // In test or CLI loop:
/// await runFixedSteps(
///   world,
///   frames: 1,
///   fixedDtSeconds: 1 / 60,
///   scheduleNames: const ['Input', 'SimUpdate'],
/// )
/// ```
/// {@endtemplate}
class UnifiedInputWidget extends StatefulWidget {
  final World world;

  final Widget child;

  /// Optional function to convert screen coordinates to world coordinates.
  ///
  /// If provided, this function will be used for all coordinate conversions.
  /// If not provided, falls back to simple conversion (screen = world).
  ///
  /// Camera plugin provides `createCameraToWorldConverter` helper function
  /// that creates a camera-aware converter.
  final ui.Offset Function(ui.Offset screenPos, ui.Size viewportSize)?
  toWorldCoords;

  /// Optional function to update viewport size resource.
  ///
  /// If provided, this function will be called when viewport size changes.
  /// Camera plugin provides `createViewportSizeUpdater` helper function.
  ///
  /// If not provided, viewport size resource will not be updated automatically.
  final void Function(ui.Size size)? onViewportSizeChanged;

  /// Whether trackpad scroll should drive camera-style pan/orbit updates.
  ///
  /// When enabled, `PointerScrollEvent`s reported as trackpad input are
  /// forwarded as raw scale updates with pan deltas instead of generic scroll
  /// events. This keeps web touchpad gestures usable for orbit/pan without
  /// affecting mouse wheel zoom.
  final bool trackpadScrollCausesPan;

  /// {@macro unified_input_widget}
  const UnifiedInputWidget({
    required this.world,
    required this.child,
    this.toWorldCoords,
    this.onViewportSizeChanged,
    this.trackpadScrollCausesPan = false,
    super.key,
  });

  @override
  State<UnifiedInputWidget> createState() => _UnifiedInputWidgetState();
}

class _UnifiedInputWidgetState extends State<UnifiedInputWidget> {
  late final _focusNode = FocusNode();
  ui.Size _viewportSize = Size.zero;

  @override
  Widget build(final BuildContext context) => LayoutBuilder(
    builder: (final context, final constraints) {
      // Update viewport size resource if callback is provided
      final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
      _viewportSize = viewportSize;
      widget.onViewportSizeChanged?.call(viewportSize);

      return Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (final node, final event) => _handleKeyEvent(event),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            widget.child,
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (final event) {
                  // Request focus when user clicks to ensure keyboard events are captured
                  _focusNode.requestFocus();
                  _sendPointerEvent(event);
                },
                onPointerMove: _sendPointerEvent,
                onPointerHover: _sendPointerEvent,
                onPointerUp: _sendPointerEvent,
                onPointerCancel: _sendPointerEvent,
                // NOTE: no onPointerPanZoom* handlers here on purpose.
                // Desktop trackpad pan-zoom gestures ALSO ride the scale
                // recognizer below (Flutter routes PointerPanZoom events to
                // ScaleGestureRecognizer), so a Listener pan-zoom path
                // double-emits every trackpad event (double pan/zoom speed).
                // The scale path is the single source; verified against the
                // macOS double-pan bug in the flutter_scene adapter.
                onPointerSignal: _sendPointerSignal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _sendScaleEvent,
                  onScaleUpdate: _sendScaleEvent,
                  onScaleEnd: _sendScaleEvent,
                  onSecondaryTapDown: (final details) {
                    // Send as secondary tap event (already classified by Flutter)
                    final event = SecondaryTapEvent(
                      position: details.globalPosition,
                      worldPosition: _toWorldCoords(
                        details.localPosition,
                        context,
                      ),
                      timestamp: DateTime.now().millisecondsSinceEpoch,
                    );
                    widget.world.events.writer<SecondaryTapEvent>().send(event);
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Request focus for keyboard input after widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  KeyEventResult _handleKeyEvent(final services.KeyEvent event) {
    // Emit raw keyboard events for logging and debugging
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (event is services.KeyDownEvent) {
      widget.world.events.writer<RawKeyDownEvent>().send(
        RawKeyDownEvent(key: event.logicalKey, timestamp: timestamp),
      );
    } else if (event is services.KeyUpEvent) {
      widget.world.events.writer<RawKeyUpEvent>().send(
        RawKeyUpEvent(key: event.logicalKey, timestamp: timestamp),
      );
    } else if (event is services.KeyRepeatEvent) {
      widget.world.events.writer<RawKeyRepeatEvent>().send(
        RawKeyRepeatEvent(key: event.logicalKey, timestamp: timestamp),
      );
    }

    // Always return handled to prevent macOS system beep
    // We're already processing all keys (sending to ECS for logging/debugging),
    // so returning handled prevents the system beep without losing functionality.
    // If system keys (Tab, Escape, etc.) need to work, they should be configured
    // in the input map or handled by a parent widget.
    return KeyEventResult.handled;
  }

  void _sendPointerEvent(final PointerEvent event) {
    final worldPos = _toWorldCoords(event.localPosition, context);
    final modifierMask = modifierMaskFromPressedKeys(
      services.HardwareKeyboard.instance.logicalKeysPressed,
    );
    if (event is PointerDownEvent) {
      widget.world.events.writer<RawPointerDownEvent>().send(
        RawPointerDownEvent(
          position: event.localPosition,
          worldPosition: worldPos,
          timestamp: event.timeStamp.inMilliseconds,
          pointer: event.pointer,
          buttons: event.buttons,
          modifierMask: modifierMask,
        ),
      );
    } else if (event is PointerHoverEvent) {
      widget.world.events.writer<RawPointerHoverEvent>().send(
        RawPointerHoverEvent(
          position: event.localPosition,
          worldPosition: worldPos,
          timestamp: event.timeStamp.inMilliseconds,
          pointer: event.pointer,
          buttons: event.buttons,
          modifierMask: modifierMask,
        ),
      );
    } else if (event is PointerMoveEvent) {
      widget.world.events.writer<RawPointerMoveEvent>().send(
        RawPointerMoveEvent(
          position: event.localPosition,
          worldPosition: worldPos,
          delta: event.delta,
          timestamp: event.timeStamp.inMilliseconds,
          pointer: event.pointer,
          buttons: event.buttons,
          modifierMask: modifierMask,
        ),
      );
    } else if (event is PointerUpEvent) {
      widget.world.events.writer<RawPointerUpEvent>().send(
        RawPointerUpEvent(
          position: event.localPosition,
          worldPosition: worldPos,
          timestamp: event.timeStamp.inMilliseconds,
          pointer: event.pointer,
          buttons: event.buttons,
          modifierMask: modifierMask,
        ),
      );
    } else if (event is PointerCancelEvent) {
      widget.world.events.writer<RawPointerCancelEvent>().send(
        RawPointerCancelEvent(
          timestamp: event.timeStamp.inMilliseconds,
          pointer: event.pointer,
          buttons: event.buttons,
          modifierMask: modifierMask,
        ),
      );
    }
  }

  void _sendPointerSignal(final PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final worldPos = _toWorldCoords(event.localPosition, context);
      final modifierMask = modifierMaskFromPressedKeys(
        services.HardwareKeyboard.instance.logicalKeysPressed,
      );
      if (event.kind == ui.PointerDeviceKind.trackpad &&
          widget.trackpadScrollCausesPan &&
          !_hasModifier(modifierMask, inputModifierShiftMask)) {
        widget.world.events.writer<RawScaleUpdateEvent>().send(
          RawScaleUpdateEvent(
            focalPoint: event.localPosition,
            focalPointDelta: -event.scrollDelta,
            scale: 1.0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        return;
      }
      widget.world.events.writer<ScrollEvent>().send(
        ScrollEvent(
          position: event.localPosition,
          worldPosition: worldPos,
          delta: event.scrollDelta,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          kind: event.kind,
          modifierMask: modifierMask,
        ),
      );
    }
  }

  void _sendScaleEvent(final details) {
    if (details is ScaleStartDetails) {
      widget.world.events.writer<RawScaleStartEvent>().send(
        RawScaleStartEvent(
          focalPoint: details.localFocalPoint,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } else if (details is ScaleUpdateDetails) {
      widget.world.events.writer<RawScaleUpdateEvent>().send(
        RawScaleUpdateEvent(
          focalPoint: details.localFocalPoint,
          focalPointDelta: details.focalPointDelta,
          rotation: details.rotation,
          pointerCount: details.pointerCount,
          scale: details.scale,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          worldFocalPoint: _toWorldCoords(details.localFocalPoint, context),
        ),
      );
    } else if (details is ScaleEndDetails) {
      widget.world.events.writer<RawScaleEndEvent>().send(
        RawScaleEndEvent(timestamp: DateTime.now().millisecondsSinceEpoch),
      );
    }
  }

  ui.Offset _toWorldCoords(
    final ui.Offset screenPos,
    final BuildContext context,
  ) {
    // Use the actual widget viewport size from LayoutBuilder, not full screen size
    // This ensures coordinate conversion uses the correct viewport dimensions
    final viewportSize = _viewportSize;

    // Use provided coordinate converter if available
    if (widget.toWorldCoords != null) {
      return widget.toWorldCoords!(screenPos, viewportSize);
    }

    // Default: screen coordinates = world coordinates
    return screenPos;
  }

  bool _hasModifier(final int modifierMask, final int mask) =>
      (modifierMask & mask) != 0;
}
