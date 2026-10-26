import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecsly_visualization_studio/checkpoint_bootstrap.dart';

void main() {
  testWidgets('host waits for storage and does not repeat read on rebuild', (
    tester,
  ) async {
    final read = Completer<String?>();
    var calls = 0;
    var builds = 0;
    Widget host() => Directionality(
      textDirection: TextDirection.ltr,
      child: CheckpointBootstrap(
        read: () {
          calls++;
          return read.future;
        },
        builder: (_, saved) {
          builds++;
          return Text('World initialized from $saved');
        },
      ),
    );
    await tester.pumpWidget(host());
    expect(builds, 0);
    expect(find.text('Loading preview checkpoint…'), findsOneWidget);
    await tester.pumpWidget(host());
    expect(calls, 1);
    read.complete('latest');
    await tester.pumpAndSettle();
    expect(find.text('World initialized from latest'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets('storage failure is visible without initializing or retrying', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      CheckpointBootstrap(
        read: () async {
          calls++;
          throw StateError('adapter unavailable');
        },
        builder: (_, saved) => const Text('Unexpected world'),
      ),
    );
    await tester.pump();
    expect(find.text('Preview checkpoint could not be loaded'), findsOneWidget);
    expect(find.text('Unexpected world'), findsNothing);
    await tester.pump();
    expect(calls, 1);
  });
}
