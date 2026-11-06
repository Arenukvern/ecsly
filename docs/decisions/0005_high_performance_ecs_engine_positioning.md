# ADR 0005: ecsly is a high-performance Dart ECS engine; public docs claim exactly what the artifacts prove

- Status: Accepted
- Date: 2026-11-07
- North Star impact: `amends` (moves the repo center from "experimental
  package family aspiring to a game-engine stack" to "high-performance ECS
  engine for Dart apps and games")

## Context

Until this decision, every public entry point described ecsly by what it is
not. The repo README tagline read "Experimental ECS packages"; the pub.dev
front page opened with a "super-experimental prerelease" warning banner; the
docs landing page called its own claim "intentionally modest"; the North Star
framed the repo as "without pretending that future engine work already
exists"; and the README carried a "Non-claims" list. The Design FAQ even
contained a question justifying why public copy says "experimental".

This posture measured ecsly against a full game engine — a category it was
never in — and apologized for the gap. Meanwhile the committed evidence
shows a runtime that is strong in the category it actually occupies. The
2026-11-07 scorecard (clean tree, `b6bfef612134`, Apple M1, Dart 3.13.4,
median of 5) records:

- 81.2M ops/sec raw chunk query iteration; 62.4M ops/sec in-place typed-column
  mutation; 59.2M ops/sec render-packet-style extraction at 30k entities.
- 20k-entity game-frame update+extract+flush at 657 µs p50 / 769 µs p95.
- Flat query throughput from 1k to 100k entities (63.1M → 65.1M ops/sec).
- ~16 KiB median RSS growth across repeated 15k-entity frame updates —
  near-zero allocation in steady state.

The docs also undersold this evidence: the README benchmark table quoted a
superseded baseline (53.8M ops/sec raw chunk, 893 µs p95) that was ~40% worse
than the committed artifact, and the pub.dev front page advertised version
`0.0.1-dev.9` while the package shipped `0.1.0-dev.13`. Stale numbers and
version drift amplified the immaturity signal that the apologetic copy was
already sending.

Underclaiming measured capability is as inaccurate as overclaiming unmeasured
capability. The repo's own proof rule — claims tied to code, tests, examples,
releases, or benchmark artifacts — applies in both directions.

## Decision

### 1. Identity

ecsly is a **high-performance Entity Component System for Dart**. Its purpose
is to bring data-oriented simulation performance to apps and games on every
runtime Dart reaches: Flutter, web, Jaspr, CLI, and server.

ecsly is not an aspiring game engine, and public copy stops contrasting it
with one. Engine subsystems — rendering, input, physics, audio — belong to
host layers (`ecsly_flutter`, Jaspr, a game's own engine code) or to future
plugins. ecsly owns simulation state, schedules, and hot loops. This is a
scope statement, not a deficiency list.

### 2. Claim rule

Every public capability claim must be backed by committed code, tests,
examples, releases, or benchmark artifacts — and every measured strength that
is decision-relevant for adopters should be claimed, with its evidence
linked. Performance claims cite the committed scorecard
(`core_packages/ecsly/benchmark/results/latest.md`) with machine, date, and
commit, plus the one-command reproduction path. Comparative superlatives
("fastest Dart ECS") require comparative evidence and are not used until then.

### 3. Voice rules for user-facing docs

Codified in `docs/VOICE.mdx`; summary:

- Lead with capability and numbers; status comes after the pitch, once.
- Exactly one factual status sentence per surface: prerelease channel, pin
  versions, changelog link. No warning banners, no emoji alarms.
- Affirmative scope. No "Non-claims", no "is and is not" lists, no maturity
  meta-commentary ("intentionally modest", "honest status", "without
  pretending").
- Future work is a Roadmap section, stated as direction, not as a disclaimer.
- Honesty is preserved by evidence discipline, not by hedging adjectives:
  measurements state their environment; prerelease status states its semver
  policy; boundaries state ownership.

### 4. North Star amendment

`docs/NORTH_STAR.mdx` moves its center to the high-performance ECS engine
identity. The "practical Dart game-engine stack over time" aspiration is
replaced by: the simulation layer that Dart apps and games build on, with
engine subsystems owned by hosts and plugins.

### 5. Evidence freshness

- Benchmark artifacts are regenerated on a clean `main` and committed with
  machine, SDK, date, and commit recorded in the report.
- README benchmark tables are generated from the artifact by
  `tool/docs/sync_readme_benchmarks.dart` between markers; `just check`
  fails when a table drifts from the artifact or `docs.json` drifts from the
  core pubspec version.
- Install snippets prefer `dart pub add <package>` over hand-written version
  ranges to eliminate the version-drift class entirely.

## Consequences

- All identity surfaces (root README, package READMEs, docs site landing,
  pubspec descriptions, docs.json) were rewritten to the new voice in the
  same change series.
- "Experimental" is removed from public copy; the prerelease (`0.1.x-dev`)
  channel remains and is stated factually — the version policy describes API
  stability commitments, not runtime quality.
- The stale `0.0.1-dev.x` pins that broke workspace resolution and the
  2026-10-27 pub.dev publishes were fixed alongside this repositioning;
  version references in docs are single-sourced or checked.
- Future docs PRs are reviewed against `docs/VOICE.mdx`. A claim without an
  artifact is rejected; a measured strength missing from the docs is treated
  as a docs bug.
- If ecsly later grows engine subsystems as plugins, they arrive as owned
  surfaces with their own evidence; the identity does not need to pre-apologize
  for their absence today.
