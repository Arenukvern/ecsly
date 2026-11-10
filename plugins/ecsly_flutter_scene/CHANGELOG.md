# Changelog

## [0.2.0](https://github.com/Arenukvern/ecsly/compare/ecsly_flutter_scene-v0.1.0...ecsly_flutter_scene-v0.2.0) (2026-11-10)


### Features

* **ecsly_flutter_scene:** environment tier hook, in-place actor updates, pan ([d923ed9](https://github.com/Arenukvern/ecsly/commit/d923ed9a2ed00530c8f5fed208aee73745630974))
* **ecsly_flutter_scene:** onTapRay — world-ray tap hook for consumer geometry picking ([19cf62c](https://github.com/Arenukvern/ecsly/commit/19cf62c3994f79d12326942b84bae0be37651f4d))
* **ecsly_flutter_scene:** per-tick environment hook (atmosphere without rebuilds) ([368ce5f](https://github.com/Arenukvern/ecsly/commit/368ce5fa6704d1323f1abc5e63214e7b05ad8635))
* **scene:** grab-the-world orbit signs + declarative cameraFocusTick close-up hook ([e79e032](https://github.com/Arenukvern/ecsly/commit/e79e032c1bb936efad42cf063f13355c761bdc86))
* **scene:** onHoverRay + onDragRay/claimDragForPaint for under-pointer editing ([ea16184](https://github.com/Arenukvern/ecsly/commit/ea16184e04036c57a3f162621d71f80a4a9ece76))


### Bug Fixes

* **input,camera-control,scene:** explicit schedule ordering + orbit gesture set + bridge hardening ([fcf6e30](https://github.com/Arenukvern/ecsly/commit/fcf6e30ad964b52ade401035e7b8517caccb21be))
* **scene:** left-handed pick basis matching flutter_scene lookAt + map-camera gestures ([353897e](https://github.com/Arenukvern/ecsly/commit/353897e2d0e5e87a2cb5b7b80de3e0c6b6812d9f))

## [0.1.0](https://github.com/Arenukvern/ecsly/releases/tag/ecsly_flutter_scene-v0.1.0) (2026-11-07)

Initial stable release: declarative per-component visual mappings, the incremental scene binder, and the orbit camera rig.
