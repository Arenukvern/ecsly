# Resident visualization workflow

Scaffold with `dart run scripts/scaffold.dart DEST --ecsly-root PATH --flutter-bin EXEC --renderer canvas` for an engine-free Flutter painting consumer. Choose `--renderer scene` for the optional 3D adapter.
Options are `--ecsly-root`, `--flutter-bin`, `--platforms` and `--renderer`. Choose an explicit
owner/lifetime for DEST. The scaffold refuses an existing destination and reads the
canonical repository example; it does not carry another bundled source template.
Run `flutter analyze --no-pub` and `flutter test --no-pub` in the generated consumer.

## Author and deliver

Data updates use `VisualizationDocument` → `ResidentViewer.apply` in one world.
Require request ID and expected revision; malformed, stale and conflicting requests
refuse. The browser catalog delegates to this facade. Native toolkit integration is
optional through `PreviewApp.onViewerReady`; the canonical example has no toolkit
package dependency. Arbitrary widget/renderer edits use an owning Oka/Flutter dev
session. Oka WebBuildTarget delegates release compilation to Flutter; resident data
updates require no compiler invocation.

## Canonical supervised web qualification

Use [the dogfood tool](../../../../tool/visualization_dogfood/README.md). Configure
explicit Oka and automation roots, resolve dependencies, build the canonical example,
then run one declared supervisor job. Keep failed receipts and captures in an owned
output directory. Default browser policy is headless; showing a visible browser is
an explicit developer choice. Never bring a user's window forward for observation.

CDP targeting re-resolves exact scoped AX targets. Missing projection, transient
bounds and disabled controls wait within a deadline; ambiguity refuses before input.
Flutter proxy forwarding is accepted only inside the same Flutter view. Input is
never replayed after dispatch. `verifyEffect` records baseline, one dispatch and a
bounded fresh effect observation. Unknown delivery can coexist with an observed
effect. Application receipts correlate document updates; independent captures check
geometry, labels, palette and readability.

## Native and historical probes

The package-owned runner supports `native-toolkit` for instrumented Flutter widget
input with independent resident-state effects, OS foreground/activation observation,
window capture and owned teardown. Prepare an explicit fresh native consumer with
`prepare_toolkit_preview.dart PROJECT MCP_FLUTTER_ROOT BUNDLE_ID AUTOMATION_ROOT`,
resolve dependencies, and build macOS debug before the supervisor job. See the
[runner's exact commands and ownership](../../../../tool/visualization_dogfood/README.md).
Use its current toolkit driver and Universal Automation `verifyEffect`; never copy
an older selector adapter from the source archive.

The real button flow and stale-snapshot refusal are verified for that consumer.
Native OS AX window exposure and keyboard/widget focus remain separate open checks.
A successful focus request does not prove a subsequent keyboard state change;
readable state does not prove correct GPU pixels. Read [verification.md](verification.md)
before transferring results to a new host. Archived launch and candidate-browser
probes are diagnostics, not production native target APIs.

For multiple previews, add `multi-view` to the supervise command. Address every
state/apply operation with the host's logical `viewerId`; use the physical Flutter
view ID only for add/remove lifecycle. Keep checkpoint identity separate from
runtime identity. Do not assume global state remains valid after removing a view.

For measured code changes, use the separately configured
[resident code cohort](../../../../tool/visualization_dev_cohort/README.md). It
scaffolds an owned consumer and edits only its copied token package. Oka supplies
one acknowledged retained Flutter/DDC reload owner. Keep source-code latency
separate from resident data updates, and reject runtime errors even when getters
change. The current native retained-session trial covers method/signature/import edits,
restart and subsequent reload; broader edit/scale acceptance remains unqualified.

For a measured Wasm lane, use the existing build tool's --wasm argument and the
runner's `wasm` scenario. Confirm the compiled dart.tool.dart2wasm flag, actual
program/renderer resources and browser isolation; compilation also emits a JS
fallback. Oka's opt-in isolation policy is independent of renderer/cache choice.
The browser apply adapter normalizes safe integral JS numbers before the strict
resident transaction; fractional/nonfinite/unsafe values refuse. See the runner
README for current commands and receipts. Successful Wasm execution is not a
comparative speed or thread-count claim.
