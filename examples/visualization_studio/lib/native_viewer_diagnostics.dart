import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'resident_registry.dart';

bool _installed = false;

/// Explicit debug-only adapter; callbacks resolve the existing mounted registry.
void installNativeViewerDiagnostics() {
  final destination = Platform.environment['ECSLY_PREVIEW_DIAGNOSTICS'];
  if (const bool.fromEnvironment('dart.vm.product') || destination == null) {
    return;
  }
  if (!_installed) {
    developer.registerExtension(
      'ext.ecsly.visualizationViews',
      (_, params) async => developer.ServiceExtensionResponse.result(
        jsonEncode({'viewerIds': residentRegistry.ids}),
      ),
    );
    developer.registerExtension('ext.ecsly.visualizationState', (
      _,
      params,
    ) async {
      try {
        return developer.ServiceExtensionResponse.result(
          jsonEncode(residentRegistry.resolve(params['viewerId']).state()),
        );
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          '$error',
        );
      }
    });
    developer.registerExtension('ext.ecsly.visualizationApply', (
      _,
      params,
    ) async {
      try {
        final values = Map<String, Object?>.from(params);
        final target = values.remove('viewerId') as String?;
        values['expectedRevision'] = int.tryParse(
          params['expectedRevision'] ?? '',
        );
        return developer.ServiceExtensionResponse.result(
          jsonEncode(await residentRegistry.resolve(target).apply(values)),
        );
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
          developer.ServiceExtensionResponse.extensionError,
          '$error',
        );
      }
    });
    _installed = true;
  }
  // URI publication is asynchronous and does not gate widget/frame construction.
  _publish(destination);
}

Future<void> _publish(String destination) async {
  try {
    final file = File(destination);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'schema': 1, 'pid': pid, 'phase': 'engine_bootstrap'}),
    );
    final service = await developer.Service.getInfo();
    final temporary = File('$destination.$pid.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schema': 1,
        'phase': 'service_discovery',
        'pid': pid,
        'vmServiceUri': service.serverUri?.toString(),
        'extensions': [
          'ext.ecsly.visualizationViews',
          'ext.ecsly.visualizationState',
          'ext.ecsly.visualizationApply',
        ],
      }),
    );
    await temporary.rename(destination);
  } catch (error) {
    // Diagnostics must not turn a functioning app into an initialization failure.
    developer.log('Native diagnostic discovery failed', error: error);
  }
}
