import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:ecsly_visualization_studio/preview_canvas.dart';
import 'package:ecsly_visualization_studio/preview_model.dart';
import 'package:ecsly_visualization_studio/startup_trace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Canvas picking changes shared selection and observes painting', (
    tester,
  ) async {
    final world = createPreviewWorld();
    final controller = EcsController(world: world);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 360,
            child: PreviewCanvas(world: world, controller: controller),
          ),
        ),
      ),
    );
    final viewport = find.byType(PreviewCanvas);
    final origin = tester.getTopLeft(viewport);
    // Parse is x=-1.5 in the shared document; projection spans eight units.
    await tester.tapAt(origin + const Offset(268, 180));
    await tester.pump();
    expect(world.getResource<PreviewResource>().value.selected, 1);
    expect(
      world.getResource<StartupTrace>().toJson()['marksUs'],
      contains('firstCanvasPaintReturned'),
    );
    await controller.runAction(
      ChangePreview((old) => old.copyWith(distance: 16, selected: 0)),
    );
    await tester.pump();
    await tester.tapAt(origin + const Offset(334, 180));
    await tester.pump();
    expect(world.getResource<PreviewResource>().value.selected, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
