import 'dart:io';

/// Keep the production example's sink unchanged; qualify typed material choices.
void installMaterialFixture(String consumer) {
  final file = File('$consumer/lib/retained_scene_sink.dart');
  var source = file.readAsStringSync();
  void replace(String before, String after) {
    if (before.allMatches(source).length != 1)
      throw StateError('material fixture source drift');
    source = source.replaceFirst(before, after);
  }

  replace('<String, UnlitMaterial>{}', '<String, Material>{}');
  replace(
    'final material = UnlitMaterial()..baseColorFactor = _color(visual.argb);',
    '''const mode = String.fromEnvironment('VIEWER_MATERIAL_MODE', defaultValue:'unlit');
    final Material material;
    if (mode != 'unlit' && visual.shape == SceneShape.sphere) {
      final physical = PhysicallyBasedMaterial()
        ..baseColorFactor = _color(visual.argb)
        ..metallicFactor = 0.1
        ..roughnessFactor = 0.65;
      if (mode == 'clearcoat') {
        physical..clearcoat = 0.7..clearcoatRoughness = 0.25;
      } else if (mode != 'pbr') {
        throw StateError('unknown material fixture mode');
      }
      material = physical;
    } else {
      material = UnlitMaterial()..baseColorFactor = _color(visual.argb);
    }''',
  );
  replace(
    '_materials[key]!.baseColorFactor = _color(visual.argb);',
    '''final material = _materials[key]!;
    if (material is UnlitMaterial) {
      material.baseColorFactor = _color(visual.argb);
    } else if (material is PhysicallyBasedMaterial) {
      material.baseColorFactor = _color(visual.argb);
    }''',
  );
  file.writeAsStringSync(source);
  final viewer = File('$consumer/lib/resident_viewer.dart');
  viewer.writeAsStringSync(
    viewer.readAsStringSync().replaceFirst(
      "'enginePreparation': preparationDiagnostics.snapshot(),",
      "'enginePreparation': preparationDiagnostics.snapshot(),\n    'materialMode': const String.fromEnvironment('VIEWER_MATERIAL_MODE', defaultValue:'unlit'),",
    ),
  );
}
