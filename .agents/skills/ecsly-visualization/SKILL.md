---
name: ecsly-visualization
description: Build and verify interactive Flutter explainers, dependency graphs, spatial simulations, and linked chart/scene views using ecsly_flutter, Flutter painting, and optional ecsly_flutter_scene. Use for runnable visualization experiences and reusable previews; delegate individual 3D model craft to flutter-scene-modeling. When no product design system exists, critique palette and type with frontend-design; when one exists, that system is the brief. Inline HTML conversation visuals remain the visualize skill's domain.
---

# Ecsly visualization

Start with the question the reader should answer and the interaction that reveals it.
Choose the smallest useful visual: Flutter widgets/painting for text, controls and
quantitative plots; flutter_scene for spatial marks when depth or motion adds meaning.
A chart does not need to become 3D because ECS is available.
Fast iteration of Flutter UI, motion, and visuals (any platform, optional scene,
optional Oka) is [flutter-design-loop](../flutter-design-loop/SKILL.md). This
skill owns explainer composition and the studio scaffold.

## Start from the verified preview

Use [the scaffold](scripts/scaffold.dart) to create a consumer from
[the canonical example](../../../examples/visualization_studio). The example includes three recipes:
dependencies, parameterized oscillators, and one observation selected in both a 2D
chart and 3D scene. Read [the workflow](references/workflow.md) for commands and
[verification evidence](references/verification.md) before making readiness claims.
The scaffold defaults to Flutter Canvas. Use `--renderer canvas` for a consumer with no flutter_scene or ecsly_flutter_scene dependency and no scene build hook. The host accepts a `PreviewViewportBuilder`; the model, document, checkpoints, actions and startup trace do not import a scene engine. Use `--renderer scene` only when depth adds meaning.

Choose an explicit output directory and record its owner/lifetime; never create an orphan scratch root. Keep consumers outside ecsly's core packages. In an existing app, adapt its
scope/controller/theme rather than mounting a second world or copying the whole host.

## Compose the experience

- Keep one dominant visual, compact relevant controls, and a selected-item detail.
  Put labels, legends and semantic controls in Flutter overlays, not text meshes.
- Use one ECS world. Put records in components and small coordination choices in
  resources. Reuse `EcsAppScope`, `EcsController`, `EcsAction` and typed selectors;
  do not introduce another notifier/action bus around them.
- Select immutable values or records from mutable resources. Selecting the mutable
  resource itself can compare equal after mutation and leave cached widgets stale.
- The simulation host owns time. Use `EcsFrameSchedule.fixed` with bounded catch-up
  for deterministic simulation; do not advance time in `build` or in a second timer.
  Pause on reload so a saved observation can be inspected. Bound runs at an endpoint.
- Keep theme, camera and selected observation in a versioned checkpoint. Restore
  validated finite values and valid ids; renderer objects and runtime entity handles
  do not belong in persisted state. Persistence must have an observable failure.
- For linked views, both derive from the same selection. Verify selection in each
  direction; two similar-looking independently updated panels are not linked.

## Rendering seams and real traps

For repeated authoring, use the template's `ResidentViewer` and versioned
`VisualizationDocument`. Apply data through its browser action catalog or an explicitly injected native toolkit adapter,
with a request ID and expected revision. Labels, positions, title and palette change
in the same world; no compiler is involved. Keep arbitrary widget/renderer edits
in an owning dev session. The package-owned dogfood tool in `tool/visualization_dogfood` consumes Oka browser-page sessions and the shared automation family; process governance uses Oka supervisor. Native toolkit wiring is optional through `PreviewApp.onViewerReady`.

For several previews in one engine, use the example's `MultiViewHost` and the
public Flutter addView/removeView lifecycle. Address document actions and state
reads with `viewerId`; omitted addresses refuse when several viewers are mounted.
Each view owns its world, camera, selection and checkpoint key. Removing a view
unregisters its actions and disposes its controller. A stable host-supplied
`initialData.viewerId` restores its checkpoint on remount. The bridge merges its
owned action into an existing catalog and refuses a name collision. Never use a
process-global current viewer or let one view overwrite another's actions.

Art direction belongs to the consumer. The template includes renderer-independent
tokens and accessible `ViewerButton`/`VisualPanel` primitives. Material is an adapter,
not a requirement for the appearance. Keep animation, contrast, label density and
camera composition deliberate; do not infer a quality/performance win over JS from
using a different language or engine.

If the host app already has a design system, that system is the brief. Do not
restyle an explainer with a new palette beside it. When the consumer has no
system, read [frontend-design](../frontend-design/SKILL.md) before choosing
type, color, or layout. Spend boldness in one place. Labels stay Flutter
overlays. Copy names the question the view answers. Motion answers selection
or playback; it does not decorate every mark. Capture a frame and remove one
accessory before calling the composition done.

Read [rendering notes](references/rendering.md) before implementing the viewport.
The following scene mapping, camera and polyline guidance applies only when the
consumer explicitly selects the scene adapter. For Canvas or widget-only views,
use the consumer's painting/layout and picking APIs through `PreviewViewportBuilder`.
Use `SceneMapping` → `EcsSceneBinder` → a consumer `SceneSink` for ECS-driven marks.
The shape enum is closed. Richer visuals and retained updates belong in the consumer.

Use the renderer camera's `worldToScreen` and `screenPointToRay` for labels/picks.
The installed adapter's independent basis was horizontally mirrored relative to
flutter_scene 0.23.0 in the live trial. A projection/pick round-trip using only that
basis cannot discover the disagreement with rendered pixels.

`PolylineGeometry` defaults to screen-pixel widths. Set width units deliberately
and call `updateForCamera(camera, viewportSize)` on the installed engine when the
camera, viewport or curve changes; unexpanded strips can render no links.

The adapter's default signature rounds positions and ignores polyline coordinates.
The template's `ExactVisualState` supplies a full-content signature through the public
seam. It is suitable for these small examples, not an unmeasured large-world policy.
Retain nodes/materials for transform-only updates; rebuilding moving geometry every
step adds allocation and upload work. Measure before extending this to instancing.

For engine code, read the installed official `flutter_scene-idioms` skill. For models
whose silhouette/material craft matters, use `flutter-scene-modeling`; artistic idle
motion belongs there, while an explanatory simulation should move only when useful.

## Readability and access

Use theme-derived colors and stable encodings. Pair selection/category color with
shape, size or text. Label quantities and units; use honest shared scales and show
uncertainty when it exists. Source geographic geometry rather than drawing guesses.

Check 320px, the normal host width and a wide desktop width, plus enlarged text.
Stack chart/scene panels when labels stop fitting. On narrow spatial views show the
selected label and offer an accessible item list instead of overlapping nameplates.
Keep keyboard alternatives, focus and touch targets usable; do not announce hover or
simulation frames as live-region updates. Default to a useful paused first render.

## Verify with the existing automation family

Read [workflow.md](references/workflow.md). Prefer the Flutter MCP toolkit and
`flutter_mcp_harness` over ad hoc browser scripts:

- Native/debug: toolkit semantic snapshot → action → fresh observed effect,
  OS window capture + console/error read. On this tested SDK, toolkit offscreen
  scene capture was associated with later glyph corruption; keep the native pixel
  oracle separate from interaction checks (see verification.md). Run doctor with the exact WS URI and discover
  required extensions. Explicitly focus a widget before sending keyboard events.
- Built Flutter web: `ChromeAppTarget` + `CdpDriver` / `FlutterWebCdp`, with a headless
  browser by default and preserved owner/borrower boundaries. Flutter semantics are proxy DOM
  nodes: use the supported stable-rectangle, effect-verified helper when the browser
  DOM hit-check does not model Flutter's pointer forwarding. Do not force a stale click.
- A detached debug binary has no expression compilation service. For repeatable state
  reads register a read-only `AgentCallEntry.resource`, discover its extension, and
  pass its required URI. Keep adapters thin over the same app state/actions.
- Capture the actual frame before discussing appearance. Compiler/unit success and
  a non-empty accessibility tree do not prove rendered links, label alignment or picks.

## Delivery and honest boundaries

Use Oka's existing web target for build composition; its current compiler step
explicitly delegates to Flutter. Bundle web renderer resources and fonts for a
self-contained local preview. The template uses `--no-web-resources-cdn` because a
real initial CanvasKit CDN request failed before Dart started.

A Flutter web build is not an inline HTML fragment. The conversation host's allowed
origins, fragment size, loader/resource policy and bridge must separately qualify.
Do not emit a visualize reference for a Flutter build or claim inline embedding from
an ordinary browser preview. Report source, commands, captures, observed interactions
and remaining limits; do not claim JS/Rust performance parity without equal workloads.

Sources and ownership: [sources.md](references/sources.md).
