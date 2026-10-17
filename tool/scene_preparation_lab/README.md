# Scene preparation laboratory

This SDK-only preparation tool creates a fresh, owned consumer and source copy of
an explicitly supplied flutter_scene package. It profiles the existing preparation
policy; it does not change production engine policy or modify the package cache.
The copied engine retains its license. Generated consumers and engine snapshots
live under ignored output; the transformations remain source-controlled here.

```sh
dart prepare.dart NEW_OUTPUT ECSLY_ROOT FLUTTER_SCENE_SOURCE FLUTTER_EXECUTABLE
```

Then use ecsly's visualization_dogfood build and supervisor commands against
`NEW_OUTPUT/consumer`. The viewer state includes `enginePreparation`. Async phase
durations overlap; synchronous bundle decode/compile timing excludes asset
transport but can include GPU-driver waits.
These diagnostic data do not prove feature-scoped rendering or performance gains.
Source anchors refuse when the supplied engine has drifted. Keep failed trials.

The 2026-10-13 eager-policy profile passes the supervised six-interaction dogfood
with zero runtime exceptions and inspected initial pixels. It compiles 75 base
entries in 315.3 ms and 17 physical-material entries in 616.2 ms, even though the
graph uses unlit materials. The inclusive material preparation phase is 1,212.3 ms;
the first renderer returns 1,490.5 ms after world creation. These are one-run
diagnostics, not a distribution or a proven policy improvement. The next experiment
must defer unused compilation while preserving shader lookup, reload and error
semantics, and verify all three recipes before considering adoption.

Add `lazy` to preparation to include the opt-in deferred-lookup prototype and its
backend probe. Build through visualization_dogfood with
`--dart-define=FLUTTER_SCENE_LAZY_WEB_SHADERS=true`, then add `shader-probe` to the
supervisor command's scenario argument. The build tool forwards explicit extra
Flutter arguments and retains them in the build receipt. The compile-time switch
defaults to eager behavior; installed/canonical engine dependencies are unchanged.

Lazy lookup retains compiled shader objects, refreshes pending bundle entries on
asset/byte reload, and compiles pending entries at first use. Error timing differs:
unused invalid source can fail at first use rather than during bundle loading.
The backend probe checks caching, missing names, same-source reload identity and
recovery after a deliberately invalid pending vertex shader. Same-source identity
checks do not prove changed shader pixels or pipeline-cache eviction. Physical
bundle validation still compiles PhysicalOpaque; feature-scoped loading remains
a separate experiment. This prototype is not an adopted production policy.

The `structural` preparation mode adds backend entry-presence checks and propagates
initialization rejection. On web, checking a pending entry does not compile it;
native retains its existing lookup behavior. The web trial compiles five initial
shaders and no physical-material shaders. Its presence predicate and the earlier
seven lookup/reload/error predicates pass. Native behavior is not live-qualified.

The `missing-physical` supervisor scenario changes only the served bundle's
PhysicalOpaque entry name. The original initializer incorrectly reported completion
after that preparation error; the fixed copy exposes a named failure and never
enters the renderer. The checker uses the shared accessibility snapshot for the
visible error, because Flutter text need not have a DOM aria-label. Failed trials
remain preserved. A passing negative trial is an error-handling claim, not a visual
interaction claim.

For a diagnostic build, `--optimization-level=1` is supported by the tested Flutter
toolchain. One corrected build took 30.7 seconds; this is a different compiler
configuration from the earlier 418.7-second O4 build and does not establish a causal
speed ratio. Startup timing remains uncontrolled. Correction: the preceding lazy
lookup trace compiled six initial shaders, not seven; structural presence removes
the physical probe compile, leaving five.

For the material matrix, add `materials` after `structural` during preparation.
The generated consumer's `VIEWER_MATERIAL_MODE` build flag accepts `unlit`, `pbr`
or `clearcoat`. Links remain unlit; spheres use the selected material. Color updates
retain the same material objects through typed setters. The canonical sink is not
changed. Each build receipt records the material choice and optimization level.

The lazy web trials for basic PBR and clearcoat pass the six interactions plus the
shader backend probe, with no runtime exceptions and inspected shaded spheres.
Basic PBR compiles seven initial shaders, including StandardCubeFragment and
StandardNoShadowCubeFragment. Clearcoat compiles nine, including four physical
variants created together. This qualifies these material choices on the tested web
backend, not textures, transmission, native rendering or changed-shader pixels.

The eager basic-PBR compatibility run also passes the six visual interactions;
its initial shader count is 92. The same build passes the missing-entry negative
contract with a visible failure and no renderer entry. All three material builds
share the same consumer source digest; flags differ. Build durations vary strongly
on the shared machine, so this is a work-count and compatibility comparison.

`summarize_matrix.dart NEW_JSON BUILD_RECEIPT TRIAL_DIR ...` pairs explicitly
supplied immutable build receipts and trial directories. It checks successful
build/runtime results and agreement of material/preparation flags, then writes
shader counts, checks, timing, source digests and capture paths. It refuses an
existing summary. Receipt linkage is operator-supplied: it does not fingerprint
the served bundle or full SDK/dependency closure and is not an acceptance oracle.
