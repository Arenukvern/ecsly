import 'dart:io';

/// Adds a read-only host identity diagnostic to an explicitly owned consumer.
Future<void> main(List<String> args) async {
  if (args.length != 2) throw ArgumentError('PROJECT MCP_FLUTTER_ROOT');
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  final window = File('$project/macos/Runner/MainFlutterWindow.swift');
  final fixture = File('$project/lib/semantic_write_fixture.dart');
  final source = File(
    '${args[1]}/mcp_toolkit/tool/native_window_identity_macos.swift',
  );
  final swift = window.readAsStringSync();
  final dart = fixture.readAsStringSync();
  if (swift.contains('installNativeWindowIdentity') ||
      !swift.contains(
        'RegisterGeneratedPlugins(registry: flutterViewController)',
      ) ||
      !dart.contains('registerExtension') ||
      dart.contains('ext.fixture.nativeWindowIdentity')) {
    throw StateError(
      'Expected an owned native semantic fixture without identity diagnostics',
    );
  }
  await window.writeAsString(
    swift.replaceFirst(
          'RegisterGeneratedPlugins(registry: flutterViewController)',
          'RegisterGeneratedPlugins(registry: flutterViewController)\n'
              '    installNativeWindowIdentity(window: self, controller: flutterViewController)',
        ) +
        '\n' +
        source.readAsStringSync(),
  );
  await fixture.writeAsString(
    dart.replaceFirst(
      '      registered = true;',
      '      registered = true;\n'
          "      registerExtension('ext.fixture.nativeWindowIdentity', (method, parameters) async {\n"
          "        final value = await const MethodChannel('fixture.nativeWindowIdentity').invokeMethod<Object?>('observe');\n"
          '        return ServiceExtensionResponse.result(jsonEncode(value));\n'
          '      });',
    ),
  );
}
