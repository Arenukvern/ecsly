import '../../components/components.dart';
import '../command_queue.dart';

class ComponentCommands {
  const ComponentCommands({required this.queue, required this.component});
  final CommandQueue queue;
  final Component component;
}
