import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:oka_core/oka_core.dart';
import 'package:oka_web/oka_web.dart';
import 'package:universal_browser_cdp/universal_browser_cdp.dart';

/// Sequential fresh pages in one owned browser; no compiler or process restart.
Future<void> qualifyRetainedBrowser({
  required BrowserPageSession owner,
  required CdpPage ownerPage,
  required String project,
  required Uri appUrl,
  required Directory output,
  required List<Map<String, Object?>> checks,
}) async {
  if (!owner.ownedProcess) throw StateError('Trial requires its own browser');
  final registry = ProcessLeaseRegistry.forProject(project);
  final leaseId = 'chrome-visualization-dogfood-$pid';
  final beforeLease = await registry.read(leaseId);
  if (beforeLease == null || beforeLease.ownership != LeaseOwnership.owned) {
    throw StateError('Owner lease missing before retained trial');
  }
  final leaseJson = jsonEncode(beforeLease.toJson());
  Future<Map<String, dynamic>> state(CdpPage page) async =>
      jsonDecode(await page.evaluate('window.__ecslyViewerState()') as String)
          as Map<String, dynamic>;
  final beforeOwner = await state(ownerPage);
  Future<Set<String>> pageIds() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      return await (() async {
        final response = await (await client.getUrl(
          owner.browserHttpUrl.resolve('/json/list'),
        )).close();
        if (response.statusCode != 200)
          throw StateError('CDP target discovery failed');
        final rows =
            jsonDecode(await utf8.decoder.bind(response).join()) as List;
        await File('${output.path}/last-target-catalog.json')
            .writeAsString(jsonEncode(rows));
        return {
          for (final row in rows)
            if ((row as Map)['type'] == 'page') row['id'] as String,
        };
      })().timeout(const Duration(seconds: 5));
    } finally {
      client.close(force: true);
    }
  }

  final rows = <Map<String, Object?>>[];
  for (var sample = 0; sample < 3; sample++) {
    final originalPages = await pageIds();
    final clock = Stopwatch()..start();
    BrowserPageSession? borrowed;
    CdpPage? page;
    String? id;
    final stages = <String, int>{};
    try {
      borrowed = await startBrowserPageSession(
        context: BuildContext(
          projectPath: project,
          buildDir: '$project/.oka_cache/dogfood',
          mode: BuildMode.debug,
          config: OkaConfig.empty,
        ),
        appUrl: appUrl,
        sessionName: 'visualization-borrower-$pid-$sample',
        spec: BrowserSessionSpec(debugPort: owner.browserHttpUrl.port),
        onStage: (stage, elapsed) => stages[stage] = elapsed.inMicroseconds,
      );
      if (borrowed.ownedProcess)
        throw StateError('Borrower spawned another process');
      final socket = Uri.parse(borrowed.pageWsUrl);
      id = socket.pathSegments.last;
      page = await CdpPage.attach(
        await CdpConnection.connect(socket),
        CdpTargetInfo(
          id: id,
          type: 'page',
          url: appUrl.toString(),
          title: 'Retained browser trial',
          webSocketDebuggerUrl: socket.toString(),
        ),
      );
      final deadline = clock.elapsed + const Duration(seconds: 20);
      Map<String, dynamic>? current;
      while (clock.elapsed < deadline) {
        final ready = await page.evaluate(
          'typeof window.__ecslyViewerState === "function"',
        );
        if (ready == true) {
          current = await state(page);
          final marks = (current['startup'] as Map?)?['marksUs'] as Map?;
          if (marks?['firstCanvasPaintReturned'] is num ||
              marks?['firstSceneRenderReturned'] is num)
            break;
        }
        current = null;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (current == null)
        throw TimeoutException('Borrowed viewer did not render');
      stages['rendererObserved'] = clock.elapsedMicroseconds;
      if (current['runtimeId'] == beforeOwner['runtimeId']) {
        throw StateError('Fresh page aliased the original viewer');
      }
      rows.add({
        'sample': sample,
        'stagesUs': stages,
        'startup': current['startup'],
        'ownedProcess': borrowed.ownedProcess,
        'pageId': id,
      });
    } finally {
      try {
        await page?.close(closeTarget: false);
      } finally {
        await borrowed?.stop();
      }
    }
    // /json/close acknowledges initiation. Observe removal without replaying it.
    var remaining = await pageIds();
    final closeClock = Stopwatch()..start();
    while (remaining.contains(id) &&
        remaining.containsAll(originalPages) &&
        closeClock.elapsed < const Duration(seconds: 5)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      remaining = await pageIds();
    }
    await File('${output.path}/borrower-$sample.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        ...rows.last,
        'originalPages': originalPages.toList(),
        'remainingPages': remaining.toList(),
        'closeObservedUs': closeClock.elapsedMicroseconds,
      }),
    );
    if (remaining.contains(id) || !remaining.containsAll(originalPages)) {
      throw StateError(
        'Borrower cleanup changed another page or retained its page',
      );
    }
    final afterLease = await registry.read(leaseId);
    if (afterLease == null || jsonEncode(afterLease.toJson()) != leaseJson) {
      throw StateError('Borrowing changed the owner process lease');
    }
    final afterOwner = await state(ownerPage);
    for (final key in [
      'runtimeId',
      'presentedRevision',
      'selected',
      'example',
      'dark',
      'time',
    ]) {
      if (afterOwner[key] != beforeOwner[key])
        throw StateError('Borrower changed owner $key');
    }
    checks.add({
      'action': 'retained browser fresh page $sample',
      'effect':
          'observed independent runtime, page cleanup and unchanged owner',
    });
  }
  await File('${output.path}/retained-browser.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'samples': rows,
      'ownerPid': beforeLease.pid,
      'ownerLeasePreserved': true,
      'note': 'Sequential fresh pages in a warm browser, not retained-world updates, a p95 or compositor timing.',
    }),
  );
}
