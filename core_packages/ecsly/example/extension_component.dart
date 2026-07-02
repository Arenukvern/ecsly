import 'package:ecsly/ecsly.dart';

import 'components.dart';

void main() {
  final world = World();
  registerEnergyExampleComponents(world);

  final reactor = world.reserveEmptyEntity().entity;
  world.spawnBundle(
    reactor,
    ComponentBundle.fromLists(
      const [DebugNoteComponent('reactor')],
      const [(EnergyComponent, Energy)],
    ),
  );
  world.flush();

  // Extension components are zero-initialized when attached. Use the facade to
  // write the packed column data after the entity is visible.
  final (entity, isValid) = world.getEntityExtension(reactor);
  if (!isValid) return;

  final energy = entity.getExtension<EnergyComponent, Energy>()!;
  energy.current = 4;
  energy.max = 10;
  energy.regenPerTick = 1.5;

  for (final (entity, energy) in world.queryExt<EnergyComponent, Energy>()) {
    final note = entity.toEntity().get<DebugNoteComponent>()?.text ?? 'entity';
    print('$note energy=${energy.current}/${energy.max}');
  }
}
