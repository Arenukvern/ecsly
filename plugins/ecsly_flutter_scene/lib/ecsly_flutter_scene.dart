/// 3D scene adapter for ecsly worlds on flutter_scene: declarative
/// per-component visual mappings, an incremental binder that keeps a
/// flutter_scene Scene in sync with world queries, and an orbit camera
/// rig. Pure core (mapping/binder/visual state) is renderer-free and
/// fully unit-testable; flutter_scene types only appear in the
/// integration shells ([FlutterSceneSink], [EcsSceneView], camera rig).
library;

export 'package:flutter_scene/scene.dart'
    show PerspectiveCamera, Scene, SceneView;

export 'src/ecs_scene_binder.dart';
export 'src/ecs_scene_view.dart';
export 'src/flutter_scene_sink.dart';
export 'src/scene_mapping.dart';
export 'src/visual_state.dart';
