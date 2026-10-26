import 'dart:convert';
import 'dart:io';

/// Explicit editable dependency roots; no machine paths in the checked-in tool.
void main(List<String> args) {
  if (![4, 6].contains(args.length) ||
      args[0] != '--oka-root' ||
      args[2] != '--automation-root' ||
      (args.length == 6 && args[4] != '--flutter-harness-root')) {
    throw ArgumentError(
      'configure.dart --oka-root PATH --automation-root PATH [--flutter-harness-root PATH]',
    );
  }
  final oka = Directory(args[1]).resolveSymbolicLinksSync();
  final automation = Directory(args[3]).resolveSymbolicLinksSync();
  final paths = {
    for (final name in [
      'oka_update',
      'oka_dart_kernel',
      'oka_core',
      'oka_web',
      'oka_supervisor',
      'resource_composition',
    ])
      name: '$oka/packages/$name',
    for (final name in [
      'universal_browser_cdp',
      'universal_automation_interface',
    ])
      name: '$automation/pkgs/$name',
  };
  if (args.length == 6) {
    final harness = Directory(args[5]).resolveSymbolicLinksSync();
    paths['flutter_mcp_harness'] = '$harness/packages/harness';
  }
  for (final path in paths.values) {
    if (!File('$path/pubspec.yaml').existsSync())
      throw StateError('Missing package: $path');
  }
  final nativeDriver = '$automation/pkgs/universal_driver_macos';
  if (!File('$nativeDriver/pubspec.yaml').existsSync()) {
    throw StateError('Missing native capture package: $nativeDriver');
  }
  File('pubspec_overrides.yaml').writeAsStringSync(
    'dependency_overrides:\n' +
        paths.entries
            .map((e) => '  ${e.key}:\n    path: ${jsonEncode(e.value)}\n')
            .join(),
  );
  File('native_capture/pubspec_overrides.yaml').writeAsStringSync(
    'dependency_overrides:\n  universal_driver_macos:\n    path: ${jsonEncode(nativeDriver)}\n'
    '  universal_automation_interface:\n    path: ${jsonEncode(paths['universal_automation_interface'])}\n',
  );
}
