import 'native_dev_checks.dart';
import 'native_attach_checks.dart';
import 'native_runtime_checks.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Bounded native launch qualification. The AppKit probe owns only its returned app.
Future<void> main(List<String> args) async {
  final project = Directory(args[0]).resolveSymbolicLinksSync();
  final output = Directory(args[2]);
  final devProbe = args[3] == 'native-dev' || args[3] == 'native-dev-cohort';
  final attachProbe = args[3] == 'native-attach';
  final captureProbe = args[3] == 'native-capture-sck';
  final inputProbe = args[3] == 'native-input';
  final windowProbe = args[3] == 'native-window-state';
  final toolkitProbe = args[3] == 'native-toolkit';
  final runtimeProbe =
      args[3] == 'native-runtime' ||
      attachProbe ||
      devProbe ||
      captureProbe ||
      inputProbe ||
      windowProbe ||
      toolkitProbe;
  final posture = args[3] == 'native-hidden' ? 'hidden' : 'background';
  try {
    if (!Platform.isMacOS)
      throw UnsupportedError('Native probe requires macOS');
    final debug = Directory('$project/build/macos/Build/Products/Debug');
    final apps = debug
        .listSync()
        .whereType<Directory>()
        .where((app) => app.path.endsWith('.app'))
        .toList();
    if (apps.length != 1)
      throw StateError('Expected exactly one prebuilt debug app');
    final core = await Isolate.resolvePackageUri(
      Uri.parse('package:oka_core/oka_core.dart'),
    );
    if (core == null) throw StateError('Oka dependency could not be located');
    final root = File.fromUri(core).parent.parent.parent.parent;
    final source = File(
      '${root.path}/tool/native_preview/native_launch_probe.swift',
    );
    if (!source.existsSync())
      throw StateError('Native probe requires editable Oka source');
    final executable = '${output.path}/native-launch-probe';
    final compile = await Process.run('/usr/bin/swiftc', [
      source.path,
      '-o',
      executable,
    ]);
    await File('${output.path}/compile.log')
        .writeAsString('${compile.stdout}\n${compile.stderr}');
    if (compile.exitCode != 0)
      throw StateError('Native probe compile failed: ${compile.exitCode}');
    await File('${output.path}/probe-source.json').writeAsString(
      jsonEncode({
        'source': source.path,
        'sha256': sha256.convert(source.readAsBytesSync()).toString(),
        'app': apps.single.path,
        'posture': posture,
        'limit': 'Probe source identity; full native app/SDK closure is not fingerprinted.',
      }),
    );
    File? ownedDiscovery;
    late ProcessResult launched;
    var runtimePassed = !runtimeProbe;
    if (runtimeProbe) {
      final bundleInfo = await Process.run('/usr/libexec/PlistBuddy', [
        '-c',
        'Print :CFBundleIdentifier',
        '${apps.single.path}/Contents/Info.plist',
      ]);
      final bundleId = bundleInfo.stdout.toString().trim();
      final home = Platform.environment['HOME'];
      if (bundleInfo.exitCode != 0 ||
          home == null ||
          !RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(bundleId)) {
        throw StateError('Native app container identity is unavailable');
      }
      // Preserve the app sandbox: the launched app can write its own temp area.
      final discovery = File(
        '$home/Library/Containers/$bundleId/Data/tmp/'
        'ecsly-preview-${DateTime.now().microsecondsSinceEpoch}-$pid.json',
      );
      ownedDiscovery = discovery;
      if (discovery.existsSync())
        throw StateError('Refusing existing discovery receipt');
      await File('${output.path}/discovery-location.json').writeAsString(
        jsonEncode({
          'bundleId': bundleId,
          'path': discovery.path,
          'appSandboxPreserved': true,
        }),
      );
      final completion = File('${output.path}/runtime-complete');
      final config = File('${output.path}/runtime-launch-config.json');
      await config.writeAsString(
        jsonEncode({
          'completionFile': completion.path,
          'observationBudgetSeconds': attachProbe || devProbe ? 120 : 45,
          'environment': {
            'ECSLY_PREVIEW_DIAGNOSTICS': discovery.path,
            'FLUTTER_ENGINE_SWITCHES': '3',
            'FLUTTER_ENGINE_SWITCH_1': 'enable-dart-profiling=true',
            'FLUTTER_ENGINE_SWITCH_2': 'enable-checked-mode=true',
            'FLUTTER_ENGINE_SWITCH_3': 'vm-service-port=0',
          },
        }),
      );
      final process = await Process.start(executable, [
        apps.single.path,
        '${output.path}/launch.json',
        posture,
        config.path,
      ]);
      final stdoutBody = utf8.decoder.bind(process.stdout).join();
      final stderrBody = utf8.decoder.bind(process.stderr).join();
      final exit = process.exitCode;
      int? launchExit;
      exit.then((code) => launchExit = code);
      try {
        await qualifyNativeRuntime(
          discovery,
          output,
          launchExit: () => launchExit,
          inputProbe: inputProbe,
          windowProbe: windowProbe,
          toolkitProbe: toolkitProbe,
          captureProbe: captureProbe
              ? File(
                  '${root.path}/tool/native_preview/window_capture_probe.swift',
                )
              : null,
        );
        if (attachProbe) await qualifyNativeAttach(discovery, project, output);
        if (devProbe)
          await qualifyNativeDev(
            discovery,
            project,
            root.path,
            output,
            cohort: args[3] == 'native-dev-cohort',
          );
        runtimePassed = true;
      } catch (error, stack) {
        await File('${output.path}/native-runtime.json').writeAsString(
          jsonEncode({'passed': false, 'error': '$error', 'stack': '$stack'}),
        );
      } finally {
        if (discovery.existsSync()) {
          await discovery.copy('${output.path}/runtime-discovery.json');
        }
        await completion.writeAsString('done');
      }
      launched = ProcessResult(
        process.pid,
        await exit,
        await stdoutBody,
        await stderrBody,
      );
    } else {
      launched = await Process.run(executable, [
        apps.single.path,
        '${output.path}/launch.json',
        posture,
      ]);
    }
    await File('${output.path}/launch.log')
        .writeAsString('${launched.stdout}\n${launched.stderr}');
    final receipt = jsonDecode(
      await File('${output.path}/launch.json').readAsString(),
    ) as Map;
    var discoveryRemoved = false;
    if (receipt['teardownVerified'] == true &&
        ownedDiscovery != null &&
        ownedDiscovery.existsSync()) {
      await ownedDiscovery.delete();
      discoveryRemoved = true;
    }
    final passed =
        launched.exitCode == 0 &&
        receipt['passed'] == true &&
        receipt['teardownVerified'] == true &&
        runtimePassed;
    await File('${output.path}/result.json').writeAsString(
      jsonEncode({
        'passed': passed,
        'checks': receipt,
        'runtimeQualified': runtimeProbe && runtimePassed,
        'containerDiscoveryRemoved': discoveryRemoved,
        'scope': 'Nonactivating launch and returned-process teardown; native-runtime also verifies app frames, never compositor pixels.',
      }),
    );
    if (!passed)
      throw StateError(
        'Native launch not qualified: ${receipt['gap'] ?? receipt['phase']}',
      );
  } catch (error, stack) {
    final result = File('${output.path}/result.json');
    if (!result.existsSync())
      await result.writeAsString(
        jsonEncode({'passed': false, 'error': '$error', 'stack': '$stack'}),
      );
    rethrow;
  }
  print('visualization-dogfood-complete');
}
