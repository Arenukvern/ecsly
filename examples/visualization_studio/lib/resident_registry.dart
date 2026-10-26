import 'resident_viewer.dart';

/// Engine-local addresses. Registration does not own another viewer's world.
class ResidentRegistry {
  final _viewers = <String, ResidentViewer>{};
  List<String> get ids => _viewers.keys.toList()..sort();

  void attach(String id, ResidentViewer viewer) {
    if (!RegExp(r'^[a-zA-Z0-9_.-]{1,80}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Invalid viewer address');
    }
    if (_viewers.containsKey(id)) {
      throw StateError('viewer_address_in_use: $id');
    }
    _viewers[id] = viewer;
  }

  ResidentViewer resolve([String? id]) {
    if (id == null) {
      if (_viewers.length != 1) throw StateError('viewer_address_required');
      return _viewers.values.single;
    }
    final viewer = _viewers[id];
    if (viewer == null) throw StateError('viewer_not_mounted: $id');
    return viewer;
  }

  void detach(String id, ResidentViewer viewer) {
    if (identical(_viewers[id], viewer)) _viewers.remove(id);
  }
}

final residentRegistry = ResidentRegistry();
