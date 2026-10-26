# Supervised visualization qualification

`novel-damped` qualifies the independent plain-object `__dampedState()` contract
of [the damped oscillator](../../examples/damped_oscillator/README.md) with the
existing driver/effect APIs and an analytical reference. It does not require
the resident studio's action bridge. `novel-damped-responsive` adds 320px scroll
captures and requires scrolling to preserve model state. These are consuming
fixtures, not new transports. The original paired skill evaluation archives its
first oracle; the subsequent extracted-app epoch waits for the same semantic
label using the existing harness retry helper, without replaying input.

This separate Dart consumer uses Oka's browser lifecycle, shared CDP targeting and
one bounded Oka supervisor job. It owns only the browser/server it starts. Job
success follows worker completion and teardown; nonzero exit remains a failure.
It requires the repository versions containing the browser-page API and runToExit
provider fixes. Neither is a published-version claim.

From this directory:

```sh
dart run configure.dart --oka-root /path/to/oka --automation-root /path/to/dart_flutter_packages
dart pub get
dart run bin/build.dart /path/to/ecsly/examples/visualization_studio /path/to/flutter
dart run bin/supervise.dart /path/to/ecsly/examples/visualization_studio /owned/evidence/trial-1
```

Build first resolves the app dependencies (`flutter pub get` in the example).
The build accepts the Flutter SDK directory; scaffolding accepts its executable.
Additional explicitly supplied Flutter build arguments are forwarded by build.dart
and recorded in the build receipt; the scene preparation lab uses this seam for
its opt-in shader policy. `shader-probe` is a separate supervisor scenario for
that lab's generated consumer, which provides the required experimental backend
probe. Ordinary examples do not expose it. It verifies same-source reload identity
and first-use error recovery, not changed-shader pixels.
`missing-physical` is a separate negative scenario for the structural engine lab.
It renames the required physical entry only in the HTTP-served payload and verifies
a named initialization failure, visible accessibility text and no renderer entry.
It leaves the compiled bundle unchanged. Its success proves expected failure
handling; it does not stand in for the normal six visual interactions.
Use a fresh evidence directory for an explicitly named new trial after a diagnosed
failure. Revision is fixed rather than time-derived; repeat converge within the same
registry must not reset the restart budget. Forced-crash/orphan recovery remains a
separate qualification requirement. Do not replace unknown receipts with retries.
The supervisor entrypoint refuses any existing evidence path before creating its
plan or starting a worker. This guards sequential reuse; it is not an atomic
cross-process reservation protocol.

Evidence separates host/browser attachment, app state, scene semantics, completed
Flutter frame, effects, runtime errors and independent captures. The worker verifies
the actual viewport before input. Window size is not a platform-independent viewport
guarantee. Captures must be inspected; this runner is not an aesthetic or performance
acceptance oracle. The six interactions cover graph selection, resident continuity,
recipe changes, deterministic stepping and theme. Native, multi-view, large-scene,
compiler-incremental and browser-alternative lanes have separate owners and gates.

Single-view runs additionally retain `startup.json` from the app's monotonic
per-world trace and an early `first-scene.png`. The first-render-return timestamp
is distinct from screenshot receipt time and widget-frame completion. It exposes
where synchronous renderer preparation occurs without claiming compositor timing.
Compare deltas within the app clock; do not subtract them from browser/server
timestamps, which have different origins. Multi-view startup cohorts remain separate.

For the same bundle's two-view host, add `multi-view` as the third argument to
`bin/supervise.dart`. This declares a separate bounded job and opens multi_view.html.
The qualification addresses both worlds, exercises scoped camera input, preserves
the embedding host action catalog, removes one physical view and remounts it from
its namespaced checkpoint. Preserve failed runs. Source/receipt continuity is
checked separately from captured pixels. A successful two-view trial establishes
only this workload, not an arbitrary-view-count memory/performance claim.

The multi-view job now retains `startup-cohort.json`: both initial views and five
fresh alpha worlds mounted in the same resident engine. Each remount verifies
checkpoint restore and unchanged beta state. World-relative first-render timings
are separate from host addView-to-observation and removal timings. Initial views
overlap resource loading; these are not two independent cold samples. The cohort
does not establish a p95, compositor-present deadline, memory plateau or equivalence
to a particular JavaScript workload. Inspect `multi-view-final.png` as well as the
structured state checks.

Build measurements now retain immutable `output/validation/build-trials/*.json`
receipts, plus `build.json` as a compatibility pointer to the latest result. Each
receipt records mode/flags, toolchain roots, timing and a SHA-256 consumer source
snapshot. It does not fully fingerprint the SDK/dependency/native shader closure;
that remains necessary before claiming reproducible binary or cache validity.

The tool lockfile produced with editable overrides is ignored because it contains
machine-specific repository paths. Preserve exact tool/dependency versions in an
owned trial receipt; a distributable locked tool requires published compatible
packages and a separate release gate.

The same build and supervisor commands accept the scaffold's `--renderer canvas` consumer. It excludes both scene dependencies and their build hook. The worker accepts the Canvas paint-return trace as renderer readiness. Both paint-return and scene render-return describe owner work, not compositor presentation. Optional source directories such as `hook/` need not exist for build provenance.

Use `retained-browser` as the supervisor scenario to run the ordinary six effects
followed by three fresh page attachments in the same owned browser. It checks
independent runtimes, unchanged owner state and lease, and removal of each borrowed
page. Only page targets are stable tab identities; iframe and worker targets have
their own lifetimes. The target catalog and per-borrower observations are retained.
`retained-browser.json` separates browser reuse, page attachment and observed
renderer timings. Owner process teardown still occurs before job completion.
This workload is distinct from `multi-view`, which retains a Flutter engine, and
from resident document application, which retains the viewer world.

For native focus qualification, scaffold a separate Canvas consumer with
`--platforms macos`, build its debug app with the chosen Flutter SDK, and run the
supervisor with `native-background` or `native-hidden`. The native worker locates
the single prebuilt app and the probe in the explicitly configured editable Oka
dependency. It keeps source hash, logs, launch intent and the receipt. The probe
refuses a locked/unavailable desktop or an existing instance. Success covers only
nonactivating launch, an observed normal window and returned-process teardown.
Background/hidden frame progress, native pixels and dev/compiler attachment need
separate qualification; failure and unknown launch receipts are retained.

`native-runtime` additionally enables the consumer's opt-in debug diagnostics,
using the Flutter MCP harness VmClient to enumerate viewers and call the existing
resident state/action adapter. URI discovery stays inside the app sandbox
container and is collected into the trial; the app sandbox is not disabled.
Engine bootstrap, VM discovery, viewer mount, initial Canvas paint and applied
revision frame are separate observations. The native driver captures only the
owned window through OS APIs; inspect its geometry and pixels separately. A
transformed/small background-window capture does not prove full-resolution preview
quality or a compositor-present deadline. The app never needs runtime expression
evaluation for these checks.

For the editable universal-automation action union, supply a compatible harness:
`configure.dart --oka-root PATH --automation-root PATH --flutter-harness-root PATH`.
The observed published harness 7.0.0 lacked ClickAtAction handling; the local
harness already provides it and is reused without editing its source. Native
capture lives in its separate `native_capture` package: run `dart pub get` there
once after configuration. Its hooks run only in the native capture process,
keeping the browser supervisor dependency graph free of native-driver build hooks.

`native-attach` extends the native runtime trial with Oka's experimental Flutter
compiler attachment. Supply `ECSLY_NATIVE_FLUTTER_SDK` explicitly. It changes one
copied token-package method, reloads once, checks the running code revision and
resident state, detaches the compiler while the app remains readable, restores
source, then lets the original app owner perform teardown. The 120-second app
observation budget bounds this qualification. This is one method-edit workload;
restart, signature/import edits and crash recovery need separate trials.

`native-dev` qualifies the integrated Oka CLI --native-vm-uri path using one
externally owned background app. It edits a copied method, issues Oka r [file],
checks the running code and retained world, then issues q and verifies the app
remains readable before its original owner stops it. Supply the explicit Flutter
SDK as for native-attach. A locked desktop is a named preflight refusal, not a
focus or native runtime success; preserve the refusal and wait for desktop state
to change before another live trial.

`native-dev-cohort` extends that session with compatible signature and import
edits, a hot restart, and another reload in the restarted runtime. Reloads must
preserve world/document/camera/selection. Restart must create a fresh runtime
with the current code and reset transient document/apply state. Reconnect the
read-only VM observer and use the harness's bounded extension-readiness polling
before inspecting the new world; the compiler's restart receipt can precede
extension registration. Per-edit state and source-to-observation timings are
retained separately from the restart receipt and compositor/pixel evidence.

Schema-2 build receipts include Oka's outputBundle manifest. The worker captures
the bundle at startup and requires it to match that identity before starting a
server/browser. It verifies asset bytes before serving and responds with a
recorded violation if bytes changed. Legacy receipts remain accepted with an
explicit runtime-capture identity basis; they do not establish build linkage.
Source and transformed-response hashes are separate for negative shader fixtures.
A full output manifest does not fingerprint SDK/dependency inputs or guarantee
atomic filesystem capture/reproducible compilation. Browser caching remains a
separate qualification lane.

`browser-cache` opts into verified HTTP revalidation while ordinary runs keep
no-store. It runs six effects, reloads the same page into a fresh engine/world,
requires real first-load 200 and matching-tag 304 responses, and sends a stale
If-None-Match control that must receive the current body. Browser response events
and server records are separate. Reload-to-frame observation is captured before
the stale request. This does not prove immutable deployment URLs or input cache
validity, and a fresh-engine reload is distinct from retained-world application.

`immutable-bundle` loads Oka's verified immutable byte snapshot with a 64-MiB
payload budget and runs the same six visual effects from those captured bytes.
It additionally requests a digest-addressed main-JS asset, checks its exact hash
and immutable cache headers, and requires a wrong bundle identity to return 404.
The scenario opens `/bundles/<digest>/index.html` and refuses unaddressed root
fallbacks. The example's relative base and explicit loader/engine configuration
keep entrypoint, CanvasKit and assets in that namespace. The route check uses a
real HTTP client; a separate real browser reload requires main-JS cache reuse,
records disk-cache/memory-cache events and validates namespaced server requests.
Ordinary scenarios retain their mutable entry URL and no-store policy.

`native-capture-sck` extends the background native runtime qualification with
Oka's opt-in ScreenCaptureKit window probe. Both the existing driver PNG and
window-specific SCK PNG/geometry receipt are retained. The probe uses existing
capture permission and nonactivating AppKit initialization; it never activates
the target window. Inspect actual pixels and point/pixel dimensions before
calling the capture full-resolution. It does not modify the shared macOS driver.

`native-input` uses an isolated PID-bound MacosDriver child, initializes native
accessibility without activation, requires one matching graph button and attempts
semantic AXPress. The parent independently checks a changed selection via the VM
resource, preserving resident identity/document. Missing or duplicate targets
refuse before input; no global coordinate fallback is used. The first live trial
found menus but no AX window/button subtree, so it refused and remains failed.
Successful rendered frames and lifecycle checks do not establish native input.

For read-only host diagnosis, scaffold a fresh Canvas macOS app, then run
`bin/prepare_native_window_probe.dart PROJECT UNIQUE_BUNDLE_ID` before its first
native build. It installs a debug-only MethodChannel/service-extension pair and
records patched source hashes. `native-window-state` records visibility, active
Space, key/main status and native accessibility counts while retaining the same
background launch/runtime/capture/teardown checks. Existing built/prepared apps
refuse preparation; prior consumer sources stay intact.

The optional `--join-all-applications` preparation flag declares an experimental
AppKit collection policy for the disposable fixture: canJoinAllSpaces,
canJoinAllApplications and fullScreenAuxiliary. It can place the viewer alongside
other apps across Spaces; it is not the scaffold/default app policy. It contains
no activation or key-window command. Qualify actual focus, placement and native
input before adopting it in a developer's host. The debug state extension remains
read-only regardless of the fixture's declared startup policy.

`--floating-preview` is another experimental fixture profile: the same collection
eligibility plus floating level and explicit non-key window ordering. Both
collection-only and floating variants failed to expose native AX controls in the
recorded environment. Floating also fails the launcher’s existing normal-layer
window criterion. Retain them as negative baselines; do not adopt either as a
verified background accessibility fix. The instrumented Flutter toolkit or a
specific native-host lifecycle reproduction is the next diagnostic route.

Native toolkit qualification uses the existing Flutter MCP harness ToolkitDriver
and Universal Automation verifyEffect against an independent resident-state
extension. `native-toolkit` checks four button effects and forces a real stale
snapshot between resolution and dispatch, requiring refusal with unchanged state.
Prepare a fresh consumer with `bin/prepare_toolkit_preview.dart PROJECT
MCP_FLUTTER_ROOT BUNDLE_ID AUTOMATION_ROOT`; the explicit automation root keeps
local toolkit and hosted semantics dependencies on the same interface source.
The native launch receipt retains OS activation events and owned teardown.

For web foreground observation, run `native_capture/bin/check_focus.dart` using
the native_capture package configuration and pass a fresh receipt path followed
by the supervisor command. It samples the existing MacosDriver.frontmost during
launch, actions and teardown. Receipts disclose the maximum sample gap; short
transitions between samples remain outside this observation's coverage.

The native toolkit qualification now also prepares widget-focus/keyboard proof:
scroll to the exact Frequency slider within its semantic container, call the
existing targeted focus capability, retain a fresh focused snapshot, then observe
ArrowRight's frequency delta independently. The macOS SDK fixture expects 0.15 Hz
(normalized 0.1 step over range 0.5..2.0). `native-focus-key-2026-10-14-frame-a`
passes this real native effect after fixes in the existing harness/toolkit:
fresh unique scroll refs and active RenderView semantics owner. Toolkit focus
now awaits actual completed frames rather than three16ms delays; a withheld-frame
regression fails the old loop and passes the new one. Missing frame completion
returns focus_frame_unobserved without replay. This does not prove OS keyboard
delivery. Earlier `native-focus-key-2026-10-14-a` was refused because the native
desktop preflight reported locked. Retain that refusal and rerun with a new
evidence directory only after a desktop-ready observation; never bypass the
launch preflight or reuse an earlier button-only receipt as keyboard proof.

For optional native semantic text proof, add the package-owned fixture to an
explicitly owned toolkit consumer with
`prepare_semantic_write_probe.dart PROJECT MCP_FLUTTER_ROOT`, then optionally
`prepare_native_window_identity.dart PROJECT MCP_FLUTTER_ROOT` before rebuilding.
The current native-toolkit qualifier discovers the live schema before invoking
semanticOnly, checks Dart controller/focus/callback effects, and refuses a
nonempty Flutter error buffer. The text fixture uses portable Dart3.10 syntax;
an installed newer SDK does not override the consumer's language declaration.

Text focus may create an invisible TUINSWindow alongside the Flutter host. The
optional read-only host channel supplies its actual window ID, independently
checked for PID/layer0 membership before existing-driver capture. Wrong-owner
capture refuses. Unbound capture still requires one normal window. Run
native-window-identity-2026-10-14-d passes with an inspected PNG and empty error
buffer; c's green worker result is disqualified by its red ErrorWidget image.
The fixture now distinguishes keyed replacement from a second physical view.
This remains a diagnostic adapter, not a general native-target API.

Offscreen discovery is now provided by the existing Universal Automation driver:
`MacosDriver.windows(pid: ownerPid, onScreenOnly: false)`. The consumer has no
Swift discovery subprocess or temporary script. It correlates an explicit host
ID with those observed owner records and captures through windowScreenshot.
The API retains on-screen default behavior and nullable visibility; absent
onScreen must not be treated as false. native-ua-window-2026-10-14 passes this
driver path with inspected pixels, clean errors and unchanged foreground samples.

Explicit Wasm lane: scaffold an owned `--renderer canvas` web consumer, build
with `dart run bin/build.dart PROJECT FLUTTER_SDK --wasm`, then qualify with
`dart run bin/supervise.dart PROJECT NEW_EVIDENCE wasm`. The job applies Oka's
opt-in WebIsolationPolicy.requireCorp headers and requires the app's compiled
Wasm flag, served main.dart.wasm, browser crossOriginIsolated and real recipe
effects. It also bypasses the client schema once with a fractional revision and
requires bridge refusal with unchanged state. Serve .mjs as JavaScript modules.
Browser logs, served requests and resident dispatch/effect receipts survive both
success and failure. Flag/resource/isolation proof is distinct from renderer
thread count, first compositor presentation and comparative performance.
The same source can be built without --wasm; its runtime flag must be false.


For a bounded JS/Wasm comparison, build two fresh consumers from identical
canonical source, then run:

```sh
dart run bin/compare_lanes.dart JS_PROJECT WASM_PROJECT NEW_EVIDENCE
```

The driver checks recorded consumer source/SDK identity, runs three alternating
JS/Wasm pairs through the existing Oka supervisor, and requires actual runtime
mode, isolation, browser version and independently observed effects. Each trial
owns a fresh browser/profile. `trials.json` preserves raw observations;
`result.json` reports medians and limits. The first-capture clock starts inside
the worker and excludes compilation of the supervisor/worker. Neither capture
completion nor Flutter frame completion proves compositor presentation. This is
JS/CanvasKit versus Wasm/SkWasm, with host load and filesystem caches uncontrolled.

The 2026-10-14 cohort passed all six trials (nine checks each). Worker-to-capture
medians were 1764.642 ms (JS) and 1592.267 ms (Wasm); resident data-to-Flutter-frame
medians were 16.670 ms and 17.951 ms. Actual uncompressed served payloads were
7,952,709 and 5,841,643 bytes. This small cohort is not a p95 or universal speed
claim. Fresh foreground sampling `web-focus-2026-10-14-g.json` recorded no PID
change across 259 samples (maximum gap 29.426 ms), but the desktop was locked;
it does not extend the earlier unlocked native focus qualification.
