import 'dart:convert';

import 'package:ecsly_flutter/ecsly_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:ecsly_visualization_tokens/ecsly_visualization_tokens.dart';

import 'preview_model.dart';
import 'resident_document.dart';
import 'automation_fixture.dart';
import 'startup_trace.dart';

/// One resident host, using existing ECS transactions for all document effects.
class ResidentViewer {
  ResidentViewer(this.world, this.controller, {VoidCallback? requestFrame})
    : requestFrame =
          requestFrame ?? WidgetsBinding.instance.scheduleForcedFrame;
  final VoidCallback requestFrame;
  final World world;
  final EcsController controller;
  final String runtimeId = DateTime.now().microsecondsSinceEpoch.toRadixString(
    36,
  );
  final Map<String, (String, Map<String, Object?>)> _requests = {};
  bool _disposed = false;
  void dispose() => _disposed = true;
  int applyCount = 0;
  int presentedRevision = 0;
  int? lastDataToFrameUs;
  Map<String, Object?>? lastReceipt;
  String get documentId => world.getResource<DocumentResource>().value.id;
  int get revision => world.getResource<DocumentResource>().value.revision;
  Map<String, Object?> state() => {
    ...jsonDecode(world.getResource<PreviewResource>().value.encode())
        as Map<String, dynamic>,
    'document': world.getResource<DocumentResource>().value.toJson(),
    'runtimeId': runtimeId,
    'compiledWithWasm': const bool.fromEnvironment('dart.tool.dart2wasm'),
    'codeRevision': visualizationCodeRevision(),
    'applyCount': applyCount,
    'presentedRevision': presentedRevision,
    'fixture': world.getResource<AutomationFixtureResource>().toJson(),
    'lastReceipt': lastReceipt,
    'dataToFlutterFrameUs': lastDataToFrameUs,
    'startup': world.getResource<StartupTrace>().toJson(),
  };

  Future<Map<String, Object?>> apply(Map<String, Object?> args) async {
    if (_disposed) throw StateError('viewer_disposed');
    final frameClock = Stopwatch()..start();
    final source = args['document'],
        requestId = args['requestId'],
        expected = args['expectedRevision'];
    if (source is! String ||
        source.length > 32768 ||
        requestId is! String ||
        requestId.isEmpty ||
        requestId.length > 100 ||
        expected is! int) {
      throw const FormatException(
        'document, requestId and expectedRevision are required',
      );
    }
    final fingerprint = jsonEncode([source, expected]);
    final prior = _requests[requestId];
    if (prior != null) {
      if (prior.$1 != fingerprint) throw StateError('request_id_conflict');
      lastReceipt = {...prior.$2, 'replayed': true};
      return lastReceipt!;
    }
    if (_requests.length >= 256) throw StateError('resident_request_capacity');
    final candidate = VisualizationDocument.fromJson(
      jsonDecode(source) as Map<String, dynamic>,
    );
    if (expected != revision) throw StateError('document_revision_stale');
    if (candidate.revision <= revision) {
      throw StateError('document_revision_not_increasing');
    }
    controller.runTransaction(
      (w) => w.getResource<DocumentResource>().value = candidate,
      invalidation: EcsInvalidationBatch.resource<DocumentResource>(),
    );
    applyCount++;
    // Presented means a Flutter frame completed, not an independent pixel oracle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && revision == candidate.revision) {
        presentedRevision = candidate.revision;
        lastDataToFrameUs = frameClock.elapsedMicroseconds;
      }
    });
    // A remote author may update a background preview. Request one frame even
    // when the normal lifecycle gate suppresses idle animation frames.
    requestFrame();
    final receipt = <String, Object?>{
      'requestId': requestId,
      'runtimeId': runtimeId,
      'revision': revision,
      'applyCount': applyCount,
      'replayed': false,
    };
    _requests[requestId] = (fingerprint, receipt);
    lastReceipt = receipt;
    return receipt;
  }
}
