set dotenv-load := false

default:
    @just --list

# Show the Steward-generated agent map.
map:
    steward map

# Validate the local Steward contract without running package gates.
doctor:
    steward doctor --json

# List typed Steward actions and their safety/effect contracts.
actions:
    steward actions list --json

# Run the quick Steward smoke probe.
probe:
    steward probe --profile quick --json

# Fetch workspace dependencies.
get:
    dart pub get

# Analyze the core Dart ECS package.
analyze-core:
    cd core_packages/ecsly && dart analyze

# Run core ECS tests.
test-core:
    cd core_packages/ecsly && dart test

# Run app-layer tests.
test-app:
    cd core_packages/ecsly_app && dart test

# Run codegen package tests.
test-codegen:
    cd core_packages/ecsly_codegen && dart test

# Run Flutter bridge tests.
test-flutter:
    cd core_packages/ecsly_flutter && flutter test

# Run all package tests that do not publish.
test: test-core test-app test-codegen test-flutter

# Check docs.page configuration and pages.
docs-check:
    npx --yes @docs.page/cli check

# Run core publish dry-run.
publish-core-dry-run:
    cd core_packages/ecsly && dart pub publish --dry-run

# Run publish dry-run preflight for all publishable packages.
publish-dry-run:
    dart tool/release/pub_package.dart --all --skip-existing

# Sync pubspec versions from the Release Please manifest.
sync-release-pubspecs:
    dart tool/release/sync_release_pubspec_versions.dart

# Check pubspec versions against the Release Please manifest.
check-release-pubspecs:
    dart tool/release/sync_release_pubspec_versions.dart --check

# Run publish dry-run preflight for one release tag.
publish-tag-dry-run tag:
    dart tool/release/pub_package.dart --tag "{{tag}}" --skip-existing

# Publish one release tag. Intended for CI or supervised maintainer bootstrap.
publish-tag-execute tag:
    dart tool/release/pub_package.dart --tag "{{tag}}" --execute --skip-existing

# Run the default local gate used before PRs.
check: probe get analyze-core test docs-check

# Run the release-oriented local gate.
release-check: check check-release-pubspecs publish-dry-run
