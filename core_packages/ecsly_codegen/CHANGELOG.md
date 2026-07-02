# Changelog

## [0.1.0-dev.2](https://github.com/Arenukvern/ecsly/compare/ecsly_codegen-v0.1.0-dev.1...ecsly_codegen-v0.1.0-dev.2) (2026-07-02)


### Documentation

* clarify ecsly resource boundaries and release automation ([371dfec](https://github.com/Arenukvern/ecsly/commit/371dfec85e3dc8ff59fca0ca2b6edde4de2b1d8f))
* mark companion packages published ([ff4192a](https://github.com/Arenukvern/ecsly/commit/ff4192a6c6f69e247b5053dd4bdba5c039228b6e))

## 0.1.0-dev.1

- Align prerelease channel with `ecsly` `0.0.1-dev.x`; document compatibility (`ecsly >=0.0.1-dev.9`).
- Replace meta LICENSE with SPDX MIT text; add `license: MIT` and `issue_tracker` to pubspec.
- Expand README and DX_FAQ with `registerExtension`, version pins, limitations, and troubleshooting.
- Extend example with full `World` registration path.
- Add annotation validation (extends `Component`, valid `facade`, positive `stride`).
- Add golden output test and validation unit tests.
- Add package-local `AGENTS.md` and cross-links from `ecsly` README.

## 0.1.0

- Hard-cut the package rename to `ecsly_codegen`.
- Renamed the public library entrypoint to `package:ecsly_codegen/ecsly_codegen.dart`.
- Added package-local release metadata, changelog, license, example, and focused generator tests.
