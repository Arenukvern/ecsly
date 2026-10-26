import 'package:ecsly_visualization_studio/preview_mapping.dart';

import 'dart:convert';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecsly_visualization_studio/main.dart';
import 'package:ecsly_visualization_studio/preview_model.dart';
import 'package:ecsly_visualization_studio/resident_document.dart';
import 'package:ecsly_visualization_studio/resident_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, Object?> args({String id = 'edit-2'}) => {
    'requestId': id,
    'expectedRevision': 1,
    'document': jsonEncode({
      ...defaultDocument.toJson(),
      'revision': 2,
      'title': 'Resident experiment',
      'accent': 0xFF227C87,
      'nodes': [
        for (var i = 0; i < 6; i++)
          {
            'label': i == 0 ? 'Input' : defaultDocument.graphLabels[i],
            'position': i == 0
                ? [-2.5, 0.4, 0]
                : defaultDocument.graphPositions[i],
          },
      ],
    }),
  };
  test(
    'resident updates preserve state and renderer mapping, replay once',
    () async {
      final world = createPreviewWorld(
        const PreviewSnapshot(selected: 3, yaw: .4),
      );
      final controller = EcsController(world: world);
      final viewer = ResidentViewer(world, controller);
      final identity = viewer.runtimeId;
      final receipt = await viewer.apply(args());
      expect(viewer.runtimeId, identity);
      expect(viewer.applyCount, 1);
      expect(receipt['revision'], 2);
      expect(world.getResource<PreviewResource>().value.selected, 3);
      expect(world.getResource<PreviewResource>().value.yaw, .4);
      final input = previewMapping()
          .collect(world)
          .values
          .singleWhere((v) => v.pickId == '0');
      expect(input.label, 'Input');
      expect(input.position, [-2.5, .4, 0]);
      expect((await viewer.apply(args()))['replayed'], true);
      expect(viewer.applyCount, 1);
      await expectLater(
        viewer.apply({...args(), 'document': defaultDocument.encode()}),
        throwsStateError,
      );
      await expectLater(viewer.apply(args(id: 'stale')), throwsStateError);
      expect(viewer.revision, 2);
      controller.dispose();
    },
  );
  test('malformed document refuses before any resource mutation', () async {
    final world = createPreviewWorld();
    final controller = EcsController(world: world);
    final viewer = ResidentViewer(world, controller);
    await expectLater(
      viewer.apply({
        ...args(),
        'document': jsonEncode({...defaultDocument.toJson(), 'nodes': []}),
      }),
      throwsFormatException,
    );
    expect(viewer.applyCount, 0);
    expect(viewer.revision, 1);
    expect(world.getResource<DocumentResource>().value, same(defaultDocument));
    controller.dispose();
  });
  testWidgets(
    'document title, controls and palette change in same mounted host',
    (tester) async {
      ResidentViewer? viewer;
      await tester.pumpWidget(
        PreviewApp(
          renderScene: false,
          onViewerReady: (value) => viewer = value,
        ),
      );
      final identity = viewer!.runtimeId;
      await viewer!.apply(args());
      await tester.pumpAndSettle();
      expect(find.text('Resident experiment'), findsOneWidget);
      expect(find.text('Input'), findsOneWidget);
      expect(viewer!.runtimeId, identity);
      expect(viewer!.presentedRevision, 2);
    },
  );
  testWidgets('optional host adapter receives the mounted resident viewer', (
    tester,
  ) async {
    ResidentViewer? attached;
    await tester.pumpWidget(
      PreviewApp(
        renderScene: false,
        onViewerReady: (viewer) => attached = viewer,
      ),
    );
    expect(attached, isNotNull);
    await attached!.apply(args());
    await tester.pumpAndSettle();
    expect(attached!.state()['presentedRevision'], 2);
    expect(find.text('Resident experiment'), findsOneWidget);
  });
}
