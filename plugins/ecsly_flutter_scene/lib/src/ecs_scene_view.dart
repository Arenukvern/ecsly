// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

/// The embedding widget: an ecsly World rendered as a flutter_scene 3D
/// view, with orbit gestures and per-frame binder sync. Requires
/// Flutter 3.47+ with Flutter GPU enabled on the platform, and
/// `Scene.initializeStaticResources()` before first geometry — handled
/// in state init (the static future is cached by flutter_scene itself).
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import 'ecs_scene_binder.dart';
import 'flutter_scene_sink.dart';
import 'scene_camera_math.dart';
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
    this.onDistanceChange,
    this.onEntityTap,
    this.onEntityHold,
    this.onCameraChanged,
    this.loadingColor,
  });

  /// Initial camera distance from the orbit target.
  final World world;
  /// Creates the view state.
  final SceneMapping mapping;
  /// The widget state.
  final double initialDistance;

  /// Called after every camera-distance change (scroll dolly, double-tap)
  /// with the NEW distance — the semantic-zoom hook: hosts derive LOD
  /// tiers from it and re-filter their mapping in place.
  final void Function(double distance)? onDistanceChange;

  /// VOSGES tap (the pick grammar): a tap landing on a visual with a
  /// [VisualState.pickId] reports that id. A tap on empty space reports
  /// nothing (orbit still owns drags; taps never fire after a pan).
  final void Function(String pickId)? onEntityTap;

  /// VOSGES hold (the intent grammar): a long-press landing on a named
  /// visual — the consumer summons the verb grammar for that target.
  final void Function(String pickId)? onEntityHold;

  /// Camera eye/target after every camera move AND on init — consumers
  /// project 2D overlays (nameplates) with the same basis the scene
  /// renders with (scene_camera_math.dart).
  final void Function(List<double> eye, List<double> target)?
  onCameraChanged;

  /// The while-loading/error backdrop (GPU static resources init
  /// asynchronously). Null = the standalone's black; a light-paper host
  /// passes its paper so the loading state reads as the same material.
  final Color? loadingColor;

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
      _reportCamera();
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
  Widget build(BuildContext context) {
    final backdrop = widget.loadingColor ?? Colors.black;
    if (_error != null) {
      return ColoredBox(
        color: backdrop,
        child: Center(
          child: Text(
            'scene unavailable: $_error',
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ),
      );
    }
    if (!_ready || _scene == null) {
      return ColoredBox(
        color: backdrop,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final camera = PerspectiveCamera(
      position: _rig.cameraPosition(),
      target: _rig.cameraTarget(),
    );
    return GestureDetector(
      onPanStart: (details) => _lastPan = details.localPosition,
      onPanUpdate: (details) {
        final last = _lastPan ?? details.localPosition;
        setState(() {
          _rig.orbit(
            details.localPosition.dx - last.dx,
            details.localPosition.dy - last.dy,
          );
        });
        _lastPan = details.localPosition;
        _reportCamera();
      },
      onPanEnd: (_) => _lastPan = null,
      onDoubleTap: () => _zoomBy(0.8),
      onTapUp: (details) => _pickAt(details.localPosition, widget.onEntityTap),
      onLongPressStart:
          (details) => _pickAt(details.localPosition, widget.onEntityHold),
      child: Listener(
        // Scroll dolly (desktop/trackpad): wheel down zooms out, up zooms
        // in. The altitude hook rides every distance change.
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _zoomBy(event.scrollDelta.dy > 0 ? 1.1 : 0.9);
          }
        },
        child: SceneView(_scene!, camera: camera),
      ),
    );
  }

  /// Reports the current camera to the consumer (overlay projection).
  void _reportCamera() {
    final cb = widget.onCameraChanged;
    if (cb == null) return;
    final eye = _rig.cameraPosition();
    cb([eye.x, eye.y, eye.z], [_rig.target[0], _rig.target[1], _rig.target[2]]);
  }

  /// The pick read: pointer → ray through THIS viewport's basis → nearest
  /// named sphere. No binder yet (first frames), no hit, or no callback —
  /// all silently do nothing; a gesture on empty space is not a verb.
  void _pickAt(Offset local, void Function(String pickId)? callback) {
    if (callback == null || _binder == null) return;
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size;
    if (size == null || size.width <= 0 || size.height <= 0) return;
    final basis = SceneCameraBasis(
      eye: _rig.cameraPosition().storage.toList(),
      target: _rig.target,
      aspect: size.width / size.height,
    );
    final (ndcX, ndcY) = basis.ndcOfPointer(
      local.dx,
      local.dy,
      size.width,
      size.height,
    );
    final hit = pickVisuals(
      visuals: _binder!.current,
      ray: basis.rayThrough(ndcX, ndcY),
    );
    if (hit != null) callback(hit.pickId);
  }

  void _zoomBy(double factor) {
    setState(() => _rig.zoom(factor));
    widget.onDistanceChange?.call(_rig.distance);
    _reportCamera();
  }
}
