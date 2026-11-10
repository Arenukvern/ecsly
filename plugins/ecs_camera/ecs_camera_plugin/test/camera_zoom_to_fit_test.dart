import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Zoom Calculation Utilities', () {
    test('calculateRequiredZoom with aspect ratio preservation', () {
      const bounds = ui.Rect.fromLTRB(-100, -50, 100, 50); // 200x100 bounds
      const viewport = ui.Size(800, 600); // 800x600 viewport

      // With aspect ratio preservation - should use min zoom
      final zoomWithAspect = _calculateRequiredZoom(bounds, viewport, 0, true);
      final expectedZoom = math.min(
        viewport.width / bounds.width,
        viewport.height / bounds.height,
      );
      expect(zoomWithAspect, equals(expectedZoom));
    });

    test('calculateRequiredZoom without aspect ratio preservation', () {
      const bounds = ui.Rect.fromLTRB(-100, -50, 100, 50); // 200x100 bounds
      const viewport = ui.Size(800, 600); // 800x600 viewport

      // Without aspect ratio preservation - should use max zoom
      final zoomWithoutAspect = _calculateRequiredZoom(
        bounds,
        viewport,
        0,
        false,
      );
      final expectedZoom = math.max(
        viewport.width / bounds.width,
        viewport.height / bounds.height,
      );
      expect(zoomWithoutAspect, equals(expectedZoom));
    });

    test('calculateRequiredZoom applies padding correctly', () {
      const bounds = ui.Rect.fromLTRB(-50, -50, 50, 50); // 100x100 bounds
      const viewport = ui.Size(800, 600);
      const padding = 50.0;

      final zoomWithPadding = _calculateRequiredZoom(
        bounds,
        viewport,
        padding,
        true,
      );

      // Padded bounds should be 200x200 (100 + 2*50)
      final paddedBounds = ui.Rect.fromLTRB(
        bounds.left - padding,
        bounds.top - padding,
        bounds.right + padding,
        bounds.bottom + padding,
      );

      final expectedZoom = math.min(
        viewport.width / paddedBounds.width,
        viewport.height / paddedBounds.height,
      );
      expect(zoomWithPadding, equals(expectedZoom));
    });

    test('calculateRequiredZoom handles zero-sized bounds', () {
      const bounds = ui.Rect.zero;
      const viewport = ui.Size(800, 600);

      final zoom = _calculateRequiredZoom(bounds, viewport, 0, true);
      expect(
        zoom,
        equals(1.0),
        reason: 'Should return default zoom for zero-sized bounds',
      );
    });

    test('calculateRequiredZoom handles negative bounds', () {
      const bounds = ui.Rect.fromLTRB(
        50,
        50,
        -50,
        -50,
      ); // Invalid negative bounds
      const viewport = ui.Size(800, 600);

      final zoom = _calculateRequiredZoom(bounds, viewport, 0, true);
      expect(
        zoom,
        equals(1.0),
        reason: 'Should return default zoom for invalid bounds',
      );
    });
  });
}

double _calculateRequiredZoom(
  final ui.Rect bounds,
  final ui.Size viewportSize,
  final double padding,
  final bool maintainAspectRatio,
) {
  // Add padding to bounds
  final paddedBounds = ui.Rect.fromLTRB(
    bounds.left - padding,
    bounds.top - padding,
    bounds.right + padding,
    bounds.bottom + padding,
  );

  final boundsWidth = paddedBounds.width;
  final boundsHeight = paddedBounds.height;

  if (boundsWidth <= 0 || boundsHeight <= 0) return 1;

  final zoomX = viewportSize.width / boundsWidth;
  final zoomY = viewportSize.height / boundsHeight;

  return maintainAspectRatio
      ? math.min(zoomX, zoomY) // Fit entirely
      : math.max(zoomX, zoomY); // Fill viewport
}
