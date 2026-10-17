import 'dart:io';

/// Opt-in experiment: pending bundle entries compile at their first lookup.
/// Live shader identities stay intact; reload refreshes pending source entries.
void patchLazyShaders(Directory engine) {
  final file = File('${engine.path}/lib/src/gpu/web/shader_library.dart');
  var text = file.readAsStringSync();
  void replace(String before, String after) {
    if (before.allMatches(text).length != 1)
      throw StateError('lazy shader source drift: $before');
    text = text.replaceFirst(before, after);
  }

  replace(
    'ShaderLibrary._(this._shaders);',
    '''ShaderLibrary._(this._shaders, {Map<String, fb.BackendShader>? pending, String? assetName})
      : _pending = pending ?? {}, _assetName = assetName;
  static const _lazy = bool.fromEnvironment('FLUTTER_SCENE_LAZY_WEB_SHADERS');
  final Map<String, fb.BackendShader> _pending;
  final String? _assetName;
  static final Map<String, List<WeakReference<ShaderLibrary>>> _librariesByAsset = {};
  void _refreshPending(Map<String, fb.BackendShader> entries) {
    _pending..clear()..addEntries(entries.entries.where((e) => !_shaders.containsKey(e.key)));
  }''',
  );
  replace(
    'Shader? operator [](String name) => _shaders[name];',
    '''Shader? operator [](String name) {
    final existing = _shaders[name];
    if (existing != null) return existing;
    final backend = _pending[name];
    if (backend == null) return null;
    final clock = Stopwatch()..start();
    final shader = _buildFromBackend(backend);
    _shaders[name] = shader;
    _pending.remove(name);
    if (_assetName != null) {
      _shadersByAsset.putIfAbsent(_assetName!, () => []).add((name:name, shader:WeakReference(shader)));
    }
    preparationDiagnostics.record({'phase':'deferredShaderCompile', 'asset':_assetName, 'shader':name, 'elapsedUs':clock.elapsedMicroseconds});
    return shader;
  }''',
  );
  replace(
    'final shaders = <String, Shader>{};',
    'final shaders = <String, Shader>{};\n    final pending = <String, fb.BackendShader>{};',
  );
  replace(
    "'entries':shaders.length",
    "'entries':shaders.length + pending.length",
  );
  replace(
    'final shader = _buildFromBackend(backend);\n      shaders[name] = shader;',
    '''if (_lazy) { pending[name] = backend; continue; }
      final shader = _buildFromBackend(backend);
      shaders[name] = shader;''',
  );
  replace(
    'return ShaderLibrary._(shaders);',
    '''final library = ShaderLibrary._(shaders, pending:pending, assetName:assetName);
    if (_lazy && assetName != null) {
      _librariesByAsset.putIfAbsent(assetName, () => []).add(WeakReference(library));
    }
    preparationDiagnostics.record({'phase':'bundlePolicy', 'asset':assetName, 'lazy':_lazy, 'compiled':shaders.length, 'pending':pending.length});
    return library;''',
  );
  final start = text.indexOf(
    'Future<void> reinitializeShaderLibraryAsync(String assetKey) async {',
  );
  final end = text.indexOf('/// Recompiles [library]', start);
  if (start < 0 || end < 0) throw StateError('asset reload source drift');
  text = text.replaceRange(
    start,
    end,
    '''Future<void> reinitializeShaderLibraryAsync(String assetKey) async {
  final tracked = ShaderLibrary._shadersByAsset[assetKey] ?? [];
  tracked.removeWhere((e) => e.shader.target == null);
  final refs = ShaderLibrary._librariesByAsset[assetKey] ?? [];
  refs.removeWhere((e) => e.target == null);
  if (tracked.isEmpty && refs.isEmpty) return;
  rootBundle.evict(assetKey);
  final data = await rootBundle.load(assetKey);
  final bundle = fb.ShaderBundle(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  final entries = <String, fb.BackendShader>{};
  for (final e in bundle.shaders ?? const <fb.Shader>[]) {
    if (e.name != null && e.openglEs != null) entries[e.name!] = e.openglEs!;
  }
  for (final ref in refs) { ref.target?._refreshPending(entries); }
  var count = 0;
  for (final record in tracked) {
    final shader = record.shader.target;
    final backend = entries[record.name];
    if (shader != null && backend != null) {
      ShaderLibrary._populateFromBackend(shader, backend); count++;
    }
  }
  preparationDiagnostics.record({'phase':'assetShaderReload', 'asset':assetKey, 'recompiled':count, 'pendingLibraries':refs.length});
}

''',
  );
  replace(
    'final existing = library._shaders[name];',
    '''final existing = library._shaders[name];
      if (ShaderLibrary._lazy && existing == null) {
        library._pending[name] = backend; continue;
      }''',
  );
  // Clear stale pending entries before populating the replacement byte bundle.
  replace(
    '''    for (final entry in bundle.shaders ?? const <fb.Shader>[]) {
      final name = entry.name;
      final backend = entry.openglEs;
      if (name == null || backend == null) continue;
      final existing = library._shaders[name];''',
    '''    if (ShaderLibrary._lazy) library._pending.clear();
    for (final entry in bundle.shaders ?? const <fb.Shader>[]) {
      final name = entry.name;
      final backend = entry.openglEs;
      if (name == null || backend == null) continue;
      final existing = library._shaders[name];''',
  );
  file.writeAsStringSync(text);
}
