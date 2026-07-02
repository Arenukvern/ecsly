import 'dart:developer';

import 'package:ecsly/ecsly.dart';

/// Tiny object component for the pub.dev example entry point.
///
/// `ecsly` also supports packed typed-data columns for hotter loops, but an
/// object component keeps the first example intentionally small.
class CounterComponent extends Component {
  CounterComponent(this.value);

  int value;
}

void main() {
  final world = World();
  world.components.registerObjectComponent<CounterComponent>();

  final entity = world.reserveEmptyEntity().entity;
  world.spawnBundle(entity, ComponentBundle.fromLists([CounterComponent(1)]));
  world.flush();

  for (final (_, counter) in world.queryMut<CounterComponent>()) {
    counter.value += 1;
    log('counter=${counter.value}');
  }
}
