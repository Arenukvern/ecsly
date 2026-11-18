// Parameters carry no `final`: this package compiles under language 3.13
// (where that modifier is an error) as well as 3.12.
// ignore_for_file: prefer_final_parameters

/// The capture seam: one frame of a flutter_scene scene as PNG bytes,
/// through a caller-owned offscreen render target.
///
/// How it works, entirely on public flutter_scene API: while armed, an
/// extra [RenderView] joins `Scene.views` targeting a private
/// [RenderTexture] whose update policy is [RenderTextureUpdate.manual] —
/// nothing renders while unarmed, and a capture asks for exactly one
/// frame. The frame is published through the target's `texture` getter
/// and converted with flutter_gpu's public `Texture.asImage` (zero-copy
/// on Impeller) straight into PNG bytes. The live screen view is never
/// touched: the host keeps its own [SceneView], the capture adds no
/// per-frame cost, and a failed capture degrades to null (a shutter must
/// never throw in a player's hands) rather than surfacing renderer
/// errors.
///
/// The camera is SHARED with the host's view, and flutter_scene derives
/// the projection's aspect from the target at draw time — so a capture
/// sized to a letterboxed region reproduces exactly the on-screen
/// content of that region (WYSIWYG framing at any aspect).
///
/// Attach one controller to one live view (via [EcsSceneView]);
/// re-attaching moves it. Headless and stub backends return null.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_scene/scene.dart';

/// One-frame PNG capture of a flutter_scene scene. See the library doc
/// for the mechanism and the WYSIWYG contract.
class SceneFrameCapture {
  /// Creates an unarmed, unattached controller.
  SceneFrameCapture();

  Scene? _scene;
  Camera? _camera;
  RenderTexture? _target;
  RenderView? _view;
  Completer<void>? _pending;
  bool _armed = false;

  /// Whether a live scene+camera are attached.
  bool get isAttached => _scene != null && _camera != null;

  /// Whether the offscreen capture view is installed in the scene.
  bool get armed => _armed;

  /// Attaches the controller to [scene] rendered through [camera] (the
  /// host's ONE camera — the capture mirrors the host's view).
  /// Re-attaching moves the controller to the new scene.
  void attach({required Scene scene, required Camera camera}) {
    if (identical(_scene, scene) && identical(_camera, camera)) return;
    _uninstall();
    _scene = scene;
    _camera = camera;
    if (_armed) _install();
  }

  /// Removes the controller from its scene (the view unmounts).
  /// Arms state is kept, so a re-attach reinstalls automatically.
  void detach() {
    _uninstall();
    _scene = null;
    _camera = null;
  }

  /// Installs / removes the offscreen capture view. Arming without an
  /// attached scene takes effect on the next [attach].
  set armed(bool value) {
    if (_armed == value) return;
    _armed = value;
    if (value) {
      _install();
    } else {
      _uninstall();
    }
  }

  /// Captures one fresh frame of [width]×[height] physical pixels —
  /// the caller picks the aspect (a letterboxed region's pixel size at
  /// the device pixel ratio reproduces that region exactly). Returns the
  /// PNG bytes, or null when unarmed, unattached, unrenderable, or when
  /// no frame arrives within [timeout] (a paused/idle scene produces no
  /// frames). Never throws.
  Future<Uint8List?> capture({
    required int width,
    required int height,
    Duration timeout = const Duration(milliseconds: 1000),
  }) async {
    final target = _target;
    if (!_armed || target == null || !isAttached) return null;
    if (width <= 0 || height <= 0) return null;
    // Resize first (a size change also forces the next update regardless
    // of policy), then ask for exactly one frame and wait for its
    // publication. Manual policy keeps the ring static afterwards, so
    // the texture below cannot be recycled mid-read.
    target.resize(width, height);
    final waiter = Completer<void>();
    _pending = waiter;
    target.requestUpdate();
    try {
      await waiter.future.timeout(timeout);
    } on TimeoutException {
      return null;
    }
    final texture = target.texture;
    if (texture == null) return null;
    final ui.Image image;
    try {
      image = texture.asImage();
    } on Object {
      // Stub/web backends without the host bridge: a capture degrades.
      return null;
    }
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } on Object {
      return null;
    } finally {
      image.dispose();
    }
  }

  /// Releases the target and detaches. The controller is unusable after.
  void dispose() {
    armed = false;
    _target
      ?..removeListener(_onFramePublished)
      ..dispose();
    _target = null;
    detach();
  }

  void _install() {
    final scene = _scene;
    final camera = _camera;
    if (scene == null || camera == null || _view != null) return;
    final target =
        _target ??= RenderTexture(
            width: 2,
            height: 2,
            update: RenderTextureUpdate.manual,
          )
          ..addListener(_onFramePublished);
    final view = RenderView(camera: camera, target: target);
    _view = view;
    scene.views.add(view);
  }

  void _uninstall() {
    final view = _view;
    final scene = _scene;
    if (view != null) {
      scene?.views.remove(view);
      _view = null;
    }
    _pending = null;
  }

  void _onFramePublished() {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete();
  }
}
