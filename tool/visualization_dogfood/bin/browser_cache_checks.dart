import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:universal_browser_cdp/universal_browser_cdp.dart';

Future<void> qualifyBrowserCache(
  CdpPage page,
  Directory output,
  List<Map<String, Object?>> requests,
  List<Map<String, Object?>> checks, {
  bool immutable = false,
  String? bundlePrefix,
}) async {
  Future<Map<String, dynamic>> state() async =>
      jsonDecode(await page.evaluate('window.__ecslyViewerState()') as String)
          as Map<String, dynamic>;
  final before = await state();
  final firstRequests = List<Map<String, Object?>>.from(requests);
  final responses = <Map<String, Object?>>[];
  final requestUrls = <String, String>{};
  final servedFromCache = <String>[];
  await page.connection.send('Network.enable');
  final requestSubscription = page.connection
      .on('Network.requestWillBeSent')
      .listen((event) {
        final request = event.params['request'] as Map?;
        if (request != null)
          requestUrls[event.params['requestId'] as String] =
              request['url'] as String;
      });
  final cacheSubscription = page.connection
      .on('Network.requestServedFromCache')
      .listen((event) {
        servedFromCache.add(
          requestUrls[event.params['requestId']] ?? 'unresolved request',
        );
      });
  final subscription = page.connection.on('Network.responseReceived').listen((
    event,
  ) {
    final response = event.params['response'] as Map?;
    if (response != null)
      responses.add({
        'url': response['url'],
        'status': response['status'],
        'fromDiskCache': response['fromDiskCache'],
      });
  });
  final start = requests.length;
  final clock = Stopwatch()..start();
  try {
    await page.connection.send('Page.reload', {'ignoreCache': false});
    Map<String, dynamic>? after;
    while (clock.elapsed < const Duration(seconds: 30)) {
      if (await page.evaluate(
            'typeof window.__ecslyViewerState === "function"',
          ) ==
          true) {
        final current = await state();
        final marks = (current['startup'] as Map?)?['marksUs'] as Map?;
        if (current['runtimeId'] != before['runtimeId'] &&
            marks?['firstCanvasPaintReturned'] is num &&
            marks?['firstWidgetFrameCompleted'] is num) {
          after = current;
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (after == null)
      throw TimeoutException('Reloaded cached viewer did not render');
    final reloadToFrameObservedUs = clock.elapsedMicroseconds;
    final reloadRequests = requests.skip(start).toList();
    final cacheHits = reloadRequests
        .where((row) => row['status'] == 304)
        .toList();
    final browserCacheObserved =
        servedFromCache.any((url) => url.endsWith('/main.dart.js')) ||
        responses.any(
          (row) =>
              row['fromDiskCache'] == true &&
              (row['url'] as String).endsWith('/main.dart.js'),
        );
    if ((immutable ? !browserCacheObserved : cacheHits.isEmpty) ||
        !firstRequests.any((row) => row['status'] == 200)) {
      throw StateError(
        'Real first-load/matching-ETag cache behavior not observed',
      );
    }
    if (immutable &&
        (bundlePrefix == null ||
            [
              ...firstRequests,
              ...reloadRequests,
            ].any((row) => !(row['uri'] as String).startsWith(bundlePrefix)))) {
      throw StateError('Loader escaped immutable bundle namespace');
    }
    final stale = jsonDecode(
      await page.evaluateAsync(
        "fetch('main.dart.js',{cache:'no-store',headers:{'If-None-Match':'\"stale-fixture\"'}}).then(async r=>JSON.stringify({status:r.status,etag:r.headers.get('etag'),bytes:(await r.arrayBuffer()).byteLength}))",
      ) as String,
    ) as Map;
    if (stale['status'] != 200 ||
        stale['etag'] is! String ||
        (stale['bytes'] as num) <= 0) {
      throw StateError('Stale ETag did not receive the verified current body');
    }
    await File('${output.path}/browser-cache.json').writeAsString(
      jsonEncode({
        'staleTagResponse': stale,
        'firstRequests': firstRequests,
        'reloadRequests': reloadRequests,
        'responses': responses,
        'notModifiedCount': cacheHits.length,
        'servedFromCache': servedFromCache,
        'immutable': immutable,
        'reloadToFrameObservedUs': reloadToFrameObservedUs,
        'startup': after['startup'],
        'note': 'Fresh engine on same page; immutable cache events and HTTP revalidation are distinct. Not retained-world update or a controlled speed comparison.',
      }),
    );
    await File('${output.path}/cache-reloaded.png')
        .writeAsBytes(await CdpDriver(page).screenshot());
    checks.add({
      'action': immutable
          ? 'browser immutable-cache reload'
          : 'browser revalidation reload',
      'effect': immutable
          ? 'fresh viewer rendered with observed browser cache reuse'
          : 'fresh viewer rendered with observed 304 responses',
    });
  } finally {
    await subscription.cancel();
    await requestSubscription.cancel();
    await cacheSubscription.cancel();
  }
}
