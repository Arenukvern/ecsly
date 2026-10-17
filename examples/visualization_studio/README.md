# Visualization studio

An unpublished consumer example of `ecsly_flutter` and `ecsly_flutter_scene`.
Its North Star impact is `applies`: it demonstrates existing package contracts;
it does not move branding, document policy or automation into the ECS runtime.

Three recipes share one resident world:

- **Graph:** six nodes, six dependency edges, spatial selection and orbit camera.
- **Simulation:** three oscillators with a fixed 1/60 second simulation schedule.
- **Linked views:** 33 samples with one selection shared by the 2D chart and 3D scene.

The warm paper/ink palette, rectangular keyboard controls and typography are
consumer art direction. `visualization_tokens` holds renderer-independent color
values; Material widgets are adapters rather than the visual specification.

## Run and check

Use Flutter 3.47 or newer with Dart 3.13.4 or newer. From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter create --platforms=web,macos .
flutter run -d chrome
```

Platform scaffolding is deliberately generated locally rather than copied from
another app. The build hook handles authored scenes/materials; flutter_scene
provides its engine shader assets. Generated manifests, bundles and build output
are not baseline fixtures. The bundled Roboto font includes its license.

## Reusable seams

| Surface | Responsibility |
| --- | --- |
| `visualization_frame.dart` | Renderer-independent Flutter layout frame |
| `preview_model.dart` | Recipe resources, fixed-step simulation and visual mappings |
| `retained_scene_sink.dart` | Stable scene nodes updated through the binder |
| `resident_document.dart` | Immutable versioned document validation |
| `resident_viewer.dart` | Validated transaction, request deduplication and frame receipt |
| `PreviewApp.onViewerReady` | Optional native tool/host adapter |
| `viewer_web_bridge.dart` | Browser action catalog over the same resident viewer |

Document updates accept `{document: <JSON string>, requestId: <string>,
expectedRevision: <integer>}`. Read the current document from `viewer.state()`;
copy it, increment its revision, then edit its title, accent or six graph nodes.
Validation happens before mutation. Reusing an identical request returns its
receipt; conflicting requests, stale revisions and malformed data refuse.
Camera and selection belong to a separate resource and survive document edits.

The browser exposes `window.__ecslyViewerState()` (JSON string) and
`window.__mcpActions.viewer_apply.invoke(args)` (Promise). These use the existing
CDP action-catalog convention without requiring a toolkit package. The bridge
owns its standalone action catalog; a host embedding multiple apps should merge
catalogs explicitly rather than overwrite another application's actions.

Native hosts can initialize their preferred toolkit in a separate entrypoint,
then mount `PreviewApp(onViewerReady: registerViewerTools)`. Register read-state
and apply-document handlers against the supplied `ResidentViewer`; no toolkit,
Oka or universal-automation dependency is required by this app. Harnesses belong
in a separate consumer environment with explicit repository/dependency inputs.

## Baseline and benchmarking

`test/preview_contract_test.dart` exercises camera projection/picking,
checkpoint restore, bounded geometry, retained binding and linked selection.
`test/resident_viewer_test.dart` exercises revisions, replay/refusal, selection
and camera continuity, and mounted title/palette changes. They are contract
oracles; they do not establish browser performance or independent pixel quality.

For runtime qualification, collect browser/engine/SDK versions, the exact build
mode and source revision. Keep these measurements separate:

1. Compiler startup and build completion.
2. Browser startup, navigation and first independently captured useful scene.
3. Warm document request to `presentedRevision` and `dataToFlutterFrameUs`.
4. Client round-trip observation and independent pixels/semantics.

`startup_trace.dart` records per-world monotonic owner timings in the viewer's
`startup.marksUs`: static-resource entry/return, initial ECS visual binding,
first renderer entry/return and first completed widget frame. The origin is world
creation, not navigation. `MeasuredScene` delegates through the public engine
rendering seam; a returned call does not independently verify GPU completion,
compositor presentation or useful pixels. The dogfood retains `startup.json` and
`first-scene.png` before interaction so those claims can be checked separately.

`presentedRevision` means a Flutter frame callback completed, not that a user
saw correct pixels. Preserve failed trials. Compare equivalent cold/warm cohorts
and recipe complexity before claiming improvement over another renderer. Native
offscreen screenshot readback and background focus require their own runtime
qualification; avoid activating user windows merely to collect benchmark data.

`VIEWER_FIXTURES=true` adds two deliberately duplicate scoped controls for
optional targeting/effect tests. It is off by default. Fixtures exercise input
contracts, not product UI. `visualizationCodeRevision()` in the tokens package
is a method-body probe for external-package hot reload and should be restored
after a qualification trial.

## Several previews in one engine

The same bundle supports a full-page preview and an embedded host. `multi_view.html`
contains two declarative host elements; its root `data-ecsly-multi-view` attribute
selects Flutter's public multi-view initialization. The bootstrap mounts each
`data-ecsly-viewer` element using its value as `initialData.viewerId`. Developers
can replace the HTML/bootstrap while keeping the Dart host and registry.

Each physical view owns a keyed widget subtree, world/controller, camera, selection
and checkpoint key. State reads accept an address: `window.__ecslyViewerState('alpha')`.
Document actions add `viewerId: 'alpha'` to the existing apply payload. Omitted
addresses work for exactly one mounted viewer; zero or several viewers refuse.
`window.__ecslyViewerViews()` lists addresses. The bridge adds only its owned action
to an existing catalog and refuses collisions. Host-supplied IDs must be unique
among mounted views and match `[a-zA-Z0-9_.-]{1,80}`.

Use the public `window.__ecslyEngine.addView({hostElement, initialData:{viewerId}})`
and `removeView(physicalViewId)` operations. Removing a view unregisters its address
and disposes its controller; stale teardown cannot unregister a replacement instance.
Remounting with the same logical address creates a new world and restores validated
checkpoint data, not runtime objects or the prior document. Native consumers inject
the mounted viewer through `onViewerReady`; the earlier process-global viewer
pointers were removed.

Checkpoint keys are now `preview.snapshot.<viewerId>`. The old global checkpoint
is deliberately not broadcast into multiple worlds. Hosts that need migration
should choose its destination explicitly.

`CheckpointCoordinator` supplies instance-bound handles over injected read/write
callbacks. The host shares one coordinator for its preferences namespace; each
key has a serial operation lane. Deactivation detaches its handle. An already
dispatched write can settle, but a replacement's write waits behind it and old
queued operations refuse before dispatch. A late restore refuses its result after
detachment. Failures do not poison subsequent operations; stale teardown cannot
release the replacement. Save errors remain visible in the shell.

Three controlled delayed-adapter regressions prove these process-local rules.
They do not prove native persistence durability or coordinate separate processes
or browser tabs. `CheckpointBootstrap` waits for `readSettled`, then refreshes
preferences before creating the world. It reads once per mounted host, retains
the future across metric changes, and shows a storage failure without starting a
world or retrying. A startup read waits for operations already queued when it
joins the lane; it does not promise a snapshot of future writes. Explicitly
constructed `PreviewApp` instances still accept an initial snapshot from their host.

This consuming host is based on [Flutter's public multi-view API](https://docs.flutter.dev/platform-integration/web/embedding-flutter-web).
The real two-view qualification exercises scoped input, catalog preservation,
independent document application, removal and checkpoint restoration on remount.
It does not prove arbitrary view counts, native multi-window behavior or live
conversation embedding. Historical prototypes under validation/raw_history and
generated output are excluded from current-source analysis.

The preview host accepts a `PreviewViewportBuilder`. `main.dart` selects the optional 3D adapter; `main_canvas.dart` selects Flutter painting. The skill scaffold's `--renderer canvas` removes scene source files, dependencies, scene-specific tests and the build hook, producing an engine-free app. Canvas renders dependencies, deterministic oscillators and linked observations from the same ECS state, with point picking routed through the same action. Scene mapping and instrumentation live in separate adapter files.

Web entry pages use a relative base. The bootstrap explicitly derives
`entrypointBaseUrl`, `assetBase` and `canvasKitBaseUrl` from `document.baseURI`,
passing the runtime configuration into `initializeEngine` as well as the loader.
This supports root hosting and Oka's `/bundles/<digest>/index.html` namespace
without embedding a digest into build bytes. These are the public
[Flutter loader configuration APIs](https://docs.flutter.dev/platform-integration/web/initialization).
The Canvas digest-hosted and ordinary multi-view trials pass separately; broader
browser/renderer and arbitrary host-subdirectory compatibility remain unqualified.
