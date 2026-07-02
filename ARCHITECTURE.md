# ecsly Public Architecture

This repository is the public canonical home for publishable `ecsly` packages
after they are explicitly migrated for public use.

## Current Ownership

| Path | Package | Ownership |
| --- | --- | --- |
| `core_packages/ecsly/` | `ecsly` | Canonical public source for the core ECS runtime |
| `core_packages/ecsly_app/` | `ecsly_app` | Canonical public source for app actions, drafts, invalidation, and cold lookup |
| `core_packages/ecsly_codegen/` | `ecsly_codegen` | Canonical public source for typed-column annotations and build_runner factories |
| `core_packages/ecsly_flutter/` | `ecsly_flutter` | Canonical public source for Flutter scope, controller, selectors, actions, and loops |

Packages, experiments, tools, docs, and validation tracks outside this repository
are not public contracts unless they are explicitly present here.

## Repository Boundary

Internal consumers may continue to depend on migrated public package identities
while non-migrated work remains outside this repository.

Consumers should depend on public package identities (`ecsly`,
`ecsly_app`, `ecsly_codegen`, `ecsly_flutter`) and may use local path overrides
to this repo while migration is in progress.

## Package Shape

The public repo keeps the `core_packages/...` layout so additional battle-tested
packages can graduate under the same shape later. Package directory names do not
have to match historical internal directories; the core package keeps package
name `ecsly` in public source under `core_packages/ecsly`.
