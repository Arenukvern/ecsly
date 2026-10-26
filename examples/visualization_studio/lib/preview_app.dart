import 'native_bootstrap_stub.dart'
    if (dart.library.io) 'native_viewer_diagnostics.dart'
    as native;

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'multi_view_host.dart';
import 'preview_canvas.dart';
import 'preview_checkpoint.dart';
import 'checkpoint_bootstrap.dart';
import 'view_configuration_stub.dart'
    if (dart.library.js_interop) 'view_configuration_web.dart';
import 'preview_model.dart';
import 'preview_shell.dart';
import 'resident_document.dart';
import 'resident_viewer.dart';
import 'visual_language.dart';
import 'startup_trace.dart';
import 'viewer_web_bridge_stub.dart'
    if (dart.library.js_interop) 'viewer_web_bridge.dart';

Future<void> launchPreview({
  PreviewViewportBuilder viewportBuilder = canvasViewport,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  native.installNativeViewerDiagnostics();
  SemanticsBinding.instance.ensureSemantics();
  final preferences = await SharedPreferences.getInstance();
  runWidget(
    MultiViewHost(
      viewBuilder: (context) {
        final id = viewerAddress(View.of(context).viewId);
        return CheckpointBootstrap(
          key: ValueKey(id),
          read: () =>
              previewCheckpoints.readSettled('preview.snapshot.$id', () async {
                await preferences.reload();
                return preferences.getString('preview.snapshot.$id');
              }),
          builder: (context, saved) {
            var snapshot = const PreviewSnapshot();
            if (saved != null) {
              try {
                snapshot = PreviewSnapshot.decode(saved);
              } catch (error) {
                debugPrint(
                  'PREVIEW ignored incompatible checkpoint for $id: $error',
                );
              }
            }
            return PreviewApp(
              viewerId: id,
              viewportBuilder: viewportBuilder,
              initial: snapshot,
              preferences: preferences,
            );
          },
        );
      },
    ),
  );
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({
    super.key,
    this.initial = const PreviewSnapshot(),
    this.preferences,
    this.renderScene = true,
    this.viewportBuilder = canvasViewport,
    this.onViewerReady,
    this.viewerId = 'standalone',
  });
  final String viewerId;
  final PreviewSnapshot initial;
  final SharedPreferences? preferences;
  final bool renderScene;
  final PreviewViewportBuilder viewportBuilder;

  /// Optional host adapter: register native tools without coupling this app to MCP.
  final ValueChanged<ResidentViewer>? onViewerReady;
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  late final World world = createPreviewWorld(widget.initial);
  late final EcsController controller = EcsController(world: world);
  final paused = ValueNotifier(true);
  late final ResidentViewer viewer = ResidentViewer(world, controller);
  late VoidCallback removeBridge;
  CheckpointHandle? checkpoint;

  void _attachCheckpoint() {
    final preferences = widget.preferences;
    if (preferences == null) return;
    final key = 'preview.snapshot.${widget.viewerId}';
    checkpoint = previewCheckpoints.attach(
      key: key,
      write: (value) => preferences.setString(key, value),
      read: () async {
        await preferences.reload();
        return preferences.getString(key);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    removeBridge = installViewerBridge(widget.viewerId, viewer);
    _attachCheckpoint();
    widget.onViewerReady?.call(viewer);
    world.getResource<StartupTrace>().mark('viewerBridgeInstalled');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        world.getResource<StartupTrace>().mark('firstWidgetFrameCompleted');
      }
    });
    controller.addListener(_pauseChanged);
  }

  @override
  void deactivate() {
    removeBridge();
    checkpoint?.detach();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    removeBridge = installViewerBridge(widget.viewerId, viewer);
    _attachCheckpoint();
  }

  void _pauseChanged() {
    final s = world.getResource<PreviewResource>().value;
    paused.value = !s.playing || s.example != Example.simulation;
  }

  @override
  void dispose() {
    removeBridge();
    checkpoint?.detach();
    viewer.dispose();
    controller.removeListener(_pauseChanged);
    controller.dispose();
    paused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    textDirection: TextDirection.ltr,
    explicitChildNodes: true,
    label: 'Visualization viewer ${widget.viewerId}',
    child: EcsAppScope(
      world: world,
      controller: controller,
      schedules: EcsFlutterSchedules(
        frame: EcsFrameSchedule.fixed(
          'preview.tick',
          fixedDt: 1 / 60,
          maxCatchUpStepsPerTick: 4,
          paused: paused,
          invalidation: EcsInvalidationBatch.resource<PreviewResource>(),
        ),
      ),
      child: EcsResourceSelector<PreviewResource, bool>(
        select: (r) => r.value.dark,
        builder: (context, dark) =>
            EcsResourceSelector<DocumentResource, VisualizationDocument>(
              select: (r) => r.value,
              builder: (context, document) => MaterialApp(
                title: 'Ecsly visualization preview',
                debugShowCheckedModeBanner: false,
                themeAnimationDuration: Duration.zero,
                theme: visualizationTheme(dark, Color(document.accent)),
                home: PreviewShell(
                  world: world,
                  controller: controller,
                  checkpoint: checkpoint,
                  renderScene: widget.renderScene,
                  viewportBuilder: widget.viewportBuilder,
                ),
              ),
            ),
      ),
    ),
  );
}
