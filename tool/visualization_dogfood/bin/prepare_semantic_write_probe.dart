import 'dart:io';

/// Adds the package-owned fixture only to an explicitly owned consumer copy.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('PROJECT MCP_FLUTTER_ROOT');
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  final main = File('$project/lib/main.dart');
  final target = File('$project/lib/semantic_write_fixture.dart');
  final source = File(
    '${args[1]}/mcp_toolkit/tool/semantic_write_fixture.dart',
  );
  final text = main.readAsStringSync();
  if (target.existsSync() ||
      !source.existsSync() ||
      !text.contains('await launchPreview();') ||
      !text.contains('MCPToolkitBinding.instance')) {
    throw StateError('Expected an unmodified owned toolkit consumer');
  }
  await source.copy(target.path);
  await main.writeAsString(
    "import 'semantic_write_fixture.dart';\n"
            "import 'preview_canvas.dart';\n" +
        text.replaceFirst(
          'await launchPreview();',
          'await launchPreview(viewportBuilder: (world, controller) => '
              'SemanticWriteFixture(child: canvasViewport(world, controller)));',
        ),
  );
}
