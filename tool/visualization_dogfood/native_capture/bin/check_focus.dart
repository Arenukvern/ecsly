import 'dart:convert';
import 'dart:io';

import 'package:universal_driver_macos/universal_driver_macos.dart';

/// Consumer-side foreground observation over the existing native driver.
/// Samples include bring-up and owned teardown; no activation or input calls.
Future<void> main(List<String> args) async {
  if (args.length < 2)
    throw ArgumentError('check_focus NEW_RECEIPT COMMAND ARGS...');
  final receipt = File(args.first);
  if (receipt.existsSync()) throw StateError('Refusing existing receipt');
  final driver = MacosDriver();
  final watch = Stopwatch()..start();
  final before = await driver.frontmost();
  final changes = <Map<String, Object?>>[];
  var samples = 1;
  var maximumGapUs = 0;
  var lastUs = watch.elapsedMicroseconds;
  final process = await Process.start(args[1], args.skip(2).toList());
  final out = stdout.addStream(process.stdout);
  final err = stderr.addStream(process.stderr);
  int? result;
  process.exitCode.then((code) => result = code);
  try {
    do {
      final current = await driver.frontmost();
      final now = watch.elapsedMicroseconds;
      final gap = now - lastUs;
      if (gap > maximumGapUs) maximumGapUs = gap;
      lastUs = now;
      samples++;
      if (current.pid != before.pid) {
        changes.add({'atUs': now, 'pid': current.pid});
      }
      if (result != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    } while (true);
    await out;
    await err;
    await receipt.writeAsString(
      jsonEncode({
        'passed': result == 0 && changes.isEmpty,
        'childExitCode': result,
        'foregroundPid': before.pid,
        'samples': samples,
        'maximumGapUs': maximumGapUs,
        'changes': changes,
        'scope': 'OS foreground PID sampled through Universal Automation during the owned command, actions and teardown; transitions shorter than sample gaps are not ruled out',
      }),
    );
    if (result != 0 || changes.isNotEmpty) exitCode = 1;
  } finally {
    await driver.close();
  }
}
