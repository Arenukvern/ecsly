import 'dart:developer';

import 'package:ecsly/ecsly.dart';

import 'components.dart';

void regenerateEnergy(final World world) {
  // queryExt asks for the marker component and the facade type together:
  // EnergyComponent selects the storage; Energy gives typed column access.
  for (final (entity, energy) in world.queryExt<EnergyComponent, Energy>()) {
    energy.current = (energy.current + energy.regenPerTick)
        .clamp(0, energy.max)
        .toDouble();

    // DebugNoteComponent is intentionally cold object data. We read it only for
    // output, keeping the hot numeric state in the Energy column.
    final note = entity.toEntity().get<DebugNoteComponent>()?.text;
    log('${note ?? 'entity'} energy=${energy.current.toStringAsFixed(1)}');
  }
}

void main() {
  final world = World();

  registerEnergyExampleComponents(world);

  final entity = world.reserveEmptyEntity().entity;
  world.spawnBundle(
    entity,
    ComponentBundle.fromLists(
      const [DebugNoteComponent('reactor-cell-a')],
      const [(EnergyComponent, Energy)],
    ),
  );
  world.flush();

  final (entityExt, isValid) = world.getEntityExtension(entity);
  if (!isValid) {
    return;
  }

  // Extension components are zero-initialized when added. Set their fields
  // through the facade after the structural spawn has been flushed.
  final energy = entityExt.getOrCreate<EnergyComponent, Energy>();
  energy.current = 2.0;
  energy.max = 10.0;
  energy.regenPerTick = 3.5;

  // Schedules group systems into explicit execution stages. This keeps update
  // order visible and lets the runtime manage flush boundaries deliberately.
  world.createSchedule('Update').add(regenerateEnergy);
  world.runSchedule('Update');
  world.flush();
}
