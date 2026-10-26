import 'package:ecsly/ecsly.dart';

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
  final World world,
  final Entity entity, {
  final Set<ComponentId>? includeOnly,
  final ObjectComponentCodecRegistry? codecs,
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
        );
    }
  }

  return snapshot.isEmpty ? null : snapshot;
}

/// Restores column data for an entity from a flat JSON map.
///
/// Inverse of [captureEntityColumns]. Writes values back into the
/// entity's columns using the same key format.
void restoreEntityColumns(
  final World world,
  final Entity entity,
  final Map<String, Object?> snapshot, {
  final Set<ComponentId>? includeOnly,
  final ObjectComponentCodecRegistry? codecs,
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
        );
    }
  }
}

void _captureObjectColumn(
  final World world,
  final Archetype archetype,
  final ComponentId componentId,
  final int row,
  final Map<String, Object?> snapshot,
  final ObjectComponentCodecRegistry? codecs,
) {
  if (codecs == null) return;
  final typeName = _componentTypeName(world, componentId);
  if (typeName == null) return;
  final codec = codecs.lookup(typeName);
  if (codec == null) return;

  final column = archetype.getColumn(componentId);
  if (column is! ObjectColumn) return;
  if (row >= column.length) return;
  final component = column.getValue(row);
  if (component == null) return;
  snapshot['obj_${componentId.value}'] = <String, Object?>{
    'type': typeName,
    'value': codec.toJson(component as dynamic),
  };
}

void _restoreObjectColumn(
  final World world,
  final Archetype archetype,
  final ComponentId componentId,
  final int row,
  final Map<String, Object?> snapshot,
  final ObjectComponentCodecRegistry? codecs,
) {
  if (codecs == null) return;
  final typeName = _componentTypeName(world, componentId);
  if (typeName == null) return;
  final codec = codecs.lookup(typeName);
  if (codec == null) return;

  final raw = snapshot['obj_${componentId.value}'];
  if (raw is! Map) return;
  final component = codec.fromJson(raw['value']);
  final column = archetype.getColumn(componentId);
  if (column != null) {
    _writeObjectValue(column, row, component);
  }
}

void _writeObjectValue(
  final DataColumn column,
  final int row,
  final Component component,
) {
  if (column case final ObjectColumn c) {
    while (row >= c.length) {
      c.addBlank();
    }
    (c as dynamic).setValue(row, component);
  }
}

String? _componentTypeName(final World world, final ComponentId componentId) {
  try {
    return world.components.getType(componentId).toString();
    // ignore: avoid_catching_errors
  } on EcsStateError {
    return null;
  }
}
