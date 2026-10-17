import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) throw ArgumentError('native_input PID NAME NEW_OUTPUT');
  final pid = int.parse(args[0]);
  final name = args[1];
  final output = Directory(args[2]);
  if (output.existsSync()) throw StateError('Existing input receipt refused');
  output.createSync(recursive: true);
  final driver = MacosDriver(targetPid: pid);
  try {
    final requested = requestAppAccessibility(pid);
    await File('${output.path}/accessibility-request.json')
        .writeAsString(jsonEncode(requested));
    final clock = Stopwatch()..start();
    Snapshot? snapshot;
    var matches = 0;
    while (clock.elapsed < const Duration(seconds: 10)) {
      snapshot = await driver.snapshot();
      matches = snapshot.nodes
          .where((node) => node.role == 'button' && node.name == name)
          .length;
      if (matches > 1)
        throw StateError('Ambiguous native button: $name ($matches)');
      if (matches == 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await File('${output.path}/before.json')
        .writeAsString(jsonEncode(snapshot?.toJson()));
    if (matches != 1) throw StateError('Native button not observed: $name');
    await driver.perform(ClickAction(role: 'button', name: name));
    await File('${output.path}/delivery.json').writeAsString(
      jsonEncode({
        'pid': pid,
        'role': 'button',
        'name': name,
        'matches': matches,
        'delivery': 'AXPress completed; effect must be independently observed',
      }),
    );
    await File('${output.path}/after.json')
        .writeAsString(jsonEncode((await driver.snapshot()).toJson()));
  } catch (error, stack) {
    await File('${output.path}/failure.json')
        .writeAsString(jsonEncode({'error': '$error', 'stack': '$stack'}));
    rethrow;
  } finally {
    await driver.close();
  }
}
