---
name: flutter-scene-modeling
description: Design and build great 3D models as code for flutter_scene (Flutter GPU 3D engine, 0.23+) and the ecsly_flutter_scene ECS adapter. Use whenever creating or improving 3D models, meshes, procedural geometry, entity shapes, GLB assets, custom SceneSink visuals, model preview/iteration loops, or inspector/world visuals — even if the user just says "make a 3D model of X", "add a shape for this component", or "make this model look better".
---

# 3D modeling for flutter_scene and ecsly_flutter_scene

This is "3D models as code" in the kiln tradition: the model is a **parameterized Dart
builder function**, you **render it, critique the render, and refine** in a closed loop —
never guessing at pixels. The craft that separates a great model from a pile of primitives
is *design* (silhouette, proportion, palette, coherence), not engine cleverness. This skill
carries that design craft plus the routing and integration knowledge; the engine's own
skills carry the API correctness.

For a complete interactive explainer, graph, simulation, or linked chart/scene,
compose with [ecsly-visualization](/Users/antonio/.codex/skills/ecsly-visualization/SKILL.md).
That skill owns the Flutter shell, ECS actions/selectors, state, overlays and
deterministic toolkit/CDP verification. Keep this skill focused on model craft.

## Step 0 — install the official engine skills (once)

flutter_scene ships six agent skills. From any package that depends on flutter_scene:

```sh
dart run flutter_scene:skills        # installs/updates them
dart run flutter_scene:skills --check
```

Read `flutter_scene-idioms` **before writing any engine code** — it corrects the
three.js/Unity/Godot reflexes that cause most first-attempt failures. The others you will
reach for on demand:

| Official skill | What it covers |
| --- | --- |
| `flutter_scene-idioms` | Correct APIs and engine traps |
| `flutter_scene-verification-loop` | Run → settle → capture mechanics |
| `flutter_scene-looks` | Lighting + post presets (`EnvironmentSettings`) |
| `flutter_scene-procedural` | `GeometryBuilder`, `InstancedMesh`, noise |
| `flutter_scene-kit` | Gameplay/camera/atmosphere components |
| `flutter_scene-performance` | Frame budget and measurement |

This skill does **not** repeat them. It adds: (1) the design methodology, (2) which of
three build routes to take, (3) the ecsly_flutter_scene adapter integration.

## Step 1 — pick the route (before writing code)

| The model is for... | Route | Read first |
| --- | --- | --- |
| A visual for an ecsly entity/component (inspector, debug view, world visualization) | `VisualState` primitives, or a custom `SceneSink` in your app when a primitive isn't enough | [references/ecsly-adapter.md](references/ecsly-adapter.md) |
| A standalone model (game asset, hero prop, set dressing), no external source | Procedural Dart geometry | [references/procedural-geometry.md](references/procedural-geometry.md) |
| A model that comes from outside (Blender export, downloaded/converted .glb) | glTF import pipeline | [references/gltf-pipeline.md](references/gltf-pipeline.md) |

Default to **procedural Dart** for agent-authored models: no import step, no
coordinate-conversion traps, parameterizable (a variant is a changed argument, not a new
file), reviewable as code, and the geometry assembles without a GPU.

Do **not** default to glTF "because it's more professional" — an agent-written binary glTF
by hand is strictly worse than Dart geometry, and the import step adds failure modes.

## Step 2 — design before you build

Write the design down as three short lists before any geometry code:

1. **Intent sentence** — what the model is for, seen from where, at what screen size.
   ("A desk lamp prop, seen three-quarter from 2 m, occupying ~1/8 of the frame on mobile.")
2. **Part decomposition** — named parts, each buildable from one or two primitives
   (base, arm, shade, cord). 3–7 parts for a prop; hierarchy over hero-mesh.
3. **Proportion ratios** — height : footprint, part-to-part lengths. Deliberate, written
   numbers, not "looks about right".

The full methodology — decomposition tables, proportion sheets, palette discipline,
material recipes, style locking, and the critique checklist — is
[references/design-craft.md](references/design-craft.md). Read it for any model that is
meant to *look good*, not just exist. The single most important rule it teaches: **models
fail on silhouette and proportion long before they fail on detail.** Block out the whole
model in one flat color, check the silhouette in four views, and only then add detail.

That reference covers the *model*. For the *experience* around it — a named style
anchor, storytelling, idle life, the signature moment, and the score-and-fix ship
gate (0/1/2 rubric, ≥ 3 critique passes) — load the `stylized-3d-craft` skill and
score its rubric against your captures. The two sheets compose: its style sheet
(anchor/palette/light/signature) sits next to this skill's design sheet
(intent/parts/ratios).

## Step 3 — the build loop (every route)

```
design (step 2) → blockout → capture → critique → ONE change → capture → ... → detail → materials → final capture
```

1. **Build the blockout**: whole model, one flat `PhysicallyBasedMaterial` color,
   builder function + params object, no side effects at import time.
2. **Preview it**: [references/preview-harness.md](references/preview-harness.md) has a
   drop-in turntable app. Run with `flutter run -d macos --enable-flutter-gpu`.
3. **Capture per the official verification loop**: let the scene settle (auto-exposure
   ramps over the first frames), then screenshot AND read the console — either alone lies.
   Take four views per iteration: front, side, three-quarter, top.
4. **Critique against the checklist** in design-craft.md (silhouette readable? parts
   overlap instead of float? palette ≤ 4 hues? one clear idea?). Localize the problem to a
   part before editing.
5. **One change per iteration.** Cause and effect stay legible; twelve tweaks per pass is
   how you lose the plot.
6. **Detail last**: edge softening, focal-zone detail, then materials/looks. Detail cannot
   rescue a bad proportion — it only makes it more expensive to fix.

Finish by reporting: the views captured, what the critique found, and the parameter set of
the final model.

## Hard rules

- `package:vector_math/vector_math.dart` — never the `_64` variant; the types are
  incompatible with flutter_scene.
- Native: `flutter run --enable-flutter-gpu`; web uses the engine's WebGL2
  backend without that flag. Bundle web renderer resources when a self-contained
  preview is required (`flutter build web --no-web-resources-cdn`).
- `await Scene.initializeStaticResources()` before building any geometry/material.
- `node.position.y = 1` does nothing — position/rotation/scale getters return copies;
  assign the whole value back.
- GPU-free by construction in the ecsly package: geometry math and the binder are pure
  Dart and must stay unit-testable. Renderer calls live only in the adapter's sink and
  view files (see the adapter reference).
- Determinism: models take a `seed` param and derive all randomness from it (e.g.
  `Random(seed)`, `FastNoiseLite(seed)`). Same params + same seed = same model, so a
  critique of view N applies to view N+1.
- Project labels and picks with the renderer camera's `worldToScreen` and
  `screenPointToRay`. The installed adapter's independent basis mirrored the
  horizontal axis in a live 0.23.0 trial; self-round-trip tests missed it.
- `PolylineGeometry` widths default to screen pixels. Set `widthMode` deliberately
  and update camera-facing geometry with `updateForCamera(camera, viewportSize)`
  when the camera, viewport or points change. An unexpanded strip can be invisible.

## Working inside ~/xs/ecsly

- `plugins/ecsly_flutter_scene` is an adapter with an **intentionally closed** shape
  vocabulary (`SceneShape`). Adding a shape to the enum is an upstream design change —
  rich per-entity visuals belong in your **app**, via the public `SceneSink` seam.
  [references/ecsly-adapter.md](references/ecsly-adapter.md) has the three extension
  patterns and the traps (including the polyline signature trap).
- The repo has its own working agreement (`AGENTS.md`): use the owning package's
  gate and `just check` before ordinary PRs. The inspected adapter declares Dart
  >=3.13 and Flutter >=3.47; the live consumer was verified on Dart 3.13.4 /
  Flutter 3.47.5. Do not claim Dart 3.12 consumer compatibility from old comments.
- For Flutter-dependent adapter/consumer checks use `flutter test`; GPU-free logic
  tests and real frame captures establish different evidence. Reuse the existing
  Flutter MCP toolkit/harness rather than inventing a new visual testing runtime.
- Maintain reusable consumer examples in `ecsly/examples/`; keep their automation
  in a separate owning tool environment. Temporary previews belong in an explicitly
  owned output directory with a cleanup lifetime, never an orphan scratch root.
  Do not put app/harness policy under `core_packages/`.
- For several model previews sharing an engine, use the canonical visualization
  host through `ecsly-visualization`: independent view worlds, camera/selection,
  addressed actions and removable registrations. Its real two-view trial passed;
  this does not qualify arbitrary view counts or native multi-window rendering.
