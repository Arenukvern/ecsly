# Verified consumer evidence — 2026-10-13

Historical trials used the prototype from which the [canonical preview project](../../../../examples/visualization_studio) was extracted. Archived receipts are under its validation/raw_history directory. This is bounded implementation/live-trial evidence,
not canonical harness acceptance, cross-client certification or operator adoption.

| Lane | Result | Evidence |
|---|---|---|
| Preview analysis | No issues | output/evidence/analyze.log |
| Preview focused contracts | 6 passed | output/evidence/tests.log |
| Real headed Chrome/CDP | 7 checks passed | output/evidence/cdp-run.log and cdp/result.json |
| Real macOS/debug toolkit | 7 checks passed | output/evidence/native-run.log and native/result.json |
| ecsly_flutter package | 37 tests passed; analysis clean | output/evidence/ecsly-flutter-tests.log and ecsly-flutter-analyze.log |
| universal_browser_cdp package | 71 tests passed | output/evidence/cdp-package-tests.log |
| Oka WebBuildTarget | Built actual web artifact | output/evidence/oka-build.json |
| Skill scaffold | Regenerated app; analysis clean and 6 tests passed | output/evidence/scaffold.log; generated app is ../ecsly_visualization_from_skill |
| Skill format | Both skills pass quick_validate.py | Validator run with the existing Codemap Python environment (PyYAML available) |

Focused contracts cover renderer-camera/pick correspondence at off-center points,
checkpoint bounds/restoration, moving same-length curves and sub-.01 movement,
repeatable fixed steps, shared selection, and 320/736/1120px layouts at 1.6 text scale.
These tests substitute the scene viewport; they do not prove GPU pixels.

The live browser checks exercise graph selection, exact displayed stepping and
frequency input, playback/freeze, a chart click reflected in the selected spatial
observation, checkpoint reload, dark theme, and responsive frames at 736 and 320px.
The native checks exercise graph selection, the exact 1/60s state delta, playback,
explicit slider focus followed by a keyboard increment, checkpoint restoration,
required toolkit extensions/doctor, and no toolkit app errors. The app resource
provides state without needing expression compilation in the detached debug binary.

Raw frames were inspected, including graph, simulation, linked view and narrow dark
view. Initial invisible polylines, mirrored labels, truncated oscillator labels and
stale dark-theme text were observed and corrected. Final captures are under
[CDP evidence](../../../../examples/visualization_studio/validation/raw_history/2026-10-13/output/evidence/cdp)
and [native evidence](../../../../examples/visualization_studio/validation/raw_history/2026-10-13/output/evidence/native).

## Changes supported by the trials

- Consumer camera APIs replace the adapter's mirrored independent basis.
- Explicit line width units and updateForCamera render links/trails.
- ExactVisualState updates curve contents and small movement; retained sink updates
  sphere transforms without creating replacement nodes.
- ecsly_flutter resource selector's cached child now owns a Builder context, so
  Theme/MediaQuery dependencies can refresh independently of an unchanged ECS value.
  Existing selector invalidation profile and full package tests remain passing.
- universal_browser_cdp stringifies numeric AX values and ignores queued socket frames
  after client closure. The slider failure was reproduced before the value patch.

The two package fixes are local working-tree changes, not published prereleases.
The generated template uses local dependency overrides; other machines need those
fixes or independently verified newer package revisions.

## Measured packaging cost and non-claims

The first Flutter web build took 48.8 seconds including a Wasm compatibility dry run.
The final Oka-delegated build receipt records 40.496 seconds for its measured run.
One local uncompressed reload recorded 12,395,408 transfer bytes over 19 requests:
about 5.43 MB CanvasKit Wasm, 2.53 MB main JavaScript, 1.22 MB base shaders and
2.49 MB physical-material shaders, plus fonts/textures. This is that page's resource
population, not a cold-network benchmark or total package size.

No equal-workload JS/Dart/Rust frame-time comparison was run. No Rust app or Wasm
release was executed (the first Flutter build's Wasm dry run is compilation only).
No inline Codex embedding, 5,000-node scale, map recipe, exported scientific figure,
or general custom-sink picking was qualified. The installed adapter's default
signature and camera math are still upstream limitations; this consumer uses public
extension seams and renderer camera APIs. Oka web currently delegates compilation
to Flutter; it is not a replacement compiler or a custom browser engine.

The follow-up [runtime design analysis](../../../../examples/visualization_studio/validation/raw_history/2026-10-13/RUNTIME_DESIGN.md)
separates Oka's existing Flutter-run/DWDS development lane from that measured
release build. It records remaining automation targeting/focus/effect gaps,
resident-viewer delivery options and bounded Chromium/Ladybird experiments.
Those recommendations are source-backed proposals, not additional runtime results.

## Resident/session/targeting extension — 2026-10-13

The second consuming slice adds versioned document application, correlated request
receipts, a prebuilt browser session and a replaceable frame-request callback. It
keeps one ECS world and its existing selection/camera. Material-default chips and
buttons were replaced by a consumer visual vocabulary and pure Dart color tokens.
The three installed recipes remain the scope; six graph nodes are schema-1's bound.

- Current preview contracts: 9 passed. Fresh skill regeneration: analysis clean,
  9 tests passed (`ecsly_visualization_resident_from_skill`).
- Resident native and web trials: 7 checks each passed. Evidence is in the scratch
  project's `output/evidence/resident-native/` and `resident-web/` result JSON,
  frames and request/effect records.
- Interface package: 61 tests passed. CDP package: 76 tests passed. Consumer native
  targeting adapter: 3 tests passed. The adapter uses existing toolkit verbs and
  does not modify the other actor's toolkit driver.
- Oka runner/composition/dependency tests: 11 passed; multi-directory watcher
  teardown: 1 passed; docs drift passed. The real Oka web session changed an
  external package method while preserving the custom resident document/runtime;
  hot restart created a fresh runtime (`output/evidence/oka-dev/`).
- Prebuilt Oka browser/server composition applied five document revisions with
  zero compiler invocations (`output/evidence/resident-session/`). Timings include
  transport and frame observations; they do not establish JS superiority.

Failures drove the final implementation: duplicate merged native slider nodes,
Flutter's transient disabled range proxy, semantics receivers beside rather than
inside the glass pane, a native background frame that had not completed, and Oka's
late stream-completion wait. Exact scoped targets now refuse ambiguity; focus waits
for readiness; pointer forwarding requires the same Flutter view; one forced frame
can present remote data in a background host. The frame policy is injectable.

`verifyEffect` separates delivery from effect, performs at most one dispatch and
handles already-satisfied state without dispatch. The delayed-effect fixture uses
real input followed by an intentionally delayed client completion to exercise an
unknown-delivery receipt; it is not a measured production transport outage. The
application counter proves exactly one effect in each tested lane.

The dev trial explicitly uses local web resources. Several earlier debug launches
failed to produce the page; the configured local-resource lane passed. Live latency
varied substantially under machine load. No broad performance claim follows from
those trials. A completed Flutter frame is also not compositor presentation: raw
frames were separately captured and inspected. New source is local/unpublished;
canonical acceptance, release/adoption, arbitrary overlays, large scenes, Wasm,
Ladybird and inline conversation embedding remain unqualified.

Final normal-bundle resident-session run (five title revisions, same resident world):
app-side data-to-completed-Flutter-frame times were 22.000, 13.401, 14.600,
15.700 and 17.101 ms; observed client round trips were 36, 21, 63, 63 and 64 ms.
There were zero compiler invocations during these updates. This tiny warm cohort
is not a p95 guarantee, a GPU presentation measurement, a geometry stress test or
an equal-workload JS comparison. The final normal delivery build took 22.928 s in
its Oka receipt; prior runs were slower. Preserve the distinction between delivery
build time, resident app work and the observing transport.

### Native capture/idle qualification limit

Final pixel inspection narrowed glyph corruption to a lane using toolkit offscreen
`scene.toImage` captures. A fresh native run without those captures produced clean
OS window pixels (`resident-native-capture-probe/os-before-toolkit.png`). This is
an observed lane difference, not an established Flutter engine root cause. A
consumer PID-scoped `MacosDriver.windowScreenshot` adapter is analyzer clean. Long
capture/idle probes later timed out in toolkit snapshot/scroll frame waits; those
failed probe receipts supersede any blanket claim of native background reliability.
Keep native interaction receipts separate from pixel evidence. The prior seven
native checks passed, but subsequent native reruns failed as recorded. A final
Xcode rebuild stalled and was stopped. Static button palette updates are locally
source-tested; final native rendering of that revision remains unqualified.

Final source contracts after replacing the button color tween: 9 tests passed
(`output/evidence/final-contracts.log`); native capture/scenario analysis clean.
The last native no-capture rerun passed selection, resident continuity and replay/
refusal, then timed out reading the baseline after slider focus. It did not dispatch
ArrowRight without that baseline. Current `resident-native/result.json` is a failed
receipt; do not present the earlier 7/7 as the latest result. The seven-step web
receipt and resident-session receipt remain passing. The native runner now skips
pixel capture during behavioral checks and bounds its own process teardown.

2026-10-13 focus/latency extension: Oka defaults to headless with explicit
--browser-visible; focused runner/composition/dependency tests 11 passed, docs drift
passed. Resident consumer removes Page.bringToFront; analysis clean. A headless
20-update geometry/title/palette cohort passed with no sampled frontmost transition;
app frames 19.601–53.500 ms (median 27.551), client 69.840–7841.059 ms (median324.770).
Existing-bundle readable-state startup was 40.142 s, not ms cold startup. Native
nonactivating AppKit probe recorded zero activation events and unchanged frontmost
PID. Both trials had loginwindow as baseline, so unlocked-desktop UX is unqualified.
First browser candidate captures were loading spinners despite readable state;
retain these as state-only receipts, never graphics parity or meaningful-first-frame.
The mechanics/research note is in scratch LATENCY_RESEARCH.md; no browser fork,
resident-DDC rewrite, native engine patch or cold-compile speedup is claimed.

Scene-ready browser candidate trial: normal headless Chrome155 produced a complete
graph capture after spatial semantics at30.922s. Installed headless-shell153 had
an earlier target/state but did not complete the subsequent frame wait; the owned
process was stopped and the receipt records closed socket. No shell graphics parity
or speed superiority is claimed. State-only spinner captures are retained separately.

## Canonical extraction

The repository example passes 10 focused Flutter tests. Its Oka release build receipt records 26.108 seconds. The supervised canonical run passed six real web interactions after correcting Chrome window-size syntax and transient AX readiness. The observed viewport was 1120×913. Earlier failed receipts remain retained; the native failed lane remains unresolved. See the example-owned output/validation directory and Oka delivery ledger for current status.

Fresh canonical scaffold: analysis clean and 10 tests passed. Installed skill routes to repository source. Latest web receipt is `output/validation/dogfood-ax-readiness-2026-10-13/result.json`; six effects observed, zero runtime exceptions, supervisor job succeeded. Graph/linked-dark pixels were inspected and the owned processes stopped. Resident update to completed Flutter frame: 31.100 ms, zero compiler invocations. This is one small warm update, not a startup latency guarantee. Native historical failures remain open.

## Multi-view qualification

Current contracts: 12 Flutter tests pass and analysis is clean. Real headless
`multi-view-optional-address-2026-10-13` records ten observed checks, no runtime
exceptions and supervisor success. The embedding host's action survives; addressed
updates and scoped camera input affect one world; removal leaves the other runtime
unchanged; remount creates a new world and restores its checkpoint. Both captured
scenes were visually inspected. The full-page six-interaction regression also
passes in `single-view-optional-address-2026-10-13`. The observer, worlds and browser
share machine resources, so these trials are not isolated performance cohorts.

Failures retained: the semantic group initially lacked text direction; the first
host-catalog test read an unawaited Promise; the first full-page state reader used
a required exported callback argument. The latest code corrects these causes;
negative address tests now check named refusal causes instead of accepting any
exception. Removed viewer instances reject later apply calls. Native multi-window,
large view counts and forced-crash recovery remain unqualified.

## Retained code-edit cohort

The example-owned dev consumer's final supervised trial passed method, compatible
signature and import edits through one retained Flutter/DDC session, with unchanged
runtime/document/camera/selection and zero runtime exceptions. Pixels were inspected
in the zero-error trial. One-shot code effects: 1,617.631 ms first edit, 222.180 ms
signature, 222.470 ms import. Flutter's acknowledgement and transport observations
are retained separately. These are small compatibility trials, not distributions
or cold-start/GPU-presentation claims. The earlier changed-state trial emitted
duplicate-definition errors and remains failed. Oka now composes one reload owner
and removes only its acknowledged path's fixed four-second delay.

## Resident engine startup evidence

The package-owned multi-view dogfood retains `startup-cohort.json` and final
captures. Its consistent-clock 2026-10-13 trial passes 14 observed checks with
zero runtime exceptions: two initial viewers plus five fresh alpha worlds,
checkpoint restoration and unchanged beta state. Five warm world-to-first-render
return times range 32.9–38.6 ms; addView-to-host observation ranges 71.1–82.6 ms.
Removal has a separate timing. Final pixels were inspected.

For repeated previews, the example's resident multi-view host is a measured way
to avoid starting another browser and engine for every viewer. Keep each viewer's
world and checkpoint isolated. This result qualifies the small graph workload,
not arbitrary scenes, memory plateau, p95 or millisecond cold builds. The engine's
public render call returning is distinct from GPU completion and compositor
presentation. Both initial viewers overlap resource loading and are not separate
cold samples. See the [dogfood commands](../../../../tool/visualization_dogfood/README.md)
for reproducing the cohort with an explicit new evidence directory.

2026-10-13 Canvas consumer: no flutter_scene or ecsly_flutter_scene in resolved
package graph; three tests pass, including selection at two zoom scales and
checkpoint isolation. Full consumer analysis passes. The Oka supervised
canvas-dogfood-ax-2026-10-13 trial passes six interactions, has no runtime
exceptions, and completes after teardown. Graph and linked-chart captures were
inspected. First paint returned at 190.3 ms from world creation; resident document
update to Flutter frame was 46.3 ms. Fresh browser attachment remained seconds.
These timings do not prove compositor presentation or a speed advantage over JS.
The preceding DOM readiness failure is retained as evidence of the observer fix.

The engine-free Canvas multi-view job canvas-multi-frame-2026-10-13 passes 14
effects with no runtime exceptions and inspected two-view pixels. Five fresh
worlds in one resident Flutter engine return their first paint at 33.6–38.1 ms;
first widget-frame completion is 45.6–53.3 ms. Host request-to-observation is
91–148 ms. Preserve these clock distinctions. Browser reuse is separately
qualified by canvas-retained-browser-pages-2026-10-13: three independent fresh
pages, unchanged owner world and process lease, page removal and final teardown.
Fresh page render remained roughly 0.9–1.1 s; engine reuse and resident document
updates are different workloads.

Native Canvas debug runtime: explicit VM discovery stays in the sandbox container,
with engine bootstrap separated from viewer mount. Flutter MCP harness VmClient
reads the registered state extension and applies the same versioned document
action; no expression evaluation is required. The supervised native container
trial passes initial paint and resident frame continuity at 51.2 ms. Owned OS
window captures show the changed title/graph and preserved foreground focus;
46.3 ms and 56.7 ms frame observations are recorded in later capture trials.
The background image is small/perspective-transformed; full-resolution window
geometry and native widget/input focus remain unqualified. Toolkit/native driver
source is reused, not copied into core ecsly.

Checkpoint lifecycle regression (2026-10-13): three controlled adapter tests
cover dispatched-old/queued-old/new-owner saves, late restore after detachment,
and recovery after storage failure. Per-key serialization prevents a dispatched
old save from settling after a newer save; queued stale calls refuse. Canonical
example now passes 16 tests and clean analysis. This is process-local proof,
not native storage durability, cross-tab coordination or an awaited remount
startup read. Cached initial reads can precede a pending older write.

The subsequent startup-read fix supersedes that cached-remount limitation for
`launchPreview`: a per-key `readSettled` barrier waits for prior operations, then
reloads preferences. `CheckpointBootstrap` initializes once per mount and creates
no world until the read succeeds. Delayed-save/latest-read and widget rebuild/
failure regressions pass; the canonical example now passes 19 tests with clean
analysis. Reads cover previously queued operations, not future writes; separate
processes/tabs and native durability remain outside this process-local contract.

Native Oka CLI cohort (2026-10-13): the package-owned native-dev-cohort driver
verifies method/signature/import reloads in the same world, restart into a new
world, a subsequent reload preserving that world, and compiler detach while the
app remains readable. Fresh extension registration must be observed after restart;
the compiler's completion line alone does not establish app readiness. The final
native-dev-restart-reload trial preserves foreground focus and verifies original
owner teardown. Source-to-observation times are one-run diagnostics, not cold
build, compositor or comparative speed guarantees. Native input and full-resolution
pixel quality remain separately unqualified.

The subsequent native-sck-appkit-capture trial supplies inspected full-resolution
pixels for one off-screen Canvas window: 800×632 points, 2× scale, 1600×1264 PNG.
Legacy capture is also full-size in that run. Earlier transformed captures remain
retained and unexplained; do not infer backend superiority or arbitrary-window
capture correctness. Focus and owned teardown pass. Native input stays unqualified.
