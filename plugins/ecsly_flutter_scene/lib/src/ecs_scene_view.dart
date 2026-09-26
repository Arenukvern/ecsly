/// The embedding widget: an ecsly World rendered as a flutter_scene 3D
/// view, with orbit gestures and per-frame binder sync. Requires
/// Flutter 3.47+ with Flutter GPU enabled on the platform, and
/// `Scene.initializeStaticResources()` before first geometry — handled
/// in state init (the static future is cached by flutter_scene itself).
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import 'ecs_scene_binder.dart';
import 'flutter_scene_sink.dart';
import 'scene_mapping.dart';

  /// The world whose mapped components this view renders (READ-ONLY —
  /// the app loop ticks it; the view never does).
class EcsSceneView extends StatefulWidget {
  /// The component→visual mapping driving the binder.
  const EcsSceneView({
    required this.world,
    required this.mapping,
    super.key,
    this.initialDistance = 24,
  });

  /// Initial camera distance from the orbit target.
  final World world;
  /// Creates the view state.
  final SceneMapping mapping;
  /// The widget state.
  final double initialDistance;

  @override
  State<EcsSceneView> createState() => _EcsSceneViewState();
}

class _EcsSceneViewState extends State<EcsSceneView> {
  bool _ready = false;
  String? _error;
  Scene? _scene;
  EcsSceneBinder? _binder;
  late final SceneCameraRig _rig = SceneCameraRig(
    distance: widget.initialDistance,
  );
  Timer? _syncTimer;
  Offset? _lastPan;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await Scene.initializeStaticResources();
      final scene = Scene();
      final binder = EcsSceneBinder(
        world: widget.world,
        sink: FlutterSceneSink(scene),
        mapping: widget.mapping,
      );
      if (!mounted) return;
      setState(() {
        _scene = scene;
        _ready = true;
      });
      // The app's own loop ticks the WORLD; the view only READS it — a
      // 30 Hz sync pass is plenty for an inspector and never contends
      // with the world schedule.
      _binder = binder;
      _syncTimer = Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => _binder?.sync(),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    if (_error != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'scene unavailable: $_error',
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ),
      );
    }
    if (!_ready || _scene == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final camera = PerspectiveCamera(
      position: _rig.cameraPosition(),
      target: _rig.cameraTarget(),
    );
    return GestureDetector(
      onPanStart: (final details) => _lastPan = details.localPosition,
      onPanUpdate: (final details) {
        final last = _lastPan ?? details.localPosition;
        setState(() {
          _rig.orbit(
            details.localPosition.dx - last.dx,
            details.localPosition.dy - last.dy,
          );
        });
        _lastPan = details.localPosition;
      },
      onPanEnd: (_) => _lastPan = null,
      onDoubleTap: () => setState(() => _rig.zoom(0.8)),
      child: SceneView(_scene!, camera: camera),
    );
  }
}
