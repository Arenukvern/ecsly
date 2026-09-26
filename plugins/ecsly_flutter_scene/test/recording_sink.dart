// ignore_for_file: prefer_final_parameters, prefer_const_constructors
import 'package:ecsly/ecsly.dart';
import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';

/// A recording sink for pure-core tests — never touches a renderer.
class RecordingSink implements SceneSink {
  final adds = <String>[];
  final updates = <String>[];
  final removes = <String>[];
  final Map<String, VisualState> stored = {};

  @override
  int get count => stored.length;

  @override
  void add(String key, VisualState visual) {
    adds.add(key);
    stored[key] = visual;
  }

  @override
  void update(String key, VisualState visual) {
    updates.add(key);
    stored[key] = visual;
  }

  @override
  void remove(String key) {
    removes.add(key);
    stored.remove(key);
  }
}

/// A test-only marker component (runtime-registered per test world).
class Marker extends Component {
  const Marker(this.kind);
  final String kind;
}

World buildWorld() {
  final world = World();
  world.components.registerObjectComponent<Marker>();
  world.flush();
  return world;
}
