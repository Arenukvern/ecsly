import 'dart:convert';

import 'package:ecsly_flutter/ecsly_flutter.dart';

import 'package:ecsly_flutter_scene/ecsly_flutter_scene.dart';

import 'preview_model.dart';
import 'resident_document.dart';

/// Full-content signature for this consumer: the upstream default rounds
/// positions and does not include polyline coordinate contents.
class ExactVisualState extends VisualState {
  const ExactVisualState({
    required super.shape,
    required super.argb,
    required super.size,
    required super.position,
    super.label,
    super.pickId,
    super.points,
  });
  @override
  String get signature =>
      jsonEncode([shape.name, argb, size, position, label, pickId, points]);
}

SceneMapping previewMapping() => SceneMapping()
  ..add<PreviewMark>((entity, mark, world) {
    final s = world.getResource<PreviewResource>().value;
    if (mark.example != s.example) return null;
    final selected = mark.index == s.selected;
    final document = world.getResource<DocumentResource>().value;
    return ExactVisualState(
      shape: SceneShape.sphere,
      argb: selected ? document.accent : (s.dark ? 0xFFB3B9C2 : 0xFF5A6472),
      size: selected ? 0.23 : (s.example == Example.linked ? 0.065 : 0.16),
      position: mark.example == Example.graph
          ? document.graphPositions[mark.index]
          : markPosition(mark.example, mark.index, s),
      label: mark.example == Example.graph
          ? document.graphLabels[mark.index]
          : mark.label,
      pickId: '${mark.index}',
    );
  })
  ..add<PreviewEdge>((entity, edge, world) {
    final s = world.getResource<PreviewResource>().value;
    if (s.example != Example.graph) return null;
    return ExactVisualState(
      shape: SceneShape.polyline,
      argb: s.dark ? 0xFF777F89 : 0xFFB1B7BF,
      size: 0.025,
      position: const [0, 0, 0],
      points: [
        world.getResource<DocumentResource>().value.graphPositions[edge.from],
        world.getResource<DocumentResource>().value.graphPositions[edge.to],
      ],
    );
  })
  ..ground = (world) {
    final s = world.getResource<PreviewResource>().value;
    final color = s.dark ? 0xFF666D77 : 0xFFBAC0C8;
    return [
      if (s.example != Example.graph)
        ExactVisualState(
          shape: SceneShape.polyline,
          argb: color,
          size: 0.015,
          position: const [0, 0, 0],
          points: const [
            [-3.5, 0, 0],
            [3.5, 0, 0],
          ],
        ),
      if (s.example == Example.simulation)
        for (var i = 0; i < 3; i++)
          ExactVisualState(
            shape: SceneShape.polyline,
            argb: color,
            size: 0.02,
            position: const [0, 0, 0],
            points: [
              for (var j = 0; j <= 32; j++)
                [
                  -2.4 + i * 2.4 + (j / 32 - 1) * 0.5,
                  1.5 * displacement(s.time - j / 32 * 0.4, s.frequency, i),
                  -0.35,
                ],
            ],
          ),
      if (s.example == Example.linked)
        ExactVisualState(
          shape: SceneShape.polyline,
          argb: color,
          size: 0.025,
          position: const [0, 0, 0],
          points: [
            for (var i = 0; i <= 32; i++) markPosition(Example.linked, i, s),
          ],
        ),
    ];
  };
