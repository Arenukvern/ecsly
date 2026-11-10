/// Event-driven gesture input system for zero-GC performance.
library;

import 'dart:ui' as ui;

import 'package:ecsly/ecsly.dart';
import 'package:meta/meta.dart';

/// Double-tap gesture event - two quick taps in sequence.
class DoubleTapEvent extends GestureEvent {
  const DoubleTapEvent({
    required super.position,
    required super.worldPosition,
    required super.timestamp,
  });

  static DoubleTapEvent fromDoubleFields(final List<double> fields) =>
      DoubleTapEvent(
        position: ui.Offset(fields[0], fields[1]),
        worldPosition: ui.Offset(fields[2], fields[3]),
        timestamp: fields[4].toInt(),
      );
}

/// Drag gesture event - pointer movement while pressed.
class DragEvent extends GestureEvent {
  final ui.Offset startPosition;

  final ui.Offset startWorldPosition;
  final ui.Offset delta;
  final int buttons;
  final int modifierMask;
  const DragEvent({
    required super.position,
    required super.worldPosition,
    required this.delta,
    required this.startPosition,
    required this.startWorldPosition,
    required super.timestamp,
    this.buttons = 0,
    this.modifierMask = 0,
  });

  @override
  List<double> get numericFields => [
    ...super.numericFields,
    startPosition.dx,
    startPosition.dy,
    startWorldPosition.dx,
    startWorldPosition.dy,
    delta.dx,
    delta.dy,
    buttons.toDouble(),
    modifierMask.toDouble(),
  ];

  static DragEvent fromDoubleFields(final List<double> fields) => DragEvent(
    position: ui.Offset(fields[0], fields[1]),
    worldPosition: ui.Offset(fields[2], fields[3]),
    timestamp: fields[4].toInt(),
    startPosition: ui.Offset(fields[5], fields[6]),
    startWorldPosition: ui.Offset(fields[7], fields[8]),
    delta: ui.Offset(fields[9], fields[10]),
    buttons: fields.length >= 13 ? fields[11].toInt() : 0,
    modifierMask: fields.length >= 13 ? fields[12].toInt() : 0,
  );
}

/// Entity-specific drag event - dispatched to specific entities after hit testing.
class EntityDragEvent extends GestureEvent {
  final Entity entity;

  final ui.Offset delta;
  const EntityDragEvent({
    required this.entity,
    required super.position,
    required super.worldPosition,
    required this.delta,
    required super.timestamp,
  });

  @override
  List<double> get numericFields => [
    entity.indexValue.toDouble(),
    entity.generation.value.toDouble(),
    ...super.numericFields,
    delta.dx,
    delta.dy,
  ];

  static EntityDragEvent fromDoubleFields(final List<double> fields) =>
      EntityDragEvent(
        entity: Entity.create(fields[0].toInt(), fields[1].toInt()),
        position: ui.Offset(fields[2], fields[3]),
        worldPosition: ui.Offset(fields[4], fields[5]),
        timestamp: fields[6].toInt(),
        delta: ui.Offset(fields[7], fields[8]),
      );
}

/// Entity-specific long-press event - dispatched to specific entities after hit testing.
class EntityLongPressEvent extends GestureEvent {
  final Entity entity;

  const EntityLongPressEvent({
    required this.entity,
    required super.position,
    required super.worldPosition,
    required super.timestamp,
  });

  @override
  List<double> get numericFields => [
    entity.indexValue.toDouble(),
    entity.generation.value.toDouble(),
    ...super.numericFields,
  ];

  static EntityLongPressEvent fromDoubleFields(final List<double> fields) =>
      EntityLongPressEvent(
        entity: Entity.create(fields[0].toInt(), fields[1].toInt()),
        position: ui.Offset(fields[2], fields[3]),
        worldPosition: ui.Offset(fields[4], fields[5]),
        timestamp: fields[6].toInt(),
      );
}

/// Entity-specific secondary tap event - dispatched to specific entities after hit testing.
class EntitySecondaryTapEvent extends GestureEvent {
  final Entity entity;

  const EntitySecondaryTapEvent({
    required this.entity,
    required super.position,
    required super.worldPosition,
    required super.timestamp,
  });

  @override
  List<double> get numericFields => [
    entity.indexValue.toDouble(),
    entity.generation.value.toDouble(),
    ...super.numericFields,
  ];

  static EntitySecondaryTapEvent fromDoubleFields(final List<double> fields) =>
      EntitySecondaryTapEvent(
        entity: Entity.create(fields[0].toInt(), fields[1].toInt()),
        position: ui.Offset(fields[2], fields[3]),
        worldPosition: ui.Offset(fields[4], fields[5]),
        timestamp: fields[6].toInt(),
      );
}

/// Entity-specific tap event - dispatched to specific entities after hit testing.
class EntityTapEvent extends GestureEvent {
  final Entity entity;

  const EntityTapEvent({
    required this.entity,
    required super.position,
    required super.worldPosition,
    required super.timestamp,
  });

  @override
  List<double> get numericFields => [
    entity.indexValue.toDouble(),
    entity.generation.value.toDouble(),
    ...super.numericFields,
  ];

  static EntityTapEvent fromDoubleFields(final List<double> fields) =>
      EntityTapEvent(
        entity: Entity.create(fields[0].toInt(), fields[1].toInt()),
        position: ui.Offset(fields[2], fields[3]),
        worldPosition: ui.Offset(fields[4], fields[5]),
        timestamp: fields[6].toInt(),
      );
}

/// Event dispatched when an entity is selected.
class EntitySelectedEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final Entity entity;
  final DateTime timestamp;

  const EntitySelectedEvent({required this.entity, required this.timestamp});

  @override
  List<double> get numericFields => [
    entity.indexValue.toDouble(),
    entity.generation.value.toDouble(),
    timestamp.millisecondsSinceEpoch.toDouble(),
  ];

  static EntitySelectedEvent fromDoubleFields(final List<double> fields) =>
      EntitySelectedEvent(
        entity: Entity.create(fields[0].toInt(), fields[1].toInt()),
        timestamp: DateTime.fromMillisecondsSinceEpoch(fields[2].toInt()),
      );
}

/// Event dispatched when an entity is deselected.
class EntityDeselectedEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final Entity entity;
  final DateTime timestamp;

  const EntityDeselectedEvent({required this.entity, required this.timestamp});

  @override
  List<double> get numericFields => [
    entity.indexValue.toDouble(),
    entity.generation.value.toDouble(),
    timestamp.millisecondsSinceEpoch.toDouble(),
  ];

  static EntityDeselectedEvent fromDoubleFields(final List<double> fields) =>
      EntityDeselectedEvent(
        entity: Entity.create(fields[0].toInt(), fields[1].toInt()),
        timestamp: DateTime.fromMillisecondsSinceEpoch(fields[2].toInt()),
      );
}

sealed class GestureEvent extends EcsEvent
    with TypedDataEventMixin
    implements TypedDataEvent {
  final ui.Offset position;

  final ui.Offset worldPosition;
  final int timestamp;
  const GestureEvent({
    required this.position,
    required this.worldPosition,
    required this.timestamp,
  });
  @override
  @mustCallSuper
  List<double> get numericFields => [
    position.dx,
    position.dy,
    worldPosition.dx,
    worldPosition.dy,
    timestamp.toDouble(),
  ];
}

/// Long-press gesture event - extended touch hold.
class LongPressEvent extends GestureEvent {
  const LongPressEvent({
    required super.position,
    required super.worldPosition,
    required super.timestamp,
  });

  static LongPressEvent fromDoubleFields(final List<double> fields) =>
      LongPressEvent(
        position: ui.Offset(fields[0], fields[1]),
        worldPosition: ui.Offset(fields[2], fields[3]),
        timestamp: fields[4].toInt(),
      );
}

/// Pinch gesture event - two-finger scale/zoom.
class PinchEvent extends GestureEvent {
  final ui.Offset focalPointDelta;

  final double rotation;
  final double scale;

  final ui.Offset focalPoint;
  final int pointerCount;
  const PinchEvent({
    required super.position,
    required super.worldPosition,
    required this.scale,
    required this.focalPoint,
    this.focalPointDelta = ui.Offset.zero,
    this.rotation = 0.0,
    this.pointerCount = 0,
    required super.timestamp,
  });

  @override
  List<double> get numericFields => [
    ...super.numericFields,
    scale,
    focalPoint.dx,
    focalPoint.dy,
    focalPointDelta.dx,
    focalPointDelta.dy,
    rotation,
    pointerCount.toDouble(),
  ];

  static PinchEvent fromDoubleFields(final List<double> fields) => PinchEvent(
    position: ui.Offset(fields[0], fields[1]),
    worldPosition: ui.Offset(fields[2], fields[3]),
    timestamp: fields[4].toInt(),
    scale: fields[5],
    focalPoint: ui.Offset(fields[6], fields[7]),
    focalPointDelta: fields.length >= 10
        ? ui.Offset(fields[8], fields[9])
        : ui.Offset.zero,
    rotation: fields.length >= 11 ? fields[10] : 0.0,
    pointerCount: fields.length >= 12 ? fields[11].toInt() : 0,
  );
}

/// Scroll gesture event - mouse wheel or multi-touch scroll.
class ScrollEvent extends GestureEvent {
  final ui.Offset delta;
  final ui.PointerDeviceKind kind;
  final int modifierMask;

  const ScrollEvent({
    required super.position,
    required super.worldPosition,
    required this.delta,
    required super.timestamp,
    this.kind = ui.PointerDeviceKind.mouse,
    this.modifierMask = 0,
  });

  @override
  List<double> get numericFields => [
    ...super.numericFields,
    delta.dx,
    delta.dy,
    _pointerDeviceKindCode(kind).toDouble(),
    modifierMask.toDouble(),
  ];

  static ScrollEvent fromDoubleFields(final List<double> fields) => ScrollEvent(
    position: ui.Offset(fields[0], fields[1]),
    worldPosition: ui.Offset(fields[2], fields[3]),
    delta: ui.Offset(fields[5], fields[6]),
    timestamp: fields[4].toInt(),
    kind: fields.length >= 8
        ? _pointerDeviceKindFromCode(fields[7].toInt())
        : ui.PointerDeviceKind.mouse,
    modifierMask: fields.length >= 9 ? fields[8].toInt() : 0,
  );
}

int _pointerDeviceKindCode(final ui.PointerDeviceKind kind) => switch (kind) {
  ui.PointerDeviceKind.mouse => 0,
  ui.PointerDeviceKind.touch => 1,
  ui.PointerDeviceKind.stylus => 2,
  ui.PointerDeviceKind.invertedStylus => 3,
  ui.PointerDeviceKind.trackpad => 4,
  _ => 5,
};

ui.PointerDeviceKind _pointerDeviceKindFromCode(final int code) =>
    switch (code) {
      0 => ui.PointerDeviceKind.mouse,
      1 => ui.PointerDeviceKind.touch,
      2 => ui.PointerDeviceKind.stylus,
      3 => ui.PointerDeviceKind.invertedStylus,
      4 => ui.PointerDeviceKind.trackpad,
      _ => ui.PointerDeviceKind.mouse,
    };

/// Secondary tap gesture event - right-click or secondary touch.
class SecondaryTapEvent extends GestureEvent {
  const SecondaryTapEvent({
    required super.position,
    required super.worldPosition,
    required super.timestamp,
  });

  static SecondaryTapEvent fromDoubleFields(final List<double> fields) =>
      SecondaryTapEvent(
        position: ui.Offset(fields[0], fields[1]),
        worldPosition: ui.Offset(fields[2], fields[3]),
        timestamp: fields[4].toInt(),
      );
}

/// Tap gesture event - single quick touch/release.
class TapEvent extends GestureEvent {
  const TapEvent({
    required super.position,
    required super.worldPosition,
    required super.timestamp,
  });

  static TapEvent fromDoubleFields(final List<double> fields) => TapEvent(
    position: ui.Offset(fields[0], fields[1]),
    worldPosition: ui.Offset(fields[2], fields[3]),
    timestamp: fields[4].toInt(),
  );
}
