import 'package:ecsly/ecsly.dart';

import 'component_naming.dart';
import 'entity_refs.dart';
import 'object_component_codec.dart';

/// Captures all SoA column data for an entity as a flat JSON map.
///
/// Reads every typed component column the entity participates in and
/// serializes the raw values. Keys are `{componentId}_{offset}`.
///
/// Object-tier components are captured only when a codec for their type is
/// present in [codecs]; otherwise they are skipped.
///
/// [includeOnly] limits capture to specific component IDs (optimization).
Map<String, Object?>? captureEntityColumns(
  World world,
  Entity entity, {
  Set<ComponentId>? includeOnly,
  ObjectComponentCodecRegistry? codecs,
}) {
  if (!world.entities.isAlive(entity)) return null;
  final (ext, ok) = world.getEntityExtension(entity);
  if (!ok) return null;

  final archetype = ext.archetype;
  final row = archetype.getRowIndex(entity, world.entities);
  if (row == null) return null;

  final snapshot = <String, Object?>{};

  for (final componentId in archetype.componentIds) {
    if (includeOnly != null && !includeOnly.contains(componentId)) continue;

    final column = archetype.getColumn(componentId);
    if (column == null) continue;

    switch (column) {
      case final FloatColumn fc:
        for (var i = 0; i < fc.stride; i++) {
          snapshot['${componentId.value}_$i'] = fc.getValue(row, i);
        }
      case final IntColumn ic:
        for (var i = 0; i < ic.stride; i++) {
          snapshot['${componentId.value}_$i'] = ic.getValue(row, i);
        }
      case final Uint8Column uc:
        snapshot['${componentId.value}_0'] = uc.getValue(row);
      case final ObjectColumn _:
        _captureObjectColumn(
          world,
          archetype,
          componentId,
          row,
          snapshot,
          codecs,
          EntityRefEncoder(world),
        );
    }
  }

  return snapshot.isEmpty ? null : snapshot;
}

/// Restores column data for an entity from a flat JSON map.
///
/// Inverse of [captureEntityColumns]. Writes values back into the
/// entity's columns using the same key format. Entity references inside
/// object payloads resolve through [refs].
void restoreEntityColumns(
  World world,
  Entity entity,
  Map<String, Object?> snapshot, {
  required EntityRefResolver refs,
  Set<ComponentId>? includeOnly,
  ObjectComponentCodecRegistry? codecs,
}) {
  final (ext, ok) = world.getEntityExtension(entity);
  if (!ok) return;

  final archetype = ext.archetype;
  final row = archetype.getRowIndex(entity, world.entities);
  if (row == null) return;

  for (final componentId in archetype.componentIds) {
    if (includeOnly != null && !includeOnly.contains(componentId)) continue;

    final column = archetype.getColumn(componentId);
    if (column == null) continue;

    switch (column) {
      case final FloatColumn fc:
        for (var i = 0; i < fc.stride; i++) {
          final value = snapshot['${componentId.value}_$i'];
          if (value is num) {
            fc.setValue(row, i, value.toDouble());
          }
        }
      case final IntColumn ic:
        for (var i = 0; i < ic.stride; i++) {
          final value = snapshot['${componentId.value}_$i'];
          if (value is num) {
            ic.setValue(row, i, value.toInt());
          }
        }
      case final Uint8Column uc:
        final value = snapshot['${componentId.value}_0'];
        if (value is num) {
          uc.setValue(row, value.toInt());
        }
      case final ObjectColumn _:
        _restoreObjectColumn(
          world,
          archetype,
          componentId,
          row,
          snapshot,
          codecs,
          refs,
        );
    }
  }
}

void _captureObjectColumn(
  World world,
  Archetype archetype,
  ComponentId componentId,
  int row,
  Map<String, Object?> snapshot,
  ObjectComponentCodecRegistry? codecs,
  EntityRefEncoder refs,
) {
  if (codecs == null) return;
  final identity = componentSnapshotName(world, componentId);
  if (identity == null) return;
  final codec = _codecFor(world, componentId, identity, codecs);
  if (codec == null) return;

  final column = archetype.getColumn(componentId);
  if (column is! ObjectColumn) return;
  if (row >= column.length) return;
  final component = column.getValue(row);
  if (component == null) return;
  snapshot['obj_${componentId.value}'] = <String, Object?>{
    'type': identity,
    'value': codec.toJson(component as dynamic, refs),
  };
}

void _restoreObjectColumn(
  World world,
  Archetype archetype,
  ComponentId componentId,
  int row,
  Map<String, Object?> snapshot,
  ObjectComponentCodecRegistry? codecs,
  EntityRefResolver refs,
) {
  if (codecs == null) return;
  final identity = componentSnapshotName(world, componentId);
  if (identity == null) return;
  final codec = _codecFor(world, componentId, identity, codecs);
  if (codec == null) return;

  final raw = snapshot['obj_${componentId.value}'];
  if (raw is! Map) return;
  final component = codec.fromJson(raw['value'], refs);
  final column = archetype.getColumn(componentId);
  if (column != null) {
    _writeObjectValue(column, row, component);
  }
}

void _writeObjectValue(
  DataColumn column,
  int row,
  Component component,
) {
  if (column case final ObjectColumn c) {
    while (row >= c.length) {
      c.addBlank();
    }
    (c as dynamic).setValue(row, component);
  }
}

/// Codec lookup tolerant of naming: try the snapshot identity first, then
/// the bare type name (codecs registered before the component carried a
/// stable name).
ObjectComponentCodec? _codecFor(
  World world,
  ComponentId componentId,
  String identity,
  ObjectComponentCodecRegistry codecs,
) =>
    codecs.lookup(identity) ??
    codecs.lookup(_typeNameOrNull(world, componentId) ?? '');

String? _typeNameOrNull(World world, ComponentId componentId) {
  try {
    return world.components.getType(componentId).toString();
    // ignore: avoid_catching_errors
  } on EcsStateError {
    return null;
  }
}
