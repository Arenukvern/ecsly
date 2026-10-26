import 'dart:convert';
import 'dart:io';

/// Editable owners are explicit inputs; Oka's experimental dev tool remains there.
void main(List<String> args) {
  if (args.length != 6 ||
      args[0] != '--oka-root' ||
      args[2] != '--automation-root' ||
      args[4] != '--toolkit-root') {
    throw ArgumentError(
      'configure.dart --oka-root PATH --automation-root PATH --toolkit-root PATH',
    );
  }
  final oka = Directory(args[1]).resolveSymbolicLinksSync();
  final automation = Directory(args[3]).resolveSymbolicLinksSync();
  final toolkit = Directory(args[5]).resolveSymbolicLinksSync();
  final paths = {
    for (final name in [
      'oka_supervisor',
      'oka_update',
      'oka_core',
      'oka_web',
      'resource_composition',
    ])
      name: '$oka/packages/$name',
    for (final name in [
      'universal_browser_cdp',
      'universal_automation_interface',
    ])
      name: '$automation/pkgs/$name',
    'flutter_mcp_harness': '$toolkit/packages/harness',
    'flutter_mcp_toolkit_core': '$toolkit/packages/core',
  };
  for (final path in paths.values) {
    if (!File('$path/pubspec.yaml').existsSync())
      throw StateError('Missing package $path');
  }
  final entry = File('$oka/packages/oka_dart_kernel/tool/oka_run_dev.dart');
  if (!entry.existsSync()) throw StateError('Missing Oka dev entrypoint');
  File('pubspec_overrides.yaml').writeAsStringSync(
    'dependency_overrides:\n' +
        paths.entries
            .map((e) => '  ${e.key}:\n    path: ${jsonEncode(e.value)}\n')
            .join(),
  );
  File('lib/oka_dev_binding.dart').writeAsStringSync(
    "// Generated explicit editable owner binding; never commit machine paths.\nexport '${entry.uri}';\n",
  );
}
