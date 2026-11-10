# ecs_spatial_core

## Package summary

- **Kind:** Plugin package
- **Package name:** 
- **Publish status: private (publish_to: none)**
- **Path:** 

Pure-Dart spatial/interaction primitives shared across ECS plugins (position lookup/mutation, AABB helpers).

## Package purpose

This package is documented here for local discovery and use in the ecsly workspace.

## Usage

If this package is a reusable library, add it with a workspace dependency:



If a public entrypoint exists, import it from the package library:

A command-line utility for Dart development.

Usage: dart <command|dart-file> [arguments]

Global options:
-v, --verbose               Show additional command output.
    --version               Print the Dart SDK version.
    --enable-analytics      Enable analytics.
    --disable-analytics     Disable analytics.
    --suppress-analytics    Disallow analytics for this `dart *` run without changing the analytics configuration.
-h, --help                  Print this usage information.

Available commands:

Global
  install     Install or upgrade a Dart CLI tool for global use.
  installed   List globally installed Dart CLI tools.
  uninstall   Remove a globally installed Dart CLI tool.

Project
  build       Build a Dart application including code assets.
  compile     Compile Dart to various formats.
  create      Create a new Dart project.
  pub         Work with packages.
  run         Run a Dart program from a file or a local or remote package.
  test        Run tests for a project.

Source code
  analyze     Analyze Dart code in a directory.
  doc         Generate API documentation for Dart projects.
  fix         Apply automated fixes to Dart source code.
  format      Idiomatically format Dart source code.

Tools
  devtools    Open DevTools (optionally connecting to an existing application).
  info        Show diagnostic information about the installed tooling.

Run "dart help <command>" for more information about a command.
See https://dart.dev/tools/dart-tool for detailed documentation.

## Notes

- Prefer package-level boundaries and explicit dependencies.
- Keep implementation details close to source code and tests.
- Update this README when public behavior changes.
