import 'package:ecsly_visualization_studio/preview_mapping.dart';

import 'dart:convert';

import 'package:vector_math/vector_math.dart' as vm;

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecsly_visualization_studio/main.dart';
import 'package:ecsly_visualization_studio/preview_model.dart';

class RecordingSink implements SceneSink {
  final values = <String, VisualState>{};
  int updates = 0;
  @override
  int get count => values.length;
  @override
  void add(String key, VisualState visual) => values[key] = visual;
  @override
  void update(String key, VisualState visual) {
    values[key] = visual;
    updates++;
  }

  @override
  void remove(String key) => values.remove(key);
}

void main() {
  test('renderer camera projection and spatial picks agree off center', () {
    for (final width in [320.0, 1100.0]) {
      for (final yaw in [-3.06, 0.4]) {
        final rig = SceneCameraRig(distance: 8, yaw: yaw, pitch: 0.18);
        final camera = PerspectiveCamera(
          position: rig.cameraPosition(),
          target: rig.cameraTarget(),
        );
        const position = [-2.0, 0.3, 0.0];
        final size = Size(width, 360);
        final pixel = camera.worldToScreen(vm.Vector3.array(position), size)!;
        final visual = ExactVisualState(
          shape: SceneShape.sphere,
          argb: 0xFF245BA6,
          size: 0.23,
          position: position,
          pickId: 'off-center',
        );
        final hit = pickVisuals(
          visuals: {'mark': visual},
          ray: camera.screenPointToRay(pixel, size),
        );
        expect(hit?.pickId, 'off-center');
      }
    }
  });
  test('checkpoint restores observation, parameters and camera, paused', () {
    const original = PreviewSnapshot(
      example: Example.simulation,
      selected: 2,
      time: 1.234,
      frequency: 1.7,
      dark: true,
      playing: true,
      yaw: 0.5,
      pitch: -0.4,
      distance: 8,
    );
    final restored = PreviewSnapshot.decode(original.encode());
    expect(restored.example, original.example);
    expect(restored.selected, 2);
    expect(restored.time, 1.234);
    expect(restored.frequency, 1.7);
    expect(restored.distance, 8);
    expect(restored.yaw, 0.5);
    expect(restored.pitch, -0.4);
    expect(restored.dark, true);
    expect(restored.playing, false);
    final invalid = jsonDecode(original.encode()) as Map<String, dynamic>;
    invalid['selected'] = 5;
    expect(
      () => PreviewSnapshot.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
    invalid['selected'] = 2;
    invalid['frequency'] = -1;
    expect(
      () => PreviewSnapshot.decode(jsonEncode(invalid)),
      throwsFormatException,
    );
  });
  test(
    'exact signature updates unchanged-length curves and sub-centimetre motion',
    () {
      final world = createPreviewWorld(
        const PreviewSnapshot(example: Example.simulation),
      );
      final sink = RecordingSink();
      final binder = EcsSceneBinder(
        world: world,
        sink: sink,
        mapping: previewMapping(),
      );
      binder.sync();
      final first = Map<String, VisualState>.of(sink.values);
      world.getResource<PreviewResource>().value = const PreviewSnapshot(
        example: Example.simulation,
        time: 0.0001,
      );
      binder.sync();
      expect(sink.updates, greaterThanOrEqualTo(6));
      final sphereKey = first.keys.firstWhere(
        (k) => k.startsWith('PreviewMark'),
      );
      expect(
        sink.values[sphereKey]!.position,
        isNot(first[sphereKey]!.position),
      );
      final trailKey = 'static|g1';
      expect(
        sink.values[trailKey]!.points.length,
        first[trailKey]!.points.length,
      );
      expect(sink.values[trailKey]!.points, isNot(first[trailKey]!.points));
      final updates = sink.updates;
      binder.sync();
      expect(sink.updates, updates);
    },
  );
  test(
    'fixed-step replay is independent of presentation and clamps at endpoint',
    () {
      final a = createPreviewWorld(
        const PreviewSnapshot(example: Example.simulation, playing: true),
      );
      final b = createPreviewWorld(
        const PreviewSnapshot(example: Example.simulation, playing: true),
      );
      for (final world in [a, b]) {
        world.upsertResource(DeltaTimeResource(1 / 60));
        world.flush();
        for (var i = 0; i < 90; i++) {
          world.runSchedule(const ScheduleId('preview.tick'));
        }
      }
      final sa = a.getResource<PreviewResource>().value;
      final sb = b.getResource<PreviewResource>().value;
      expect(sa.time, closeTo(1.5, 1e-10));
      expect(
        markPosition(Example.simulation, 2, sa),
        markPosition(Example.simulation, 2, sb),
      );
      for (var i = 0; i < 500; i++) {
        a.runSchedule(const ScheduleId('preview.tick'));
      }
      expect(a.getResource<PreviewResource>().value.time, 8);
      expect(a.getResource<PreviewResource>().value.playing, false);
    },
  );
  test(
    'action changes one shared selection used by spatial and chart projections',
    () async {
      final world = createPreviewWorld();
      final controller = EcsController(world: world);
      await controller.runAction(
        ChangePreview((s) => s.copyWith(example: Example.linked, selected: 10)),
      );
      final snapshot = world.getResource<PreviewResource>().value;
      final visuals = previewMapping().collect(world).values;
      final selected = visuals.singleWhere((v) => v.pickId == '10');
      expect(selected.size, 0.23);
      expect(
        selected.position[1] / 1.3,
        closeTo(displacement(10 / 8, 1), 1e-10),
      );
      expect(selectionDetail(snapshot), contains('t = 1.250 s'));
      controller.dispose();
    },
  );
  testWidgets('three recipes and controls fit narrow widths with large text', (
    tester,
  ) async {
    for (final width in [320.0, 736.0, 1120.0]) {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      for (final example in Example.values) {
        await tester.pumpWidget(
          PreviewApp(
            key: UniqueKey(),
            renderScene: false,
            initial: PreviewSnapshot(example: example),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (example == Example.graph) {
          await tester.tap(find.text('Parse').last);
          await tester.pumpAndSettle();
          expect(find.text('Parse · 1 dependencies'), findsOneWidget);
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
