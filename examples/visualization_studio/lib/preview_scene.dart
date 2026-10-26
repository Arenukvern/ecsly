import 'preview_mapping.dart';
import 'measured_scene.dart';

import 'dart:async';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'preview_model.dart';
import 'retained_scene_sink.dart';
import 'startup_trace.dart';

/// ECS host drives time; this reusable widget projects it and owns GPU objects.
class PreviewScene extends StatefulWidget {
  const PreviewScene({
    required this.world,
    required this.controller,
    super.key,
  });
  final World world;
  final EcsController controller;
  @override
  State<PreviewScene> createState() => _PreviewSceneState();
}

class _PreviewSceneState extends State<PreviewScene> {
  Scene? _scene;
  EcsSceneBinder? _binder;
  RetainedSceneSink? _sink;
  String? _error;
  late final SceneMapping _mapping = previewMapping();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final trace = widget.world.getResource<StartupTrace>();
    try {
      trace.mark('staticResourcesEntered');
      await Scene.initializeStaticResources();
      trace.mark('staticResourcesReturned');
      if (!mounted) return;
      final scene = MeasuredScene(trace);
      _sink = RetainedSceneSink(scene);
      _binder = EcsSceneBinder(
        world: widget.world,
        mapping: _mapping,
        sink: _sink!,
      );
      _binder!.sync();
      trace.mark('initialVisualsBound');
      setState(() => _scene = scene);
      debugPrint('PREVIEW scene ready; ${_binder!.current.length} visuals');
    } catch (error, stack) {
      trace.fail(error);
      debugPrint('PREVIEW scene initialization failed: $error\n$stack');
      if (mounted) setState(() => _error = '$error');
    }
  }

  void _sync() {
    _binder?.sync();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _scene?.dispose();
    super.dispose();
  }

  PreviewSnapshot get snapshot =>
      widget.world.getResource<PreviewResource>().value;
  void _change(PreviewSnapshot Function(PreviewSnapshot) change) {
    widget.controller.runTransaction((world) {
      world.getResource<PreviewResource>().value = change(snapshot);
    }, invalidation: EcsInvalidationBatch.resource<PreviewResource>());
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Semantics(
          liveRegion: true,
          child: Text('Scene unavailable: $_error'),
        ),
      );
    }
    if (_scene == null) return const Center(child: CircularProgressIndicator());
    final s = snapshot;
    final rig = SceneCameraRig(
      distance: s.distance,
      yaw: s.yaw,
      pitch: s.pitch,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth, height = constraints.maxHeight;
        final camera = PerspectiveCamera(
          position: rig.cameraPosition(),
          target: rig.cameraTarget(),
        );
        final viewSize = Size(width, height);
        _sink!.updateForCamera(camera, viewSize);
        final labels = <Widget>[];
        for (final visual in _binder!.current.values) {
          if (visual.label == null || visual.pickId == null) continue;
          final index = int.parse(visual.pickId!);
          if (width < 500 && index != s.selected) continue;
          if (s.example == Example.linked && index != s.selected) continue;
          final screen = camera.worldToScreen(
            vm.Vector3.array(visual.position),
            viewSize,
          );
          if (screen == null) continue;
          final x = screen.dx, y = screen.dy;
          final labelWidth = s.example == Example.simulation ? 112.0 : 64.0;
          if (x < 0 || x > width || y < 0 || y > height) continue;
          labels.add(
            Positioned(
              left: (x - labelWidth / 2).clamp(
                0,
                (width - labelWidth).clamp(0, width),
              ),
              top: (y + 14).clamp(0, height - 30),
              width: labelWidth,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Text(
                    visual.label!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
            ),
          );
        }
        return Semantics(
          label: 'Interactive spatial view. Select items using labeled controls below.',
          child: GestureDetector(
            onPanUpdate: (d) => _change(
              (old) => old.copyWith(
                yaw: old.yaw + d.delta.dx * 0.008,
                pitch: (old.pitch + d.delta.dy * 0.008).clamp(-1.3, 1.3),
              ),
            ),
            onTapUp: (d) {
              final hit = pickVisuals(
                visuals: _binder!.current,
                ray: camera.screenPointToRay(d.localPosition, viewSize),
              );
              if (hit != null) {
                _change((old) => old.copyWith(selected: int.parse(hit.pickId)));
              }
            },
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _change(
                    (old) => old.copyWith(
                      distance:
                          (old.distance *
                                  (event.scrollDelta.dy > 0 ? 1.08 : 0.92))
                              .clamp(6, 24),
                    ),
                  );
                }
              },
              child: Stack(
                children: [
                  Positioned.fill(child: SceneView(_scene!, camera: camera)),
                  ...labels,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
