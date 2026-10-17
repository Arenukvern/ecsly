# Current verification boundaries — 2026-10-13

Use [workflow.md](workflow.md) and the package-owned
[dogfood runner](../../../../tool/visualization_dogfood/README.md). Receipts are
owned outputs of that runner. Keep failures; a successful dispatch is distinct
from an independently observed application effect.

| Capability | Current evidence | Boundary |
| --- | --- | --- |
| Engine-free Canvas consumer | Fresh scaffold analysis and nine tests; web/native runtime jobs | Resolved graph excludes both scene packages; optional 3D has separate evidence |
| Native background widget actions | `native-toolkit-effects-2026-10-13-b`: four observed button effects and real stale-snapshot refusal with unchanged state | Existing ToolkitDriver; no OS AX or keyboard-focus claim |
| Native widget focus and key | `native-focus-key-2026-10-14-frame-a`: exact scoped Frequency slider, independent focused semantics, ArrowRight1.00→1.15Hz, subsequent button effects and stale refusal | Instrumented Flutter delivery, not OS keyboard synthesis; prior d focus refusal retained; regression proves elapsed16ms waits are not frames |
| Native text and explicit window capture | `native-window-identity-2026-10-14-d`: three catalog-gated text writes preserve decoy focus; native host ID corroborated by OS owner PID; wrong-owner capture refuses; empty error buffer and inspected graph PNG | Optional test fixture; controllers reset on viewport replacement; no shared SetValueAction or compositor-timing claim |
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
Read and retain the toolkit error buffer before declaring runtime success. State
effects alone can coexist with an ErrorWidget; native identity run c demonstrated
that false green and is disqualified as a visual result. Inspect actual pixels.

A text field can produce an additional invisible AppKit TUINSWindow at layer0.
Do not select the largest or titled window. Where an owned host supplies its
actual Flutter window ID, correlate it with OS PID/layer membership and capture
that address through the existing driver. Without identity, preserve ambiguity
refusal. Keep input, window-content pixels and compositor presentation distinct.

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
