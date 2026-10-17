import 'dart:convert';
import 'dart:io';

/// Opt-in toolkit bootstrap for a fresh native visualization scaffold.
Future<void> main(List<String> args) async {
  if (args.length != 4)
    throw ArgumentError(
      'prepare_toolkit_preview PROJECT MCP_FLUTTER_ROOT BUNDLE_ID AUTOMATION_ROOT',
    );
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  final toolkit = Directory(args[1]).resolveSymbolicLinksSync();
  final bundleId = args[2];
  final automation = Directory(args[3]).resolveSymbolicLinksSync();
  final interface = '$automation/pkgs/universal_automation_interface';
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9-]*(\.[a-zA-Z0-9-]+)+$')
      .hasMatch(bundleId)) {
    throw ArgumentError('Invalid bundle ID');
  }
  if (Directory('$project/build/macos').existsSync() ||
      File('$project/toolkit-preview.json').existsSync()) {
    throw StateError('Expected fresh unbuilt scaffold');
  }
  final manifest = File('$project/pubspec.yaml');
  final config = File('$project/macos/Runner/Configs/AppInfo.xcconfig');
  final main = File('$project/lib/main.dart');
  final text = manifest.readAsStringSync();
  final configText = config.readAsStringSync();
  if (!text.contains('dependencies:\n') ||
      !text.contains('dependency_overrides:\n') ||
      !main.readAsStringSync().contains('launchPreview()') ||
      !File('$toolkit/mcp_toolkit/pubspec.yaml').existsSync() ||
      !File('$interface/pubspec.yaml').existsSync()) {
    throw StateError('Scaffold/toolkit differs; no writes applied');
  }
  await manifest.writeAsString(
    text
        .replaceFirst(
          'dependencies:\n',
          'dependencies:\n  mcp_toolkit:\n    path: ${jsonEncode('$toolkit/mcp_toolkit')}\n',
        )
        .replaceFirst(
          'dependency_overrides:\n',
          'dependency_overrides:\n  universal_automation_interface:\n    path: ${jsonEncode(interface)}\n  flutter_mcp_toolkit_core:\n    path: ${jsonEncode('$toolkit/packages/core')}\n',
        ),
  );
  await config.writeAsString(
    configText.replaceFirst(
      RegExp(r'^PRODUCT_BUNDLE_IDENTIFIER = .+$', multiLine: true),
      'PRODUCT_BUNDLE_IDENTIFIER = $bundleId',
    ),
  );
  await main.writeAsString(
    "import 'package:flutter/widgets.dart';\nimport 'package:mcp_toolkit/mcp_toolkit.dart';\nimport 'preview_app.dart';\nexport 'preview_app.dart' show PreviewApp;\nFuture<void> main() async {\n WidgetsFlutterBinding.ensureInitialized();\n MCPToolkitBinding.instance..initialize()..initializeFlutterToolkit();\n await launchPreview();\n}\n",
  );
  await File('$project/toolkit-preview.json').writeAsString(
    jsonEncode({
      'schema': 1,
      'toolkitRoot': toolkit,
      'bundleId': bundleId,
      'scope': 'Optional instrumented Flutter widget input; does not change native window policy or prove OS AX delivery',
    }),
  );
}
