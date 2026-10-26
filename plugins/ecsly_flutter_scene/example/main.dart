import 'dart:math' as math;

import 'package:ecsly/ecsly.dart';
import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter/material.dart';

/// A minimal example: ten markers in a ring, rendered as 3D shapes with
/// an orbiting inspector camera. Run with Flutter GPU enabled:
/// `flutter run -d macos --enable-flutter-gpu`.
void main() => runApp(const _ExampleApp());

class Marker extends Component {
  const Marker(this.label, this.hue);
  final String label;
  final int hue;
}

class _Position extends Component {
  const _Position(this.angle);
  final double angle;
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Colors.black, body: _ScenePage()),
      );
}

class _ScenePage extends StatefulWidget {
  const _ScenePage();
  @override
  State<_ScenePage> createState() => _ScenePageState();
}

class _ScenePageState extends State<_ScenePage> {
  late final World world;
  late final SceneMapping mapping;

  @override
  void initState() {
    super.initState();
    world = World();
    world.components.registerObjectComponent<Marker>();
    world.components.registerObjectComponent<_Position>();
    for (var i = 0; i < 10; i++) {
      final entity = world.spawnComponents([
        Marker('node $i', (i * 37) % 360),
        _Position(i * 6.283 / 10),
      ]);
      final angle = i * 6.283 / 10;
      // The consumer owns layout: position derives from component data.
      debugPrint('spawned ${entity.toJson()} at $angle');
    }
    world.flush();
    mapping = SceneMapping()
      ..add<Marker>(
        (entity, marker, world) {
          final pos = world.getEntity(entity).$1.get<_Position>();
          final t = pos?.angle ?? 0;
          return VisualState(
            shape: SceneShape.sphere,
            argb: 0xFF000000 | (0xFF << 16) | (marker.hue << 8),
            size: 0.5,
            position: [4 * math.cos(t), 0, 4 * math.sin(t)],
            label: marker.label,
          );
        },
      );
  }

  @override
  Widget build(BuildContext context) =>
      EcsSceneView(world: world, mapping: mapping);
}
