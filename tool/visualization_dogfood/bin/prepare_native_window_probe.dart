import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Adds a read-only diagnostic to a fresh disposable scaffold before build.
Future<void> main(List<String> args) async {
  if (args.length < 2 ||
      args.length > 3 ||
      (args.length == 3 &&
          ![
            '--join-all-applications',
            '--floating-preview',
          ].contains(args[2]))) {
    throw ArgumentError(
      'prepare_native_window_probe PROJECT BUNDLE_ID [--join-all-applications|--floating-preview]',
    );
  }
  final joinAllApplications = args.length == 3;
  final floatingPreview = args.length == 3 && args[2] == '--floating-preview';
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  final bundleId = args[1];
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9-]*(\.[a-zA-Z0-9-]+)+$')
      .hasMatch(bundleId)) {
    throw ArgumentError('Invalid bundle ID');
  }
  if (Directory('$project/build/macos').existsSync() ||
      File('$project/native-window-probe.json').existsSync()) {
    throw StateError('Expected fresh unbuilt scaffold');
  }
  final window = File('$project/macos/Runner/MainFlutterWindow.swift');
  final config = File('$project/macos/Runner/Configs/AppInfo.xcconfig');
  final main = File('$project/lib/main.dart');
  final baseline = window.readAsStringSync();
  const anchor =
      '    RegisterGeneratedPlugins(registry: flutterViewController)';
  if (!baseline.contains(anchor) ||
      !main.readAsStringSync().contains('launchPreview()')) {
    throw StateError('Scaffold template differs; no writes applied');
  }
  final fixtureRoot = Directory.fromUri(
    Platform.script.resolve('../native_capture/fixtures/'),
  );
  final swift = File('${fixtureRoot.path}/appkit_window_probe.swift.template')
      .readAsStringSync();
  final dart = File('${fixtureRoot.path}/native_window_probe.dart.template')
      .readAsStringSync();
  final configText = config.readAsStringSync();
  if (!RegExp(
    r'^PRODUCT_BUNDLE_IDENTIFIER = .+$',
    multiLine: true,
  ).hasMatch(configText)) {
    throw StateError('Bundle config differs; no writes applied');
  }
  final preparedWindow = baseline.replaceFirst(
    anchor,
    '$anchor\n#if DEBUG\n'
    '${joinAllApplications ? "    if #available(macOS 13.0, *) {\n      collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]\n    }\n" : ""}'
    '    installWindowProbe(controller: flutterViewController)\n#endif',
  );
  await window.writeAsString(
    (floatingPreview
            ? preparedWindow.replaceFirst(
                '    super.awakeFromNib()',
                '    super.awakeFromNib()\n#if DEBUG\n    level = .floating\n    orderFrontRegardless()\n#endif',
              )
            : preparedWindow) +
        swift,
  );
  await config.writeAsString(
    configText.replaceFirst(
      RegExp(r'^PRODUCT_BUNDLE_IDENTIFIER = .+$', multiLine: true),
      'PRODUCT_BUNDLE_IDENTIFIER = $bundleId',
    ),
  );
  await File('$project/lib/native_window_probe.dart').writeAsString(dart);
  await main.writeAsString(
    "import 'package:flutter/widgets.dart';\nimport 'preview_app.dart';\nimport 'native_window_probe.dart';\nexport 'preview_app.dart' show PreviewApp;\nFuture<void> main() async {\n WidgetsFlutterBinding.ensureInitialized();\n installWindowProbe();\n await launchPreview();\n}\n",
  );
  await File('$project/native-window-probe.json').writeAsString(
    jsonEncode({
      'schema': 1,
      'bundleId': bundleId,
      'readOnly': true,
      'windowPolicy': floatingPreview
          ? 'floatingPreview'
          : joinAllApplications
          ? 'joinAllApplications'
          : 'default',
      'sources': [
        for (final source in [
          window,
          config,
          main,
          File('$project/lib/native_window_probe.dart'),
        ])
          {
            'path': source.path.substring(project.length + 1),
            'sha256': sha256.convert(await source.readAsBytes()).toString(),
          },
      ],
    }),
  );
}
