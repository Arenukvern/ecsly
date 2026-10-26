import 'dart:convert';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecsly_visualization_studio/main.dart';
import 'package:ecsly_visualization_studio/preview_model.dart';
import 'package:ecsly_visualization_studio/resident_document.dart';
import 'package:ecsly_visualization_studio/resident_registry.dart';
import 'package:ecsly_visualization_studio/resident_viewer.dart';

Map<String, Object?> update(String title) => {
  'requestId': 'same-id-in-two-worlds',
  'expectedRevision': 1,
  'document': jsonEncode({
    ...defaultDocument.toJson(),
    'revision': 2,
    'title': title,
  }),
};

void main() {
  test('registry refuses ambiguity, duplicates and stale teardown', () {
    final registry = ResidentRegistry();
    final worldA = createPreviewWorld();
    final worldB = createPreviewWorld();
    final a = ResidentViewer(worldA, EcsController(world: worldA));
    final b = ResidentViewer(worldB, EcsController(world: worldB));
    try {
      registry.attach('alpha', a);
      registry.attach('beta', b);
      expect(() => registry.resolve(), throwsStateError);
      expect(() => registry.attach('alpha', b), throwsStateError);
      registry.detach('alpha', a);
      registry.attach('alpha', b);
      registry.detach('alpha', a);
      expect(registry.resolve('alpha'), same(b));
      expect(() => registry.resolve('removed'), throwsStateError);
    } finally {
      a.dispose();
      a.controller.dispose();
      b.dispose();
      b.controller.dispose();
    }
  });

  testWidgets(
    'removing one host preserves the other and isolates checkpoints',
    (tester) async {
      tester.view.physicalSize = const Size(1120, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      late ResidentViewer alpha;
      late ResidentViewer beta;
      Widget hosts(bool includeAlpha) => Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            if (includeAlpha)
              Expanded(
                key: const ValueKey('alpha-host'),
                child: PreviewApp(
                  key: const ValueKey('alpha'),
                  viewerId: 'alpha',
                  renderScene: false,
                  preferences: preferences,
                  initial: const PreviewSnapshot(selected: 1, yaw: .3),
                  onViewerReady: (v) => alpha = v,
                ),
              ),
            Expanded(
              key: const ValueKey('beta-host'),
              child: PreviewApp(
                key: const ValueKey('beta'),
                viewerId: 'beta',
                renderScene: false,
                preferences: preferences,
                initial: const PreviewSnapshot(selected: 4, yaw: .8),
                onViewerReady: (v) => beta = v,
              ),
            ),
          ],
        ),
      );
      await tester.pumpWidget(hosts(true));
      final betaBefore = beta;
      await alpha.apply(update('Alpha title'));
      await tester.pumpAndSettle();
      expect(beta.revision, 1);
      expect(beta.state()['selected'], 4);
      expect(beta.state()['yaw'], .8);
      await beta.apply(update('Beta title'));
      await tester.pumpAndSettle();
      expect(alpha.applyCount, 1);
      expect(beta.applyCount, 1);
      expect(find.text('Alpha title'), findsOneWidget);
      expect(find.text('Beta title'), findsOneWidget);
      for (final id in ['alpha', 'beta']) {
        await tester.tap(
          find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.text('Save checkpoint'),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(
        PreviewSnapshot.decode(preferences.getString('preview.snapshot.alpha')!)
            .selected,
        1,
      );
      expect(
        PreviewSnapshot.decode(preferences.getString('preview.snapshot.beta')!)
            .selected,
        4,
      );
      await tester.pumpWidget(hosts(false));
      await tester.pumpAndSettle();
      expect(beta, same(betaBefore));
      expect(beta.revision, 2);
      expect(residentRegistry.ids, ['beta']);
      await expectLater(alpha.apply(update('Detached')), throwsStateError);
      expect(beta.state()['selected'], 4);
      await tester.pumpWidget(const SizedBox());
      expect(residentRegistry.ids, isEmpty);
    },
  );
}
