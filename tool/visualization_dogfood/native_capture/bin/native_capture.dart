import 'dart:convert';
import 'dart:io';

import 'native_window_capture.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 && args.length != 3) {
    throw ArgumentError('native_capture PID OUTPUT [WINDOW_ID]');
  }
  final bytes = await captureOwnedNativeWindow(
    int.parse(args[0]),
    windowId: args.length == 3 ? int.parse(args[2]) : null,
    onObserved: (value) =>
        File('${args[1]}.identity.json').writeAsStringSync(jsonEncode(value)),
  );
  await File(args[1]).writeAsBytes(bytes);
}
