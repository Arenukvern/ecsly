{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load({config: {
  entrypointBaseUrl: document.baseURI, assetBase: document.baseURI,
  canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
}});
