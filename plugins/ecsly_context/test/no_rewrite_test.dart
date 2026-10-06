import 'dart:io';

import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';


/// Tricky verbatim texts: nothing here may ever come back altered.
const _trickyTexts = <String>[
  'Plain decision line about the memory CLI.',
  'Multi\nline\nwith\ttabs and   uneven   spacing  ',
  'Unicode: héllo wörld — 日本語のテキスト 🚀',
  '#12 2020-01-01 a line that looks like a legacy record',
  'Regex specials: ^\$.*+?()[]{}|\\ and quotes \' " backtick',
];

ContextGraph _graphOnDisk(final JsonlEventLog log) => ContextGraph(log);void main() {
  late Directory tempDir;
  late String path;
  late JsonlEventLog log;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('ecsly_context_rewrite');
    path = '${tempDir.path}/context.jsonl';
    log = await JsonlEventLog.open(path);
  });

  tearDown(() {
    log.close();
    tempDir.deleteSync(recursive: true);
  });

  test('stored text is byte-identical through append and reload', () {
    final graph = _graphOnDisk(log);
    for (final text in _trickyTexts) {
      graph.append('2026-10-06', text);
    }
    final reloaded = _graphOnDisk(log);
    for (var i = 0; i < _trickyTexts.length; i++) {
      expect(reloaded.read(i + 1)!.text, _trickyTexts[i]);
    }
  });

  test('projection output lines are whole stored texts, substring-free', () {
    final graph = _graphOnDisk(log);
    for (final text in _trickyTexts) {
      graph.append('2026-10-06', text);
    }
    final reloaded = _graphOnDisk(log);
    final view = reloaded.wake(budgetLines: _trickyTexts.length);
    expect(view.lines, hasLength(_trickyTexts.length));
    for (final line in view.lines) {
      expect(_trickyTexts, contains(line.text));
    }
    for (final absence in view.absences) {
      expect(
        absence.reason,
        anyOf(Absence.notSummarized, Absence.summarizedOutOfFrame),
      );
    }
    final recall = reloaded.recall('line', cap: _trickyTexts.length);
    for (final match in recall.matches) {
      expect(_trickyTexts, contains(match.beat.text));
    }
    final zoom = reloaded.zoom(const IdRange(1, 1));
    final beat = zoom.items.single as ZoomBeat;
    expect(_trickyTexts, contains(beat.beat.text));
  });

  test('derive and decompose never touch source texts', () {
    final graph = _graphOnDisk(log);
    for (final text in _trickyTexts) {
      graph.append('2026-10-06', text);
    }
    graph.derive([1, 2], 'a summary text');
    graph.decompose(1, <String>['part one', 'part two']);
    final reloaded = _graphOnDisk(log);
    for (var i = 0; i < _trickyTexts.length; i++) {
      expect(reloaded.read(i + 1)!.text, _trickyTexts[i]);
    }
  });

  test('the public surface has no rewrite or fit primitives', () {
    // The design law: text is never rewritten, truncated, substringed or
    // merged, and there is no substring-to-fit primitive anywhere. Record
    // framing (line splitting for import parsing) is not text rewriting.
    final forbidden = <String>[
      'substring(',
      'padLeft(',
      'padRight(',
      'replaceAll(',
      'replaceFirst(',
    ];
    final libDir = Directory('lib');
    final offenders = <String>[];
    for (final file in libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((final file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final needle in forbidden) {
        if (source.contains(needle)) {
          offenders.add('${file.path} contains $needle');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'design law forbids rewrite/fit');
  });
}
