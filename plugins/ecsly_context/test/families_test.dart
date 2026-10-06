import 'package:ecsly_context/ecsly_context.dart';
import 'package:test/test.dart';

import 'memory_store.dart';

void main() {
  group('behaviour signature (contract surface)', () {
    test('canonical string, digest and family id match the pinned spec', () {
      // One plain fact clause, no date, no topic: canonical
      // beatKind=raw;clauses=action:0,done:0,fact:1,open:0, whose
      // FNV-1a 32-bit digest over UTF-16 code units (low byte first) is
      // 0x6a3c6c29. These literals ARE the cross-consumer contract.
      final signature = BehaviourSignature.of(
        ContextBeat(id: 1, date: '2026-10-06', text: 'Plain decision line.'),
      );
      expect(
        signature.canonical,
        'beatKind=raw;clauses=action:0,done:0,fact:1,open:0',
      );
      expect(signature.digest, 0x6a3c6c29);
      expect(signature.familyId, 'bh:6a3c6c29');
    });

    test('clause shape separates signatures', () {
      final fact = BehaviourSignature.of(
        ContextBeat(id: 1, date: '2026-10-06', text: 'Plain decision line.'),
      );
      final open = BehaviourSignature.of(
        ContextBeat(id: 2, date: '2026-10-06', text: 'blocker: gate fails'),
      );
      final action = BehaviourSignature.of(
        ContextBeat(id: 3, date: '2026-10-06', text: 'next: run the gate'),
      );
      expect(fact.familyId, isNot(open.familyId));
      expect(open.familyId, isNot(action.familyId));
      expect(fact.openClauses, 0);
      expect(open.openClauses, 1);
      expect(action.actionClauses, 1);
    });

    test('beat kind separates identical clause shapes', () {
      final raw = BehaviourSignature.of(
        ContextBeat(id: 1, date: '2026-10-06', text: 'Plain decision line.'),
      );
      final summary = BehaviourSignature.of(
        ContextBeat(
          id: 2,
          date: '2026-10-06',
          text: 'Plain decision line.',
          kind: BeatKind.summary,
        ),
      );
      expect(raw.familyId, isNot(summary.familyId));
      expect(summary.beatKind, BeatKind.summary);
    });

    test('signatures are value objects', () {
      expect(
        BehaviourSignature.of(
          ContextBeat(id: 1, date: '2026-10-06', text: 'a; b'),
        ),
        BehaviourSignature.of(
          ContextBeat(id: 9, date: '2020-01-01', text: 'c; d'),
        ),
      );
    });
  });

  group('families projection', () {
    test('groups same-shape beats and aggregates adjacency weights', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      // Beats 1 and 3 share one clause shape; beat 2 is another family.
      graph.append('2026-10-06', 'Plain decision line.');
      graph.append('2026-10-06', 'blocker: gate fails');
      graph.append('2026-10-06', 'Another plain fact line.');

      final view = graph.families();
      expect(view.totalFamilies, 2);
      expect(view.truncated, isFalse);

      final twoMembers = view.families.firstWhere(
        (final family) => family.memberIds.length == 2,
      );
      final oneMember = view.families.firstWhere(
        (final family) => family.memberIds.length == 1,
      );
      // Ranking is fan-in, then member count, then id: both families have
      // fan-in 1 (one adjacency edge each way), so the bigger family wins.
      expect(view.families.first.id, twoMembers.id);
      expect(twoMembers.memberIds, [1, 3]);
      // Adjacency ran 1->2 and 2->3, crossing families both ways; the
      // same-family 1->3 adjacency is a self-edge and is never created.
      // The record carries both incident edges, direction named.
      expect(twoMembers.connections.length, 2);
      final outgoing = twoMembers.connections.firstWhere(
        (final connection) => connection.fromFamilyId == twoMembers.id,
      );
      expect(outgoing.toFamilyId, oneMember.id);
      final incoming = twoMembers.connections.firstWhere(
        (final connection) => connection.toFamilyId == twoMembers.id,
      );
      expect(incoming.fromFamilyId, oneMember.id);
      expect(oneMember.connections.length, 2);
    });

    test('provenance links sources to derived beats', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-06', 'blocker: gate fails');
      graph.append('2026-10-06', 'next: run the gate');
      graph.derive([1, 2], 'gate work settled');

      final view = graph.families();
      final summaryFamily = view.families.firstWhere(
        (final family) =>
            family.signature.beatKind == BeatKind.summary,
      );
      // The summary is the hottest family: two provenance edges plus the
      // 2->3 adjacency all point into it.
      expect(view.families.first.id, summaryFamily.id);
      expect(summaryFamily.fanIn, 3);
      expect(summaryFamily.connections.length, 2);
      for (final connection in summaryFamily.connections) {
        expect(connection.toFamilyId, summaryFamily.id);
      }
    });

    test('cap keeps the ranked frame and names the tail', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-06', 'Plain fact one.');
      graph.append('2026-10-06', 'blocker: one');
      graph.append('2026-10-06', 'next: one');
      final view = graph.families(cap: 2);
      expect(view.totalFamilies, 3);
      expect(view.budgetFamilies, 2);
      expect(view.truncated, isTrue);
      expect(view.families, hasLength(2));
    });

    test('the view is identical after a fresh fold of the same events', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-06', 'Plain fact one.');
      graph.append('2026-10-06', 'blocker: one');
      graph.derive([1, 2], 'settled');

      final refolded = ContextState.foldAll(store.events);
      final view = graph.families();
      expect(buildFamilies(refolded).toJson(), view.toJson());
    });

    test('archived members count as evidence and are named', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-06', 'long original thought');
      graph.decompose(1, <String>['part one', 'part two']);

      final view = graph.families();
      final originals = view.families.where(
        (final family) => family.archivedMembers > 0,
      );
      expect(originals, isNotEmpty);
      final originalFamily = originals.single;
      expect(originalFamily.memberIds, contains(1));
      expect(originalFamily.archivedMembers, 1);
    });

    test('forgotten derived beats leave the projection', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-06', 'Plain fact one.');
      graph.append('2026-10-06', 'blocker: one');
      final summary = graph.derive([1, 2], 'settled');
      expect(
        graph
            .families()
            .families
            .any((final family) => family.signature.beatKind
                == BeatKind.summary),
        isTrue,
      );
      graph.forget(summary.id);
      expect(
        graph
            .families()
            .families
            .any((final family) => family.signature.beatKind
                == BeatKind.summary),
        isFalse,
      );
    });

    test('family payloads never carry beat text', () {
      final store = MemoryStore();
      final graph = ContextGraph(store);
      graph.append('2026-10-06', 'the cantaloupe specification wins');
      final json = graph.families().toJson().toString();
      expect(json.contains('cantaloupe'), isFalse);
    });

    test('cap must be positive', () {
      final graph = ContextGraph(MemoryStore());
      expect(() => graph.families(cap: 0), throwsArgumentError);
    });
  });
}
