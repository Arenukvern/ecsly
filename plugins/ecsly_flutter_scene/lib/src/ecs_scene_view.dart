// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

/// The embedding widget: an ecsly World rendered as a flutter_scene 3D
/// view, with the standard map-camera gestures (drag pans, right/shift
/// drags orbit, two fingers pinch+twist, the wheel zooms at the cursor)
/// and per-frame binder sync. Requires
/// Flutter 3.47+ with Flutter GPU enabled on the platform, and
/// `Scene.initializeStaticResources()` before first geometry — handled
/// in state init (the static future is cached by flutter_scene itself).
library;

import 'dart:async';

import 'package:ecsly/ecsly.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'ecs_scene_binder.dart';
import 'flutter_scene_sink.dart';
import 'scene_camera_math.dart';
import 'scene_mapping.dart';

/// Imperative camera request evaluated on the sync tick: mirror the orbit
/// rig to [target] (world XYZ) with optional distance/pitch/yaw overrides.
/// Returning null each tick means "leave the camera to the player's
/// gestures". Hosts that keep camera state in ECS (e.g. an
/// OrbitCameraResource driven by input systems) return its full pose here
/// every tick — the rig becomes a pure mirror of the renderer-agnostic
/// state, and this widget is only the bridge.
class SceneCameraFocus {
  /// Creates a focus request.
  const SceneCameraFocus({
    required this.target,
    this.distance,
    this.pitch,
    this.yaw,
  });

  /// World-space orbit target (XYZ).
  final List<double> target;

  /// Orbit distance override (meters).
  final double? distance;

  /// Pitch override (radians).
  final double? pitch;

  /// Yaw override (radians). Null leaves the rig's yaw untouched (close-up
  /// framings historically preserve the player's heading).
  final double? yaw;
}

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
    this.onManipulationStart,
    this.onManipulationUpdate,
    this.onManipulationEnd,
    this.loadingColor,
    this.environmentRevision,
    this.onEnvironmentBuild,
    this.onEnvironmentTick,
    this.cameraFocusTick,
    this.onTapRay,
    this.onHoverRay,
    this.onDragRay,
    this.claimDragForPaint = false,
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
  final void Function(List<double> eye, List<double> target)? onCameraChanged;

  /// Consumer claims a picked drag. Returning true prevents camera orbit for
  /// this gesture; project semantics and permission stay with the consumer.
  final bool Function(String pickId)? onManipulationStart;
  final void Function(String pickId, double dx, double dy)?
  onManipulationUpdate;
  final void Function(String pickId, bool cancelled)? onManipulationEnd;

  /// The while-loading/error backdrop (GPU static resources init
  /// asynchronously). Null = the standalone's black; a light-paper host
  /// passes its paper so the loading state reads as the same material.
  final Color? loadingColor;

  /// Cheap revision token for consumer-owned environment content (city
  /// terrain, roads, buildings — geometry too rich for the closed
  /// [VisualState] actor vocabulary, which it bypasses by design). When
  /// the token changes between sync ticks, [onEnvironmentBuild] runs.
  /// Both null = no environment tier (pure actor view, the default).
  final int Function(World world)? environmentRevision;

  /// Builds (or rebuilds) the consumer's environment subtree. The
  /// consumer owns its root node's lifecycle: remove the previous root,
  /// add the next. Called once after scene creation, then on every
  /// [environmentRevision] change. Runs on the sync tick, never inside
  /// the world's own schedule.
  final void Function(Scene scene, World world)? onEnvironmentBuild;

  /// Cheap per-tick environment update (sun position, fog, palette
  /// uniforms) — runs every sync tick WITHOUT a geometry rebuild, so
  /// time-of-day advances smoothly while meshes stay cached.
  final void Function(Scene scene, World world)? onEnvironmentTick;

  /// Close-up camera request per sync tick (null = player keeps control).
  final SceneCameraFocus? Function(World world)? cameraFocusTick;

  /// Every tap also reports its world ray (render-camera basis), whether
  /// or not a named visual was hit — consumers ray-march their own
  /// geometry (terrain brushes, plot placement). Entity pick still fires
  /// independently via [onEntityTap].
  final void Function(vm.Ray ray)? onTapRay;

  /// Pointer hover (mouse moves with no button) reports its world ray —
  /// consumers draw a placement ghost / brush footprint under the cursor.
  /// Null before the first layout; never fires during a drag.
  final void Function(vm.Ray ray)? onHoverRay;

  /// While [claimDragForPaint] is true, a plain drag reports its ray each
  /// move instead of panning — continuous brush painting. Middle-drag and
  /// shift-drag still orbit regardless. Null = drags always pan/orbit.
  final void Function(vm.Ray ray)? onDragRay;

  /// When true (and [onDragRay] set), plain drags paint rather than pan.
  /// The consumer toggles this with its edit mode + active brush tool.
  final bool claimDragForPaint;

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
  Offset? _lastFocal;
  double _lastScale = 1;
  double _lastRotation = 0;
  bool _middleDrag = false;
  String? _manipulationId;
  int? _envRevision;
  bool _painting = false;
  // Last pose handed to onCameraChanged/onDistanceChange — the sync tick's
  // change detector compares against it so ECS-driven camera moves report
  // exactly once (and gesture-driven moves don't report twice).
  List<double>? _lastReportedEye;
  List<double>? _lastReportedTarget;
  double? _lastReportedDistance;

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
      // Environment tier first (the ground the actors stand on), then
      // the actor binder's initial sync rides the same timer below.
      _envRevision = widget.environmentRevision?.call(widget.world);
      widget.onEnvironmentBuild?.call(scene, widget.world);
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
        (_) => _syncTick(),
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

  /// One 30 Hz read pass: actor binder sync, then the environment
  /// revision gate (rebuild only when the consumer's token changed).
  void _syncTick() {
    _binder?.sync();
    final scene = _scene;
    if (scene == null) return;
    final revisionOf = widget.environmentRevision;
    final build = widget.onEnvironmentBuild;
    if (revisionOf != null && build != null) {
      final revision = revisionOf(widget.world);
      if (revision != _envRevision) {
        _envRevision = revision;
        build(scene, widget.world);
      }
    }
    widget.onEnvironmentTick?.call(scene, widget.world);
    final focus = widget.cameraFocusTick?.call(widget.world);
    if (focus != null) {
      _rig.focus(focus.target);
      if (focus.distance != null) _rig.distance = focus.distance!;
      if (focus.pitch != null) _rig.pitch = focus.pitch!;
      if (focus.yaw != null) _rig.yaw = focus.yaw!;
    }
    // Camera consumers (LOD hook, pose rendezvous) must see moves made
    // OUTSIDE the gesture handlers too — an ECS orbit state mirrored via
    // cameraFocusTick never touches the gesture path. Change-detected so
    // idle ticks cost one comparison.
    _reportCameraIfChanged();
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
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final camera = PerspectiveCamera(
      position: _rig.cameraPosition(),
      target: _rig.cameraTarget(),
    );
    return GestureDetector(
      // One recognizer for mouse + touch (the city-builder camera map):
      //   single-finger/left drag ......... PAN (tool drag paints when
      //                                     claimDragForPaint is on)
      //   middle-drag / shift-drag ........ ORBIT
      //   two-finger drag ................. PAN + PINCH zoom + TWIST yaw
      //   wheel / double-tap .............. zoom AT the cursor
      //   trackpad two-finger / pinch ..... PAN / zoom (pan-zoom events)
      onScaleStart: (details) {
        _lastFocal = details.localFocalPoint;
        _lastScale = 1;
        _lastRotation = 0;
        _manipulationId = null;
        _painting = false;
        if (details.pointerCount > 1) return;
        final orbitDrag =
            _middleDrag || HardwareKeyboard.instance.isShiftPressed;
        if (!orbitDrag &&
            widget.claimDragForPaint &&
            widget.onDragRay != null) {
          final ray = _rayAt(details.localFocalPoint);
          if (ray != null) {
            _painting = true;
            widget.onDragRay!(ray);
            return;
          }
        }
        if (!orbitDrag) {
          _pickAt(details.localFocalPoint, (id) {
            if (widget.onManipulationStart?.call(id) ?? false) {
              _manipulationId = id;
            }
          });
        }
      },
      onScaleUpdate: (details) {
        final last = _lastFocal ?? details.localFocalPoint;
        final dx = details.localFocalPoint.dx - last.dx;
        final dy = details.localFocalPoint.dy - last.dy;
        if (details.pointerCount > 1) {
          // Touch transform: focal pan + pinch dolly + twist orbit.
          final pinch = details.scale / (_lastScale == 0 ? 1 : _lastScale);
          final twist = details.rotation - _lastRotation;
          setState(() {
            _rig.pan(dx, dy);
            if (pinch != 1) _rig.zoom(1 / pinch);
            _rig.yaw += twist;
          });
          _lastScale = details.scale;
          _lastRotation = details.rotation;
          _lastFocal = details.localFocalPoint;
          widget.onDistanceChange?.call(_rig.distance);
          _reportCamera();
          return;
        }
        if (_painting) {
          final ray = _rayAt(details.localFocalPoint);
          if (ray != null) widget.onDragRay!(ray);
          _lastFocal = details.localFocalPoint;
          return;
        }
        final id = _manipulationId;
        if (id != null) {
          widget.onManipulationUpdate?.call(id, dx, dy);
          _lastFocal = details.localFocalPoint;
          return;
        }
        // Single "pointer" but scale changing = trackpad pinch (macOS
        // pan-zoom gestures ride the scale recognizer): dolly.
        final trackpadPinch = _lastScale == 0 ? 1 : details.scale / _lastScale;
        _lastScale = details.scale;
        setState(() {
          if (trackpadPinch != 1) _rig.zoom(1 / trackpadPinch);
          // Middle-drag (or shift-drag for trackpads) orbits; every other
          // plain drag pans — the industry default for map cameras.
          if (_middleDrag || HardwareKeyboard.instance.isShiftPressed) {
            _rig.orbit(dx, dy);
          } else {
            _rig.pan(dx, dy);
          }
        });
        _lastFocal = details.localFocalPoint;
        widget.onDistanceChange?.call(_rig.distance);
        _reportCamera();
      },
      onScaleEnd: (_) => _endManipulation(false),
      onDoubleTapDown: (details) => _zoomAt(0.8, details.localPosition),
      onTapUp: (details) {
        _pickAt(details.localPosition, widget.onEntityTap);
        final rayCb = widget.onTapRay;
        if (rayCb != null) {
          final ray = _rayAt(details.localPosition);
          if (ray != null) rayCb(ray);
        }
      },
      onLongPressStart: (details) =>
          _pickAt(details.localPosition, widget.onEntityHold),
      child: Listener(
        // Which mouse button owns the current drag (middle = orbit).
        onPointerDown: (event) {
          _middleDrag = (event.buttons & kTertiaryButton) != 0;
        },
        onPointerUp: (_) => _middleDrag = false,
        onPointerCancel: (_) => _middleDrag = false,
        // Wheel dolly AT the cursor (desktop): the ground point under the
        // pointer stays under it while the distance scales. Trackpad
        // two-finger pan/pinch rides the scale recognizer above (macOS
        // delivers it as pan-zoom gestures, not scroll signals).
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _zoomAt(event.scrollDelta.dy > 0 ? 1.1 : 0.9, event.localPosition);
          }
        },
        // Hover ray (mouse, no button): the placement ghost follows the
        // cursor so tools land directly under the pointer.
        onPointerHover: (event) {
          final cb = widget.onHoverRay;
          if (cb == null) return;
          final ray = _rayAt(event.localPosition);
          if (ray != null) cb(ray);
        },
        child: SceneView(_scene!, camera: camera),
      ),
    );
  }

  void _endManipulation(bool cancelled) {
    final id = _manipulationId;
    _manipulationId = null;
    _painting = false;
    _lastFocal = null;
    if (id != null) widget.onManipulationEnd?.call(id, cancelled);
  }

  /// Reports the current camera to the consumer (overlay projection) and
  /// records the pose snapshot the sync-tick change detector reads.
  void _reportCamera() {
    final eye = _rig.cameraPosition();
    _lastReportedEye = [eye.x, eye.y, eye.z];
    _lastReportedTarget = [_rig.target[0], _rig.target[1], _rig.target[2]];
    _lastReportedDistance = _rig.distance;
    final cb = widget.onCameraChanged;
    if (cb == null) return;
    cb(_lastReportedEye!, _lastReportedTarget!);
  }

  /// Change-detected report for camera moves that bypass the gesture
  /// handlers (ECS orbit state mirrored through [SceneCameraFocus], agent
  /// close-ups): fires [EcsSceneView.onCameraChanged] and — when the
  /// distance moved — [EcsSceneView.onDistanceChange].
  void _reportCameraIfChanged() {
    final eye = _rig.cameraPosition();
    final lastEye = _lastReportedEye;
    final lastTarget = _lastReportedTarget;
    final lastDistance = _lastReportedDistance;
    if (lastEye != null &&
        lastTarget != null &&
        lastDistance == _rig.distance &&
        lastEye[0] == eye.x &&
        lastEye[1] == eye.y &&
        lastEye[2] == eye.z &&
        lastTarget[0] == _rig.target[0] &&
        lastTarget[1] == _rig.target[1] &&
        lastTarget[2] == _rig.target[2]) {
      return;
    }
    final distanceChanged = lastDistance != _rig.distance;
    _reportCamera();
    if (distanceChanged) widget.onDistanceChange?.call(_rig.distance);
  }

  /// The pick read: pointer → ray through THIS viewport's basis → nearest
  /// named sphere. No binder yet (first frames), no hit, or no callback —
  /// all silently do nothing; a gesture on empty space is not a verb.
  void _pickAt(Offset local, void Function(String pickId)? callback) {
    if (callback == null || _binder == null) return;
    final ray = _rayAt(local);
    if (ray == null) return;
    final hit = pickVisuals(visuals: _binder!.current, ray: ray);
    if (hit != null) callback(hit.pickId);
  }

  /// Pointer → world ray through the render camera's basis. Consumers
  /// ray-march their own geometry against it (terrain editing); null
  /// before the first layout.
  vm.Ray? _rayAt(Offset local) {
    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size;
    if (size == null || size.width <= 0 || size.height <= 0) return null;
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
    return basis.rayThrough(ndcX, ndcY);
  }

  /// Dolly by [factor], keeping the ground point under [local] fixed
  /// (zoom-at-cursor, the desktop city-builder standard). Falls back to a
  /// centered zoom when the cursor ray misses the target's horizontal
  /// plane (looking up, or before the first layout).
  void _zoomAt(double factor, Offset? local) {
    vm.Vector3? hit;
    final ray = local == null ? null : _rayAt(local);
    final dirY = ray?.direction.y ?? 0;
    if (ray != null && dirY.abs() > 1e-6) {
      final t = (_rig.target[1] - ray.origin.y) / dirY;
      if (t > 0) hit = ray.origin + ray.direction * t;
    }
    setState(() {
      _rig.zoom(factor);
      final pinned = hit;
      if (pinned != null) {
        final keep = 1 - factor;
        _rig.target = [
          _rig.target[0] + (pinned.x - _rig.target[0]) * keep,
          _rig.target[1],
          _rig.target[2] + (pinned.z - _rig.target[2]) * keep,
        ];
      }
    });
    widget.onDistanceChange?.call(_rig.distance);
    _reportCamera();
  }
}
