# Releases in ~/xs/ecsly

Release automation is Release Please plus a Dart publish preflight. Automation config:
`release-please-config.json`, `.release-please-manifest.json`, publish workflow
`.github/workflows/pub-publish.yml`. Changelogs are **per-package** `CHANGELOG.md` files
under `core_packages/`.

## The local commands (justfile)

| Target | Does |
| --- | --- |
| `just sync-release-pubspecs` | Rewrites package pubspec versions from the Release Please manifest |
| `just check-release-pubspecs` | Same, `--check`: verifies without writing (part of `release-check`) |
| `just publish-dry-run` | Publish preflight for all publishable packages: `dart tool/release/pub_package.dart --all --skip-existing` |
| `just publish-tag-dry-run <tag>` | Preflight for one release tag |
| `just publish-tag-execute <tag>` | **Actually publishes** one tag — intended for CI or supervised maintainer bootstrap only |
| `just release-check` | The full release-oriented local gate: `check` + pubspec check + dry-run |

`pub_package.dart` flags: `--execute` performs the publish; without it the tool only
preflights. `--skip-existing` skips versions already on pub.dev. `--tag` scopes to one
release tag.

## Order of operations for a release

1. Land PRs normally (`just check` green).
2. Release Please opens/updates release PRs; merging them cuts component tags
   (uses the `RELEASE_PLEASE_TOKEN` repository secret — a token with `repo` + `workflow`
   scopes, so component tags can trigger the downstream pub.dev publish workflow; the
   default `GITHUB_TOKEN` cannot).
3. Tag-triggered workflow runs the publish path with artifact provenance **required** by
   the Steward contract (`steward.yaml` `release.artifact_provenance`).
4. Local verification before trusting any of it: `just release-check` must be green.

## Agent-assisted approval (DX_FAQ-sourced facts)

- The `agent-auto-approve` label on a trusted same-repo `codex/` or `release-please--`
  PR lets `.github/workflows/agent-auto-approve.yml` approve it after `Release
  validation` passes.
- Eligible authors: `Arenukvern` or `github-actions[bot]`.
- `AUTO_APPROVE_TOKEN` must belong to a **separate machine user** with write access —
  GitHub forbids authors approving their own PRs.

## Rules

- Never run `publish-tag-execute` casually; it is the real publish. Dry-run first, always.
- Don't hand-edit pubspec versions across packages — sync from the manifest, or
  `check-release-pubspecs` will fail the gate.
- Don't hand-edit generated Release Please PR branches; adjust
  `release-please-config.json` and let it regenerate.
- Changing release automation itself is what `just release-check` exists for — run it
  before proposing such changes, and expect Steward review (`review_handoff`
  `moe_required_for_architecture`).
