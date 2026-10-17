{{flutter_js}}
{{flutter_build_config}}

// The embedding host chooses the mode; the resident app uses public Flutter APIs.
const previewLoaderConfig = {
  entrypointBaseUrl: document.baseURI,
  assetBase: document.baseURI,
  canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
};
_flutter.loader.load({
  config: previewLoaderConfig,
  onEntrypointLoaded: async function (initializer) {
    const multiView = document.documentElement.hasAttribute('data-ecsly-multi-view');
    const engine = await initializer.initializeEngine({
      ...previewLoaderConfig, multiViewEnabled: multiView,
    });
    const app = await engine.runApp();
    window.__ecslyEngine = app;
    if (multiView) {
      for (const host of document.querySelectorAll('[data-ecsly-viewer]')) {
        const id = app.addView({hostElement: host,
          initialData: {viewerId: host.dataset.ecslyViewer}});
        host.dataset.flutterViewId = String(id);
      }
    }
  }
});
