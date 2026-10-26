export 'preview_app.dart' show PreviewApp;
import 'preview_app.dart';
import 'preview_scene.dart';

Future<void> main() => launchPreview(
  viewportBuilder: (world, controller) =>
      PreviewScene(world: world, controller: controller),
);
