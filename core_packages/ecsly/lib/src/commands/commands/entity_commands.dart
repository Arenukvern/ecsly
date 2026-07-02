import '../../components/components.dart';
import '../../entities/entities.dart';
import '../commands.dart';

/// Not serializable command container.
class EntityCommands {
  const EntityCommands({required this.queue, required this.entity});
  final CommandQueue queue;
  final Entity entity;
}

extension EntityCommandsX on EntityCommands {
  void despawn() => queue.push(DestroyEntityCommand(entity));
  void remove<T extends Component>() {
    final componentId = queue.world.components.getComponentId<T>();
    queue.push(RemoveComponentCommand<T>(entity, componentId));
  }

  void upsert<T extends Component>(final T component) =>
      queue.push(UpsertComponentCommand<T>(entity, component));
}
