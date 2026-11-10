/// Raw input events from Flutter widgets.
///
/// These are low-level pointer and gesture events that are sent directly
/// from UnifiedInputWidget without any classification or processing.
/// Gesture classification systems will process these into high-level gestures.
library;

import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:flutter/services.dart';

const int inputModifierShiftMask = 1 << 0;
const int inputModifierCtrlMask = 1 << 1;
const int inputModifierAltMask = 1 << 2;
const int inputModifierMetaMask = 1 << 3;

int modifierMaskFromPressedKeys(
  final Iterable<LogicalKeyboardKey> pressedKeys,
) {
  final keys = pressedKeys is Set<LogicalKeyboardKey>
      ? pressedKeys
      : pressedKeys.toSet();
  var mask = 0;
  if (keys.contains(LogicalKeyboardKey.shiftLeft) ||
      keys.contains(LogicalKeyboardKey.shiftRight)) {
    mask |= inputModifierShiftMask;
  }
  if (keys.contains(LogicalKeyboardKey.controlLeft) ||
      keys.contains(LogicalKeyboardKey.controlRight)) {
    mask |= inputModifierCtrlMask;
  }
  if (keys.contains(LogicalKeyboardKey.altLeft) ||
      keys.contains(LogicalKeyboardKey.altRight)) {
    mask |= inputModifierAltMask;
  }
  if (keys.contains(LogicalKeyboardKey.metaLeft) ||
      keys.contains(LogicalKeyboardKey.metaRight)) {
    mask |= inputModifierMetaMask;
  }
  return mask;
}

int _intField(final List<double> fields, final int index) =>
    index < fields.length ? fields[index].toInt() : 0;

/// Raw key down event (key pressed).
class RawKeyDownEvent extends RawKeyEvent {
  const RawKeyDownEvent({required super.key, required super.timestamp});

  static RawKeyDownEvent fromDoubleFields(final List<double> fields) =>
      RawKeyDownEvent(
        key: LogicalKeyboardKey(fields[0].toInt()),
        timestamp: fields[1].toInt(),
      );
}

/// Base class for raw keyboard events.
sealed class RawKeyEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final LogicalKeyboardKey key;
  final int timestamp;

  const RawKeyEvent({required this.key, required this.timestamp});

  @override
  List<double> get numericFields => [
    key.keyId.toDouble(),
    timestamp.toDouble(),
  ];
}

/// Raw key repeat event (key held down, auto-repeating).
class RawKeyRepeatEvent extends RawKeyEvent {
  const RawKeyRepeatEvent({required super.key, required super.timestamp});

  static RawKeyRepeatEvent fromDoubleFields(final List<double> fields) =>
      RawKeyRepeatEvent(
        key: LogicalKeyboardKey(fields[0].toInt()),
        timestamp: fields[1].toInt(),
      );
}

/// Raw key up event (key released).
class RawKeyUpEvent extends RawKeyEvent {
  const RawKeyUpEvent({required super.key, required super.timestamp});

  static RawKeyUpEvent fromDoubleFields(final List<double> fields) =>
      RawKeyUpEvent(
        key: LogicalKeyboardKey(fields[0].toInt()),
        timestamp: fields[1].toInt(),
      );
}

/// Raw pointer cancel event.
class RawPointerCancelEvent extends RawPointerEvent {
  const RawPointerCancelEvent({
    required super.timestamp,
    required super.pointer,
    super.buttons,
    super.modifierMask,
  }) : super(position: ui.Offset.zero, worldPosition: ui.Offset.zero);

  static RawPointerCancelEvent fromDoubleFields(final List<double> fields) =>
      RawPointerCancelEvent(
        timestamp: fields[4].toInt(),
        pointer: fields[5].toInt(),
        buttons: _intField(fields, 6),
        modifierMask: _intField(fields, 7),
      );
}

/// Raw pointer down event.
class RawPointerDownEvent extends RawPointerEvent {
  const RawPointerDownEvent({
    required super.position,
    required super.worldPosition,
    required super.timestamp,
    required super.pointer,
    super.buttons,
    super.modifierMask,
  });

  static RawPointerDownEvent fromDoubleFields(final List<double> fields) =>
      RawPointerDownEvent(
        position: ui.Offset(fields[0], fields[1]),
        worldPosition: ui.Offset(fields[2], fields[3]),
        timestamp: fields[4].toInt(),
        pointer: fields[5].toInt(),
        buttons: _intField(fields, 6),
        modifierMask: _intField(fields, 7),
      );
}

/// Base class for raw pointer events.
sealed class RawPointerEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final ui.Offset position;

  final ui.Offset worldPosition;
  final int timestamp;
  final int pointer;
  final int buttons;
  final int modifierMask;
  const RawPointerEvent({
    required this.position,
    required this.worldPosition,
    required this.timestamp,
    required this.pointer,
    this.buttons = 0,
    this.modifierMask = 0,
  });

  @override
  List<double> get numericFields => [
    position.dx,
    position.dy,
    worldPosition.dx,
    worldPosition.dy,
    timestamp.toDouble(),
    pointer.toDouble(),
    buttons.toDouble(),
    modifierMask.toDouble(),
  ];
}

/// Raw pointer move event.
class RawPointerMoveEvent extends RawPointerEvent {
  final ui.Offset delta;

  const RawPointerMoveEvent({
    required super.position,
    required super.worldPosition,
    required this.delta,
    required super.timestamp,
    required super.pointer,
    super.buttons,
    super.modifierMask,
  });

  @override
  List<double> get numericFields => [
    position.dx,
    position.dy,
    worldPosition.dx,
    worldPosition.dy,
    timestamp.toDouble(),
    pointer.toDouble(),
    delta.dx,
    delta.dy,
    buttons.toDouble(),
    modifierMask.toDouble(),
  ];

  static RawPointerMoveEvent fromDoubleFields(final List<double> fields) =>
      RawPointerMoveEvent(
        position: ui.Offset(fields[0], fields[1]),
        worldPosition: ui.Offset(fields[2], fields[3]),
        timestamp: fields[4].toInt(),
        pointer: fields[5].toInt(),
        delta: ui.Offset(fields[6], fields[7]),
        buttons: _intField(fields, 8),
        modifierMask: _intField(fields, 9),
      );
}

/// Raw pointer up event.
class RawPointerUpEvent extends RawPointerEvent {
  const RawPointerUpEvent({
    required super.position,
    required super.worldPosition,
    required super.timestamp,
    required super.pointer,
    super.buttons,
    super.modifierMask,
  });

  static RawPointerUpEvent fromDoubleFields(final List<double> fields) =>
      RawPointerUpEvent(
        position: ui.Offset(fields[0], fields[1]),
        worldPosition: ui.Offset(fields[2], fields[3]),
        timestamp: fields[4].toInt(),
        pointer: fields[5].toInt(),
        buttons: _intField(fields, 6),
        modifierMask: _intField(fields, 7),
      );
}

/// Raw scale end event (pinch gesture finish).
class RawScaleEndEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final int timestamp;

  const RawScaleEndEvent({required this.timestamp});

  @override
  List<double> get numericFields => [timestamp.toDouble()];

  static RawScaleEndEvent fromDoubleFields(final List<double> fields) =>
      RawScaleEndEvent(timestamp: fields[0].toInt());
}

/// Raw scale start event (pinch gesture begin).
class RawScaleStartEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final ui.Offset focalPoint;

  final int timestamp;
  const RawScaleStartEvent({required this.focalPoint, required this.timestamp});

  @override
  List<double> get numericFields => [
    focalPoint.dx,
    focalPoint.dy,
    timestamp.toDouble(),
  ];

  static RawScaleStartEvent fromDoubleFields(final List<double> fields) =>
      RawScaleStartEvent(
        focalPoint: ui.Offset(fields[0], fields[1]),
        timestamp: fields[2].toInt(),
      );
}

/// Raw scale update event (pinch gesture continue).
class RawScaleUpdateEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final ui.Offset focalPoint;
  final ui.Offset focalPointDelta;

  final double rotation;
  final double scale;
  final int pointerCount;
  final int timestamp;
  const RawScaleUpdateEvent({
    required this.focalPoint,
    required this.scale,
    this.focalPointDelta = ui.Offset.zero,
    this.rotation = 0.0,
    this.pointerCount = 0,
    required this.timestamp,
  });

  @override
  List<double> get numericFields => [
    focalPoint.dx,
    focalPoint.dy,
    scale,
    timestamp.toDouble(),
    focalPointDelta.dx,
    focalPointDelta.dy,
    rotation,
    pointerCount.toDouble(),
  ];

  static RawScaleUpdateEvent fromDoubleFields(final List<double> fields) =>
      RawScaleUpdateEvent(
        focalPoint: ui.Offset(fields[0], fields[1]),
        scale: fields[2],
        timestamp: fields[3].toInt(),
        focalPointDelta: fields.length >= 6
            ? ui.Offset(fields[4], fields[5])
            : ui.Offset.zero,
        rotation: fields.length >= 7 ? fields[6] : 0.0,
        pointerCount: fields.length >= 8 ? fields[7].toInt() : 0,
      );
}
