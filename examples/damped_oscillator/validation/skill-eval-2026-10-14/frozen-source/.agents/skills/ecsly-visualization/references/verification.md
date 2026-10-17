# Current verification boundaries — 2026-10-13

Use [workflow.md](workflow.md) and the package-owned
[dogfood runner](../../../../tool/visualization_dogfood/README.md). Receipts are
owned outputs of that runner. Keep failures; a successful dispatch is distinct
from an independently observed application effect.

| Capability | Current evidence | Boundary |
| --- | --- | --- |
| Engine-free Canvas consumer | Fresh scaffold analysis and nine tests; web/native runtime jobs | Resolved graph excludes both scene packages; optional 3D has separate evidence |
| Native background widget actions | `native-toolkit-effects-2026-10-13-b`: four observed button effects and real stale-snapshot refusal with unchanged state | Existing ToolkitDriver; no OS AX or keyboard-focus claim |
| Native focus and teardown | Same run: unchanged foreground PID, empty OS activation trace, owned app stopped and discovery removed | Off-screen window capture inspected; onscreen/compositor presentation not established |
| Single-view Flutter web | `web-effects-real-2026-10-13-b`: six observed effects, zero runtime errors, inspected linked-dark capture and teardown | Real headless Chrome, not an inline conversation fragment |
| Scoped multi-view web | `web-effects-multiview-2026-10-13-c`: fourteen isolation, targeting and remount checks | Small process-local cohort; arbitrary scale and cross-process storage remain open |
| Web foreground | Same two runs: no changes across 510/302 Universal Automation samples; maximum gaps 30.630/30.037 ms | Transitions shorter than sample gaps are not excluded |
| Owning native compiler session | `native-dev-restart-reload`: method, signature, import, restart and subsequent reload observed | One-run code latency; distinct from data updates and compositor presentation |
| Skill/runtime contracts | Canonical nineteen tests, fresh Canvas nine tests, harness seventy-one tests | Unit, implementation and live evidence remain separate from skill behavior |

Toolkit locators must be unique. The owning harness observes a fresh snapshot,
carries its revision with click/type/set-value, and surfaces refusal without
replaying the mutation. Consumers use Universal Automation `verifyEffect` with
independent state reads, rather than duplicating targeting or trusting delivery.
Run toolkit doctor against the exact discovered VM URI before driving the app.

Inspect actual captures for label/link alignment and readability. Toolkit offscreen
capture was associated with glyph corruption in earlier trials; current native
pixel observation uses the existing macOS window capture separately. That historic
causality remains unproven. Do not infer OS AX access from toolkit semantics.

The detailed prior record is [archived with the example](../../../../examples/visualization_studio/validation/skill_history/verification-before-native-toolkit-2026-10-13.md).
Its byte hash and original link base are recorded beside it. Historical counts,
engine versions, prototypes and failures are evidence epochs, not current commands.
The Oka-owned `docs/validation/visualization_delivery.md` ledger tracks broader
supervisor, compiler/cache and browser experiments in the explicitly configured Oka
checkout. No equal-workload JS/Dart/Rust speed or aesthetic superiority is established.
