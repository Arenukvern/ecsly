# The preview harness (turntable + four views)

The design loop needs eyes. This temporary Flutter consumer renders the model under
design on a turntable with a ground reference. Choose an owned output directory and
record its cleanup lifetime; maintained reusable consumers belong in ecsly/examples. You
edit the model builder, hot-reload, capture, critique. A model you haven't seen render is
a guess.

For full explainers, state restoration, linked plots and repeatable verification,
use the verified [ecsly-visualization shell](/Users/antonio/.codex/skills/ecsly-visualization/SKILL.md)
and its Flutter MCP harness/CDP composition roots. This turntable remains a small
model-only recipe; the code below is illustrative, not the executed three-example trial.

## Setup (once per owned temporary consumer)

```sh
MODEL_PREVIEW_DIR=/absolute/path/to/your-project/output/model_preview
flutter create "$MODEL_PREVIEW_DIR" --platforms macos
cd "$MODEL_PREVIEW_DIR"
flutter pub add flutter_scene vector_math
dart run flutter_scene:init     # required asset/shader build-hook setup
dart run flutter_scene:skills   # engine skills install here too
```

Import your model builder from the project under design (path dependency, or paste the
builder into `lib/model.dart` while iterating — fast, and the diff back into the real
project is mechanical).

## main.dart — turntable, ground, camera views

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'model.dart'; // Node buildDeskLamp(LampParams p)

/// One of: front, side, threeQuarter, top. Hot-reload to switch views.
const view = 'threeQuarter';
const turn = true; // hot-reload false to hold a pose for capture

void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();
  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  final Scene _scene = Scene();
  Node? _model;
  Node? _stage;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Scene.initializeStaticResources().then((_) {
      final model = buildDeskLamp(const LampParams()); // ← the model under design
      _model = model;
      _scene.add(model);
      _stage = _ground();
      _scene.add(_stage!);
      // Frame the model: eye distance ≈ 2.5× its height, slightly above center.
      if (mounted) setState(() => _ready = true);
    });
  }

  Node _ground() => Node(
        mesh: Mesh(
          DiscGeometry(radius: 3),
          PhysicallyBasedMaterial()
            ..baseColorFactor = vm.Vector4(0.85, 0.85, 0.88, 1)
            ..roughnessFactor = 0.9,
        ),
      );

  vm.Vector3 _eye() {
    switch (view) {
      case 'front':
        return vm.Vector3(0, 1.2, -4);
      case 'side':
        return vm.Vector3(4, 1.2, 0);
      case 'top':
        return vm.Vector3(0.01, 5.5, 0.01);
      default: // threeQuarter
        return vm.Vector3(2.8, 2.0, -2.8);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SceneView(_scene, camera: PerspectiveCamera(position: _eye()),
          onTick: (elapsed, deltaSeconds) {
            if (!turn) return;
            _model?.rotation = vm.Quaternion.axisAngle(
              vm.Vector3(0, 1, 0), elapsed.inMicroseconds / 1000000 * 0.4);
          }),
      ),
    );
  }
}
```

Notes: the ground disc doubles as the scale/grounding reference (a model that floats or
pierces the disc fails the grounding check immediately). The scene's default studio
environment lights the model — add the official `flutter_scene-looks` preset once you
reach the material pass, not during blockout.

## The capture rhythm

1. `flutter run -d macos --enable-flutter-gpu` (the flag is mandatory).
2. **Settle** — let auto-exposure and first frames stabilize; don't judge frame one.
3. Set `view` to `front` → hot reload (`r`) → capture. Repeat: `side`, `threeQuarter`,
   `top`. Then set `turn: false` and hold the three-quarter pose while refining.
4. Capture the **console too** — import warnings, shader errors, and NaN spam print there
   while pixels lie. (With the editor MCP connected, use its screenshot + console tools;
   otherwise macOS `screencapture -l <windowid>` or the window's share button.)
5. Save views under `views/<model>/<iter>_<view>.png` so a critique can cite
   `iter3_side` exactly, and regressions are visible side by side.

## Critique ritual (per design-craft.md's checklist)

Write, per iteration, three lines: what view failed which check, the ONE change to make,
and the expected effect ("iter3_side: arm merges with head → raise head pivot 0.15 →
expect a gap in side silhouette"). Then make that one change and re-capture **only** the
view that failed, plus three-quarter as the control. Full four-view sweeps at blockout
gate and final pass; targeted single views between.

## Previewing ecsly world visuals

Don't build a fake world in the harness — the adapter ships one:
`~/xs/ecsly/plugins/ecsly_flutter_scene/example/main.dart` (ten ring markers,
orbit camera). Run it from the plugin directory the same way
(`flutter run -d macos --enable-flutter-gpu`) when iterating on mapping/sink behavior,
and keep temporary model work in the owned consumer output. Native `flutter run`
is an interactive launch that can activate a window. Use it when intentionally
reviewing the model; background automated observation requires separately qualified
nonactivating lifecycle and capture policy.
