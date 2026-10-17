import 'package:flutter/material.dart';

import 'preview_model.dart';

class SignalChart extends StatelessWidget {
  const SignalChart({
    required this.selected,
    required this.onSelected,
    super.key,
  });
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Semantics(
      label:
          'Displacement over time, 0 to 4 seconds, minus 1 to 1 metre. Selected sample $selected.',
      child: GestureDetector(
        onTapUp: (d) => onSelected(
          (((d.localPosition.dx - 52) / (c.maxWidth - 68)) * 32).round().clamp(
            0,
            32,
          ),
        ),
        child: CustomPaint(
          size: Size(c.maxWidth, 220),
          painter: _SignalPainter(
            selected,
            Theme.of(context).colorScheme,
            Theme.of(context).textTheme,
          ),
        ),
      ),
    ),
  );
}

class _SignalPainter extends CustomPainter {
  _SignalPainter(this.selected, this.colors, this.text);
  final int selected;
  final ColorScheme colors;
  final TextTheme text;
  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTRB(52, 20, size.width - 16, size.height - 46);
    Offset point(double t, double y) => Offset(
      frame.left + t / 4 * frame.width,
      frame.bottom - (y + 1.2) / 2.4 * frame.height,
    );
    void label(String value, Offset position, {bool center = false}) {
      final p = TextPainter(
        text: TextSpan(
          text: value,
          style: text.labelMedium!.copyWith(color: colors.onSurface),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(canvas, position - Offset(center ? p.width / 2 : 0, 0));
    }

    final grid = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    for (final y in [-1.0, 0.0, 1.0]) {
      final p = point(0, y);
      canvas.drawLine(p, point(4, y), grid);
      label(y.toStringAsFixed(0), Offset(30, p.dy - 7));
    }
    canvas.drawRect(
      frame,
      Paint()
        ..color = colors.outlineVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (var t = 0; t <= 4; t++) {
      label(
        '$t',
        Offset(point(t.toDouble(), 0).dx, frame.bottom + 6),
        center: true,
      );
    }
    label('Time (s)', Offset(frame.center.dx, size.height - 20), center: true);
    label('Displacement (m)', const Offset(52, 0));
    final path = Path();
    for (var i = 0; i <= 256; i++) {
      final p = point(i / 64, displacement(i / 64, 1));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.primary
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    final p = point(selected / 8, displacement(selected / 8, 1));
    canvas.drawLine(
      Offset(p.dx, frame.top),
      Offset(p.dx, frame.bottom),
      Paint()..color = colors.onSurfaceVariant.withValues(alpha: 0.4),
    );
    canvas.drawCircle(p, 5, Paint()..color = colors.primary);
    for (var i = 0; i <= 32; i++) {
      if (i == selected) continue;
      canvas.drawCircle(
        point(i / 8, displacement(i / 8, 1)),
        2,
        Paint()..color = colors.primary.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SignalPainter old) =>
      selected != old.selected || colors != old.colors;
}
