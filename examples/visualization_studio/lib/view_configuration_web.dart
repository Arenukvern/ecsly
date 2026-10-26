import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

/// Optional host identity gives checkpoints a stable key across remounts.
String viewerAddress(int viewId) {
  final data = ui_web.views.getInitialData(viewId)?.dartify();
  if (data is Map && data.containsKey('viewerId')) {
    final id = data['viewerId'];
    if (id is! String || !RegExp(r'^[a-zA-Z0-9_.-]{1,80}$').hasMatch(id)) {
      throw const FormatException('Invalid initialData.viewerId');
    }
    return id;
  }
  return 'view-$viewId';
}
