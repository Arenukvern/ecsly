import 'browser_apply_args.dart';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'resident_registry.dart';
import 'resident_viewer.dart';

@JS('__mcpActions')
external JSObject? get _actions;
@JS('__mcpActions')
external set _actions(JSObject value);
@JS('__ecslyViewerState')
external set _state(JSFunction value);
@JS('__ecslyViewerViews')
external set _views(JSFunction value);

bool _installed = false;

/// One bridge per engine, with explicit viewer addresses and removable ownership.
void Function() installViewerBridge(String id, ResidentViewer viewer) {
  if (!_installed) {
    final catalog = _actions ?? JSObject();
    if (catalog.hasProperty('viewer_apply'.toJS).toDart) {
      throw StateError('action_catalog_conflict: viewer_apply');
    }
    final handler = ((JSAny? args) => _apply(args).toJS).toJS;
    catalog.setProperty(
      'viewer_apply'.toJS,
      {
        'description': 'Apply a visualization revision to one mounted viewer.',
        'schema': {
          'type': 'object',
          'additionalProperties': false,
          'properties': {
            'viewerId': {'type': 'string'},
            'document': {'type': 'string'},
            'requestId': {'type': 'string'},
            'expectedRevision': {'type': 'integer'},
          },
          'required': ['document', 'requestId', 'expectedRevision'],
        },
        'invoke': handler,
      }.jsify(),
    );
    _actions = catalog;
    _state = (([JSString? id]) => jsonEncode(
      residentRegistry.resolve(id?.toDart).state(),
    ).toJS).toJS;
    _views = (() => jsonEncode(residentRegistry.ids).toJS).toJS;
    _installed = true;
  }
  residentRegistry.attach(id, viewer);
  return () => residentRegistry.detach(id, viewer);
}

Future<JSAny?> _apply(JSAny? args) async {
  final values = browserApplyArgs(args.dartify());
  final id = values.remove('viewerId');
  if (id != null && id is! String) {
    throw const FormatException('Invalid viewerId');
  }
  return (await residentRegistry.resolve(id as String?).apply(values)).jsify();
}
