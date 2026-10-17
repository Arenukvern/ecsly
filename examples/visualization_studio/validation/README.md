# Visualization validation ownership

This directory owns baseline/evaluation definitions and summaries for the canonical
studio example. Fresh run artifacts live under the example's ignored `output/validation/`.
Historical raw diagnostics live under ignored `validation/raw_history/`; they may
contain local debug endpoints and are not release artifacts. Keep failed receipts.

A baseline records compiler/preparation, browser-target, app, scene, completed-frame,
transport and captured-pixel observations separately. An accessibility/readable-state
clock is not a first meaningful GPU frame. Toolkit offscreen native capture and
extended background focus were failing historical lanes; do not rewrite them as green.

The package-owned dogfood runner is `../../../tool/visualization_dogfood` relative to this directory (see its README). The source recipes and tests are the reusable assets; SDK
caches, generated shaders and compiled app bundles can be regenerated and must not
be archived as durable source. Raw history's manifest records provenance and hashes.

Current runtime scenarios: full-page six-action qualification and one-engine
two-view mount/remove/remount qualification. Build trials preserve consumer source
hashes and timings without overwriting history. Skill eval prompt/rubric definitions
live in the canonical skill; raw answers and exposure metadata live in this example's
owned output. Keep static rules, paired guidance, contracts and real pixels as
separate proof types.
