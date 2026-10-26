---
name: ecsly-repo-dev
description: Develop, validate, and release packages in the ecsly repo at ~/xs/ecsly (Dart/Flutter ECS workspace with core_packages, plugins, just command hub, Steward governance). Use for ANY task inside ~/xs/ecsly — fixing or extending ecsly/ecsly_app/ecsly_codegen/ecsly_flutter/ecsly_serialization, running tests or benchmarks, preparing releases, updating docs, or navigating repo governance — even if the user just says "add this to ecsly" or "make the ecsly tests pass".
---

# Developing in ~/xs/ecsly

The repo documents itself well — `AGENTS.md` is the authoritative router, `docs/DX_FAQ.mdx`
covers maintainer workflows, `docs/NORTH_STAR.mdx` is the charter. **Read `AGENTS.md`
first in any nontrivial task.** This skill is the fast path: the loops, the boundaries,
and the non-obvious traps. The repo's installed Steward skills
(`repository-governance-lifecycle`, `skill-source-citations`, … under
`~/xs/ecsly/.agents/skills/`) govern governance mechanics — defer to them there.

## Orientation (30 seconds)

- Workspace: `core_packages/` (publishable: `ecsly`, `ecsly_app`, `ecsly_codegen`,
  `ecsly_flutter`) + `plugins/` (only `ecsly_serialization` is canonical — see below).
- Command hub: run `just` to list targets. `steward map` prints the agent-facing repo map.
- Pub workspace: run `dart pub get` at the **repo root** before analyzing/testing any
  package (package `.dart_tool/workspace_ref.json` files point at the root resolution).

## Canonical vs. merely present (the ownership trap)

`ARCHITECTURE.md` and `docs/NORTH_STAR.mdx` "What This Repo Owns" tables are the
authority. Today: the four core packages + `plugins/ecsly_serialization` are canonical.
`plugins/` also contains `ecsly_flutter_scene`, `ecsly_world_sync`,
`ecsly_world_sync_bridge`, `ecsly_async_parallel` — present, but **not** in the ownership
tables. Rules that follow:

- Never describe a present-but-uncanonicalized plugin as a shipped/public capability
  (the North Star's "absent packages are not contracts" rule).
- Changes there follow the same quality loops, but they are not public contracts and
  must not be promoted in root docs without an ownership-table change (which is a
  North Star `amends` — see the gate below).
- Public claims need proof: code, tests, examples, releases, or explicit blocked state.

## Validation loops

| Package kind | Loop |
| --- | --- |
| Pure Dart (`ecsly`, `ecsly_app`, `ecsly_codegen`) | `cd <pkg> && dart analyze && dart test`; publishable → `dart pub publish --dry-run` |
| Flutter (`ecsly_flutter`, `ecsly_serialization`) | `cd <pkg> && flutter test`; benchmarks: `just bench-serialization` |
| Whole repo pre-PR | `just check` (= `probe get analyze-core test docs-check`) |
| Release-oriented gate | `just release-check` (= `check` + `check-release-pubspecs` + `publish-dry-run`) |

Fast targeted runs: `just analyze-core`, `just test-core`, `just test-app`,
`just test-codegen`, `just test-flutter`, `just test-serialization`.

Steward checks (`just doctor`, `just probe`, `just actions`) are **stewardship proof,
not package proof** — passing them never substitutes for tests/publish dry-runs.

## The North Star gate (before durable structural changes)

Classify impact on `docs/NORTH_STAR.mdx` as one of `none`, `applies`, `clarifies`,
`sub_star`, `amends`, `conflicts`. `amends` and `conflicts` require ADR work
(`docs/decisions/`) **before** the change moves the repo center. Everything else records
the classification and proceeds.

Docs obligations that ride along with code changes:

- Core internals change → update `core_packages/ecsly/DESIGN_FAQ.md` and the architecture
  diagram when relevant.
- Public usage change → `core_packages/ecsly/DX_FAQ.md`.
- Package-specific behavior → the package's own README/DX FAQ.
- Repo-wide workflow answer → `docs/DX_FAQ.mdx`.
- **Plans are temporary.** Extract durable outcomes into ADRs/FAQs/code, then delete the
  stale plan file. Do not leave plan documents behind as pseudo-docs.

## Releases (outline — details in references/release.md)

Release Please automates versions/changelogs per package (per-package `CHANGELOG.md`,
`release-please-config.json`, `.release-please-manifest.json`); pubspecs are synced from
the manifest (`just sync-release-pubspecs` / `--check`); publish preflight runs
`dart tool/release/pub_package.dart` (`just publish-dry-run`), and actual tag publishing
is CI or explicitly supervised (`just publish-tag-execute <tag>`). Artifact provenance is
**required** by the Steward contract. Read [references/release.md](references/release.md)
before touching release automation, tokens, or the publish workflow.

## Repo hygiene

- The repo hosts agent skills in `.agents/skills/` (`installable_skills: true` since the
  2026-09-30 contract flip; see `docs/DX_FAQ.mdx` → "Agent skills"). Two kinds coexist:
  Steward-installed governance skills from `Arenukvern/skill_steward` (hash-locked in
  `skills-lock.json` — manage via `steward install`/`update`, never by hand) and
  repo-authored developer skills (this skill and `ecsly-plugin-pattern`), maintained as
  normal versioned files.
- No compatibility mirrors: never add bidirectional sync scripts or hidden mirror
  machinery between this repo and internal workspaces.
- Core `ecsly` stays pure Dart: no Flutter dependency, no assumptions about paths outside
  the repo, no host-app concerns pushed into the runtime.
- Agent/auto-approval mechanics (`agent-auto-approve` label, `AUTO_APPROVE_TOKEN`,
  `RELEASE_PLEASE_TOKEN`) are documented in `docs/DX_FAQ.mdx` — consult it rather than
  guessing at CI behavior.
