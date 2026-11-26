// ignore_for_file: do_not_use_environment

/// Compiler family for benchmark reports.
///
/// AOT and JIT are both `vm`. Pass `--compiler=aot` or `--compiler=jit` to
/// tell them apart.
const String kEcslyCompilerKind = bool.fromEnvironment('dart.tool.dart2wasm')
    ? 'wasm'
    : bool.fromEnvironment('dart.tool.dart2js')
    ? 'js'
    : bool.fromEnvironment('dart.tool.ddc')
    ? 'ddc'
    : 'vm';
