import 'dart:convert';
import 'dart:io';

import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

const _lockAttempts = 2;
const _lockRetryDelay = Duration(milliseconds: 1);

void main() {
  late Directory tempDir;
  late String path;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ecsly_context_log');
    path = '${tempDir.path}/context.jsonl';
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('appends one JSON object per line, newline-terminated (ack)', () async {
    final log = await JsonlEventLog.open(path);
    log.append(const BeatAppended(id: 1, date: '2026-10-01', text: 'first'));
    log.append(const BeatAppended(id: 2, date: '2026-10-02', text: 'second'));
    final content = File(path).readAsStringSync();
    final lines = content.split('\n')..removeLast();
    expect(lines, hasLength(2));
    for (final line in lines) {
      expect(() => jsonDecode(line), returnsNormally);
    }
    expect(content.codeUnitAt(content.length - 1), 0x0A);
    log.close();
  });

  test('replay is deterministic and idempotent across reloads', () async {
    final log = await JsonlEventLog.open(path);
    log.append(const BeatAppended(id: 1, date: '2026-10-01', text: 'first'));
    log.append(const BeatAppended(id: 2, date: '2026-10-02', text: 'second'));
    log.append(
      const SummaryAdded(id: 3, date: '2026-10-02', text: 'both', summarizes: [1, 2]),
    );
    final first = ContextGraph(log);
    final second = ContextGraph(log);
    expect(first.state, second.state);
    String encode(final ContextEvent event) => jsonEncode(event.toJson());
    expect(log.load().map(encode).toList(), log.load().map(encode).toList());
    log.close();
  });

  test('crash tail: unacknowledged partial line is repaired, ids continue', () async {
    final log = await JsonlEventLog.open(path);
    log.append(const BeatAppended(id: 1, date: '2026-10-01', text: 'first'));
    log.append(const BeatAppended(id: 2, date: '2026-10-02', text: 'second'));
    log.close();

    // Simulate a torn write: partial JSON bytes without a newline.
    File(path).writeAsBytesSync(
      '{"type":"beatAppended","id":3,"dat'.codeUnits,
      mode: FileMode.append,
    );

    final reopened = await JsonlEventLog.open(path);
    final events = reopened.load();
    expect(events, hasLength(2));
    final repaired = File(path).readAsBytesSync();
    expect(repaired.last, 0x0A);
    expect(File(path).readAsStringSync().contains('"id":3'), isFalse);

    reopened.append(const BeatAppended(id: 3, date: '2026-10-03', text: 'third'));
    final graph = ContextGraph(reopened);
    expect(graph.read(3)!.text, 'third');
    expect(graph.read(1)!.text, 'first');
    expect(graph.state.nextId, 4);
    reopened.close();
  });

  test('crash tail: a full but unparsable final line is repaired', () async {
    final log = await JsonlEventLog.open(path);
    log.append(const BeatAppended(id: 1, date: '2026-10-01', text: 'first'));
    log.close();
    File(path).writeAsStringSync('garbage\n', mode: FileMode.append);
    final reopened = await JsonlEventLog.open(path);
    expect(reopened.load(), hasLength(1));
    expect(File(path).readAsStringSync().contains('garbage'), isFalse);
    reopened.close();
  });

  test('mid-file corruption is named, never silently truncated', () async {
    final valid = jsonEncode(
      const BeatAppended(id: 1, date: '2026-10-01', text: 'first').toJson(),
    );
    final trailing = jsonEncode(
      const BeatAppended(id: 2, date: '2026-10-02', text: 'second').toJson(),
    );
    File(path).writeAsStringSync('$valid\ngarbage\n$trailing\n');
    final log = await JsonlEventLog.open(path);
    expect(
      log.load,
      throwsA(
        isA<ContextLogCorruptException>()
            .having((final error) => error.line, 'line', 2)
            .having((final error) => error.path, 'path', path),
      ),
    );
    log.close();
  });

  test('lock exclusivity: second opener fails fast, close releases', () async {
    final log = await JsonlEventLog.open(path);
    await expectLater(
      JsonlEventLog.open(
        path,
        lockAttempts: _lockAttempts,
        lockRetryDelay: _lockRetryDelay,
      ),
      throwsA(isA<ContextLockException>()),
    );
    log.close();
    final reopened = await JsonlEventLog.open(
      path,
      lockAttempts: _lockAttempts,
      lockRetryDelay: _lockRetryDelay,
    );
    reopened.append(const BeatAppended(id: 1, date: '2026-10-01', text: 'next'));
    expect(File(path).readAsStringSync(), isNotEmpty);
    reopened.close();
  });

  test('a stale lock from a dead holder is stolen, not waited on', () async {
    // A pid that has already exited: the shell prints its own pid, then dies.
    final probe = await Process.run('sh', <String>['-c', r'echo $$']);
    final deadPid = int.parse(probe.stdout.toString().trim());
    File('$path.lock').writeAsStringSync('stale pid=$deadPid\n');
    final log = await JsonlEventLog.open(
      path,
      lockAttempts: _lockAttempts,
      lockRetryDelay: _lockRetryDelay,
    );
    log.append(
      const BeatAppended(id: 1, date: '2026-10-01', text: 'after the steal'),
    );
    expect(File(path).readAsStringSync(), isNotEmpty);
    log.close();
  });

  test('close is idempotent; use after close is a named error', () async {
    final log = await JsonlEventLog.open(path);
    log.append(const BeatAppended(id: 1, date: '2026-10-01', text: 'first'));
    log.close();
    expect(log.close, returnsNormally);
    expect(
      () => log.append(const BeatAppended(id: 2, date: '2026-10-02', text: 'x')),
      throwsA(isA<StateError>()),
    );
    expect(File('$path.lock').existsSync(), isFalse);
  });

  test('events round-trip through JSON with exact fields', () async {
    final log = await JsonlEventLog.open(path);
    log.append(const BeatAppended(id: 1, date: '2026-10-01', text: 'raw'));
    log.append(
      const SummaryAdded(id: 2, date: '2026-10-01', text: 'sum', summarizes: [1]),
    );
    log.append(
      DecompositionAdded(originalId: 1, children: const [
        DecompositionPart(id: 3, text: 'part'),
      ]),
    );
    log.append(const BeatForgotten(id: 2));
    final decoded = log.load();
    expect(decoded, hasLength(4));
    expect(decoded[0], isA<BeatAppended>());
    final summary = decoded[1] as SummaryAdded;
    expect(summary.summarizes, [1]);
    final decomposition = decoded[2] as DecompositionAdded;
    expect(decomposition.originalId, 1);
    expect(decomposition.children.single.id, 3);
    expect(decomposition.children.single.text, 'part');
    expect(decoded[3], isA<BeatForgotten>());
    log.close();
  });
}
