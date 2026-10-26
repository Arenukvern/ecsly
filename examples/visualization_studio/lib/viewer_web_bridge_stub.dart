import 'resident_registry.dart';
import 'resident_viewer.dart';

void Function() installViewerBridge(String id, ResidentViewer viewer) {
  residentRegistry.attach(id, viewer);
  return () => residentRegistry.detach(id, viewer);
}
