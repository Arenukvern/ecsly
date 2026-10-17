import 'dart:async';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/material.dart';

import 'preview_model.dart';
import 'resident_document.dart';
import 'startup_trace.dart';

typedef PreviewViewportBuilder = Widget Function(
  World world,
  EcsController controller,
);
Widget canvasViewport(World world, EcsController controller) =>
    PreviewCanvas(world: world, controller: controller);

/// Flutter painting adapter. State, schedules and actions stay with the host.
class PreviewCanvas extends StatelessWidget {
  const PreviewCanvas({
    required this.world,
    required this.controller,
    super.key,
  });
  final World world;
  final EcsController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final snapshot = world.getResource<PreviewResource>().value;
      final document = world.getResource<DocumentResource>().value;
      return Semantics(
        label: 'Interactive spatial view. Flutter Canvas renderer.',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final painter = _PreviewPainter(
              snapshot,
              document,
              Theme.of(context).colorScheme,
              world.getResource<StartupTrace>(),
            );
            return GestureDetector(
              onTapUp: (details) {
                final points = painter.points(size);
                var nearest = -1;
                var distance = 28.0;
                for (var i = 0; i < points.length; i++) {
                  final d = (points[i] - details.localPosition).distance;
                  if (d < distance) {
                    nearest = i;
                    distance = d;
                  }
                }
                if (nearest >= 0) {
                  unawaited(
                    controller.runAction(
                      ChangePreview((old) => old.copyWith(selected: nearest)),
                    ),
                  );
                }
              },
              child: CustomPaint(size: size, painter: painter),
            );
          },
        ),
      );
    },
  );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.snapshot, this.document, this.colors, this.trace);
  final PreviewSnapshot snapshot;
  final VisualizationDocument document;
  final ColorScheme colors;
  final StartupTrace trace;
  Offset project(List<double> p, Size size) => Offset(
    size.width / 2 + p[0] * (size.width - 96) / snapshot.distance,
    size.height / 2 - p[1] * (size.height - 88) * 2 / snapshot.distance,
  );
  List<Offset> points(Size size) => [
    for (
      var i = 0;
      i <
          switch (snapshot.example) {
            Example.graph => document.graphPositions.length,
            Example.simulation => 3,
            Example.linked => 33,
          };
      i++
    )
      project(
        snapshot.example == Example.graph
            ? document.graphPositions[i]
            : markPosition(snapshot.example, i, snapshot),
        size,
      ),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    trace.mark('firstCanvasPaintEntered');
    final nodes = points(size);
    final line = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    // Quiet coordinate grid keeps motion and dependencies easy to read.
    for (var i = -3; i <= 3; i++) {
      canvas.drawLine(
        project([i.toDouble(), -1.8, 0], size),
        project([i.toDouble(), 1.8, 0], size),
        Paint()..color = colors.outlineVariant.withValues(alpha: 0.25),
      );
    }
    if (snapshot.example == Example.graph) {
      for (final edge in graphEdges) {
        canvas.drawLine(nodes[edge.$1], nodes[edge.$2], line);
        final delta = nodes[edge.$2] - nodes[edge.$1];
        final unit = delta / delta.distance;
        final tip = nodes[edge.$2] - unit * 15;
        final normal = Offset(-unit.dy, unit.dx);
        canvas.drawPath(
          Path()
            ..moveTo(
              (tip - unit * 7 + normal * 4).dx,
              (tip - unit * 7 + normal * 4).dy,
            )
            ..lineTo(tip.dx, tip.dy)
            ..lineTo(
              (tip - unit * 7 - normal * 4).dx,
              (tip - unit * 7 - normal * 4).dy,
            ),
          line,
        );
      }
    } else if (snapshot.example == Example.linked) {
      final path = Path()..moveTo(nodes.first.dx, nodes.first.dy);
      for (final point in nodes.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, line);
    } else {
      for (var i = 0; i < 3; i++) {
        canvas.drawLine(
          project([-2.4 + i * 2.4, -1.6, 0], size),
          project([-2.4 + i * 2.4, 1.6, 0], size),
          line,
        );
      }
    }
    for (var i = 0; i < nodes.length; i++) {
      final selected = i == snapshot.selected;
      final radius = selected
          ? 11.0
          : snapshot.example == Example.linked
          ? 3.5
          : 8.0;
      if (selected) {
        canvas.drawCircle(
          nodes[i],
          radius + 6,
          Paint()..color = Color(document.accent).withValues(alpha: 0.15),
        );
      }
      canvas.drawCircle(
        nodes[i],
        radius,
        Paint()
          ..color = selected ? Color(document.accent) : colors.onSurfaceVariant,
      );
      if (snapshot.example == Example.graph || selected) {
        final label = snapshot.example == Example.graph
            ? document.graphLabels[i]
            : snapshot.example == Example.simulation
            ? 'Oscillator ${i + 1}'
            : 'Sample $i';
        final text = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 12,
              fontFamily: 'PreviewRoboto',
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, nodes[i] + Offset(-text.width / 2, 23));
      }
    }
    trace.mark('firstCanvasPaintReturned');
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
