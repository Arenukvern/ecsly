# ecs_camera_flutter DX_FAQ - Memory Palace

Developer notes for practical setup and safe integration.

## Quick setup



## First use

- Read  and  before integrating.
- Add dependency and keep calls close to package boundaries.

## Common checks

- Keep package-local constraints in sync with runtime behavior and tests.
- If this package has no importable library entrypoint, treat it as an executable/project package and wire through \ or host entry files.
- For packages with a library entrypoint, prefer stable exported APIs over internals.

## Notes

- Update all three docs (, , ) when behavior changes.
- Follow repo rules for interop and host thinness.
