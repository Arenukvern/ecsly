import 'dart:io';

/// Verify backend entries without forcing first-use compilation on web.
void patchShaderPresence(Directory engine) {
  void replace(String path, String before, String after) {
    final file = File('${engine.path}/$path');
    final source = file.readAsStringSync();
    if (before.allMatches(source).length != 1)
      throw StateError('presence source drift: $path');
    file.writeAsStringSync(source.replaceFirst(before, after));
  }

  replace(
    'lib/src/gpu/web/shader_library.dart',
    'final Map<String, Shader> _shaders;',
    'final Map<String, Shader> _shaders;\n  bool hasEntry(String name) => _shaders.containsKey(name) || _pending.containsKey(name);',
  );
  final shim = File('${engine.path}/lib/src/gpu/gpu.dart');
  shim.writeAsStringSync(
    '${shim.readAsStringSync()}\nexport \'shader_presence_native.dart\' if (dart.library.js_interop) \'shader_presence_web.dart\';\n',
  );
  File(
    '${engine.path}/lib/src/gpu/shader_presence_native.dart',
  ).writeAsStringSync('''
import 'impeller/_gpu.dart' as gpu;
bool shaderLibraryHasEntry(gpu.ShaderLibrary library, String name) => library[name] != null;
''');
  File('${engine.path}/lib/src/gpu/shader_presence_web.dart').writeAsStringSync(
    '''
import 'web/_gpu.dart' as gpu;
bool shaderLibraryHasEntry(gpu.ShaderLibrary library, String name) => library.hasEntry(name);
''',
  );
  replace(
    'lib/src/shaders.dart',
    'lib[baseShaderBundleProbeName] == null',
    '!gpu.shaderLibraryHasEntry(lib, baseShaderBundleProbeName)',
  );
  replace(
    'lib/src/material/physical_material_variant.dart',
    'library[physicalBundleProbeName] == null',
    '!gpu.shaderLibraryHasEntry(library, physicalBundleProbeName)',
  );
  // A rejected preparation must remain rejected to callers, rather than
  // reporting success and letting the renderer skip blank frames indefinitely.
  replace(
    'lib/src/scene.dart',
    '_initializeStaticResources = null;\n            });',
    "_initializeStaticResources = null;\n              Error.throwWithStackTrace(e ?? StateError('Unknown initialization error'), stacktrace);\n            });",
  );
}
