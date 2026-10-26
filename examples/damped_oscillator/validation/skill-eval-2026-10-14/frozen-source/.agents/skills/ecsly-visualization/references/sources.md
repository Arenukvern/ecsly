# Sources and provenance

Verified local stack on 2026-10-13: Flutter 3.47.5 / Dart 3.13.4;
flutter_scene 0.23.0; local ecsly 0.0.1-dev.13, ecsly_flutter 0.1.0-dev.4,
ecsly_flutter_scene 0.1.0-dev.1; Flutter MCP toolkit/harness 7.0.0;
universal_browser_cdp 0.3.0; Oka core/web 0.6.0.

| Source | Used for |
|---|---|
| [Visualize skill](/Users/antonio/.codex/plugins/cache/openai-bundled/visualize/1.0.49/skills/visualize/SKILL.md) | Composition, host boundary, themes, accessible interaction and state |
| [Scene modeling](/Users/antonio/.agents/skills/flutter-scene-modeling/SKILL.md) | Model craft and consumer sink extension boundary |
| [Engine idioms](/Users/antonio/.pub-cache/hosted/pub.dev/flutter_scene-0.23.0/skills/flutter_scene-idioms/SKILL.md) | Correct API/setup; pinned local engine |
| [Engine verification](/Users/antonio/.pub-cache/hosted/pub.dev/flutter_scene-0.23.0/skills/flutter_scene-verification-loop/SKILL.md) | Frame plus console and bounded visual iteration |
| [ecsly Flutter bridge](https://github.com/Arenukvern/ecsly/tree/main/core_packages/ecsly_flutter) | Scope/controller/action/selector/fixed-step ownership; local source checked |
| [Scene adapter](https://github.com/Arenukvern/ecsly/tree/main/plugins/ecsly_flutter_scene) | Mapping/binder/sink public seams; local source checked |
| [Flutter MCP harness](https://github.com/Arenukvern/mcp_flutter/tree/main/packages/harness) | Native toolkit and browser lifecycle/scenarios; local current contracts checked |
| [Universal CDP](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/universal_browser_cdp) | Typed browser driver and live semantic targeting |
| [Oka web](https://github.com/Arenukvern/oka/tree/main/packages/oka_web) | Typed web build delegation and shell/session boundaries |
| [Dart web](https://dart.dev/web) | DOM/JavaScript interop; language is independent of Flutter runtime |
| [Dart Wasm](https://dart.dev/web/wasm) | Compilation/runtime distinction |
| [Rust browser interop](https://wasm-bindgen.github.io/wasm-bindgen/examples/dom.html) | Rust/Wasm can use browser DOM APIs |

The template and evidence were produced in
[the preview project](../../../../examples/visualization_studio).
Local captures carry stronger version-specific evidence than repository landing pages.

2026-10-13: initial source comparison and live consumer trials. See verification.md
for the exact completed checks and non-claims.

Resident extension, checked 2026-10-13: consuming `lib/resident_document.dart`,
`resident_viewer.dart`, `visual_language.dart`, pure Dart visualization tokens and
`tool/automation/lib/resident_preview_session.dart`; DFP
`universal_automation_interface/lib/src/targeted_automation.dart` and
`universal_browser_cdp/lib/src/cdp_semantic_targeting.dart`; Oka experimental
`tool/dev_browser_session.dart`, `dev_watch_inputs.dart`, `oka_run_dev.dart` and
ADR 0044. Installed Flutter engine `semantics/incrementable.dart` documents the
pointer/browser-gesture range proxy; `view_embedder/dom_manager.dart` defines the
`flutter-view` ownership boundary. Actual consuming trials qualify the bounded
behaviors listed in verification.md, not every behavior in those libraries.

2026-10-13: canonical multi-view host uses [Flutter web embedding](https://docs.flutter.dev/platform-integration/web/embedding-flutter-web)
and the installed Flutter 3.47.5 View/ViewCollection, runWidget and ui_web initial
data APIs. The consuming registry enforces logical address uniqueness and
instance-matched teardown; bridge callbacks use optional arguments for single-view
reads. The same bundle's real single/two-view jobs are recorded under the canonical
example output/validation directory.

2026-10-13 renderer-independent source boundary: canonical `preview_app.dart`,
`preview_shell.dart`, `preview_model.dart`, `startup_trace.dart` and
`preview_canvas.dart` use the existing ecsly Flutter controller/scope/action
contracts. The builder typedef is consumer-owned; it is not a new core runtime
contract. `preview_mapping.dart`, `measured_scene.dart` and `preview_scene.dart`
contain the optional 3D adapter. Scene-free generated dependency graphs and
Canvas picking/isolation tests qualify the absent-engine boundary separately
from scene trials.

2026-10-13 namespaced web loader: [Flutter initialization documentation](https://docs.flutter.dev/platform-integration/web/initialization)
documents entrypointBaseUrl, assetBase and canvasKitBaseUrl. A custom
onEntrypointLoaded callback must pass runtime configuration to initializeEngine
explicitly. Installed Flutter 3.47.5 loader source was also inspected. The example
uses these APIs with a relative base; real Canvas jobs qualify digest-hosted
startup/cache reload and ordinary multi-view compatibility.
