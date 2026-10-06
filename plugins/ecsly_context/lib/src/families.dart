/// Behaviour-signature families over the beat graph — the meaning payload
/// contract v1 (ADR 0071 in the harness repo).
///
/// Families are the EVIDENCE layer beside the graph's RECORD layer: they
/// answer "what kinds of records exist, which are hot, what follows what"
/// without reading any text. The shape follows the contract codemap proved
/// for code: closed mechanical signatures, family ids that are a pure
/// function of the canonical signature, weighted connections, hot/cold by
/// fan-in, and honesty markers (`degraded`, named truncation).
///
/// Laws carried from the graph:
/// - payloads carry ids, counts and digest-derived ids only — beat text
///   never enters a family payload;
/// - budgets resolve by selection with a named tail (`totalFamilies`,
///   `truncated`), never by silent clipping;
/// - the basis is `exact_mechanical`: identical clause shape is a hint
///   from word shape, never a claim of semantic equivalence.
///
/// Determinism: the same folded state always yields the same view, and a
/// family id computed here matches the same signature computed anywhere
/// else that follows the spec — the digest is the platform-stable 32-bit
/// FNV-1a from the ecsly core, not a process-local identity.
library;

// Value objects with all-final fields; the lint's @immutable marker lives
// in package:meta, which this SDK-only plugin does not depend on.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

import 'package:ecsly/ecsly.dart';

import 'beat_kind.dart';
import 'context_beat.dart';
import 'context_state.dart';
import 'segment.dart';

/// The comparison basis of every v1 family: signatures are computed from
/// exact verbatim text by the mechanical clause segmenter.
const String familyBasisExactMechanical = 'exact_mechanical';

/// Default family cap for a [FamiliesView].
const int defaultFamiliesCap = 8;

/// The closed mechanical signature of one beat: its kind plus the counts
/// of clause kinds the segmenter finds in its verbatim text.
///
/// The canonical string — the contract's identity surface — is
/// `beatKind=<name>;clauses=action:<a>,done:<d>,fact:<f>,open:<o>` with
/// all four counts always present in that order. The family id is
/// `bh:` + 8 lowercase hex digits of the platform-stable FNV-1a 32-bit
/// digest of the canonical string, so the same signature names the same
/// family in every store, process and consumer.
final class BehaviourSignature {
  /// Creates a signature from precomputed counts. Prefer
  /// [BehaviourSignature.of].
  const BehaviourSignature({
    required this.beatKind,
    required this.actionClauses,
    required this.doneClauses,
    required this.factClauses,
    required this.openClauses,
  });

  /// The signature of [beat]: its kind plus the clause-kind counts of a
  /// fresh mechanical segmentation of its verbatim text.
  factory BehaviourSignature.of(final ContextBeat beat) {
    final counts = <ClauseKind, int>{
      for (final kind in ClauseKind.values) kind: 0,
    };
    for (final clause in segmentText(beat.text).clauses) {
      counts[clause.kind] = counts[clause.kind]! + 1;
    }
    return BehaviourSignature(
      beatKind: beat.kind,
      actionClauses: counts[ClauseKind.action]!,
      doneClauses: counts[ClauseKind.done]!,
      factClauses: counts[ClauseKind.fact]!,
      openClauses: counts[ClauseKind.open]!,
    );
  }

  /// The beat kind this signature's beats share.
  final BeatKind beatKind;

  /// Directive clauses (`next`, `fix`, `run`, ...).
  final int actionClauses;

  /// Settled clauses (`landed`, `proven`, ...).
  final int doneClauses;

  /// Plain fact clauses — the default kind.
  final int factClauses;

  /// Open-thread clauses (`blocker`, `todo`, ...).
  final int openClauses;

  /// The contract's canonical signature string (see the class docs).
  String get canonical =>
      'beatKind=${beatKind.name}'
      ';clauses=action:$actionClauses,done:$doneClauses'
      ',fact:$factClauses,open:$openClauses';

  /// The platform-stable 32-bit digest of [canonical].
  int get digest => DeterministicSectionHashing.stableStringHash(canonical);

  /// The family id: `bh:` + 8 lowercase hex digits of [digest]. A pure
  /// function of [canonical] — identical signatures name identical
  /// families across stores, processes and consumers.
  String get familyId => 'bh:${_hex8(digest)}';

  /// Total clauses the signature counts.
  int get clauseCount =>
      actionClauses + doneClauses + factClauses + openClauses;

  /// The contract payload for this signature.
  Map<String, Object?> toJson() => <String, Object?>{
    'beatKind': beatKind.name,
    'clauses': <String, Object?>{
      'action': actionClauses,
      'done': doneClauses,
      'fact': factClauses,
      'open': openClauses,
    },
    'canonical': canonical,
    'basis': familyBasisExactMechanical,
  };

  @override
  bool operator ==(final Object other) =>
      other is BehaviourSignature &&
      other.beatKind == beatKind &&
      other.actionClauses == actionClauses &&
      other.doneClauses == doneClauses &&
      other.factClauses == factClauses &&
      other.openClauses == openClauses;

  @override
  int get hashCode => Object.hash(
    beatKind,
    actionClauses,
    doneClauses,
    factClauses,
    openClauses,
  );

  @override
  String toString() => canonical;
}

/// One aggregated family-to-family edge, direction included.
final class FamilyConnection {
  const FamilyConnection._(this.fromFamilyId, this.toFamilyId, this.weight);

  /// The source family id (the earlier beat, or the provenance source).
  final String fromFamilyId;

  /// The target family id (the later beat, or the derived beat).
  final String toFamilyId;

  /// How many beat-level links the edge aggregates.
  final int weight;

  /// The contract payload for this edge.
  Map<String, Object?> toJson() => <String, Object?>{
    'from': fromFamilyId,
    'to': toFamilyId,
    'weight': weight,
  };

  @override
  String toString() => '$fromFamilyId -> $toFamilyId x$weight';
}

/// One behaviour family: the signature, its member beats, and the
/// aggregated evidence around it.
final class FamilyRecord {
  FamilyRecord._(
    this.id,
    this.signature,
    this.memberIds,
    this.archivedMembers,
    this.connections,
    this.fanIn,
  );

  /// The family id (`bh:`-prefixed, signature-derived, contract-stable).
  final String id;

  /// The shared signature.
  final BehaviourSignature signature;

  /// Member beat ids, ascending. Text lives in the graph — read members
  /// through [ContextGraph.read]/[ContextGraph.zoom].
  final List<int> memberIds;

  /// How many members are archived out of the wake frame (they persist
  /// and still count as evidence).
  final int archivedMembers;

  /// Aggregated connections touching this family (outgoing and incoming,
  /// direction named by [FamilyConnection.fromFamilyId]/toFamilyId),
  /// sorted by target then source id for determinism. Self-edges are
  /// never created.
  final List<FamilyConnection> connections;

  /// Summed inbound connection weight — the hot/cold rank.
  final int fanIn;

  /// Honesty marker, false in v1: the computation has no caps or partial
  /// reads to hide. Reserved so a future degradation has somewhere true
  /// to stand.
  final bool degraded = false;

  /// Lowest member id — one end of the family's addressable range.
  int get firstMemberId => memberIds.first;

  /// Highest member id — the other end of the addressable range.
  int get lastMemberId => memberIds.last;

  /// The contract payload: identity, signature, membership and evidence —
  /// ids and counts only, never text.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'basis': familyBasisExactMechanical,
    'signature': signature.toJson(),
    'members': memberIds,
    'archivedMembers': archivedMembers,
    'fanIn': fanIn,
    'degraded': degraded,
    'connections': <Object?>[
      for (final connection in connections) connection.toJson(),
    ],
  };

  @override
  String toString() =>
      '$id members=${memberIds.length} fanIn=$fanIn '
      'connections=${connections.length}';
}

/// The projected families view: the ranked records plus the named tail.
final class FamiliesView {
  const FamiliesView._(this.families, this.totalFamilies, this.budgetFamilies);

  /// The families that made the frame, ranked by fan-in, then member
  /// count, then id — a total, deterministic order.
  final List<FamilyRecord> families;

  /// How many families the store actually has.
  final int totalFamilies;

  /// The cap the view was built with.
  final int budgetFamilies;

  /// Whether [families] is a named selection of [totalFamilies].
  bool get truncated => totalFamilies > families.length;

  /// The contract payload for the whole view.
  Map<String, Object?> toJson() => <String, Object?>{
    'families': <Object?>[for (final family in families) family.toJson()],
    'totalFamilies': totalFamilies,
    'budgetFamilies': budgetFamilies,
    'truncated': truncated,
    'basis': familyBasisExactMechanical,
  };
}

/// Projects [state]'s live beats into behaviour-signature families.
///
/// Pure and deterministic: grouping is by signature, connections are
/// aggregated from thread adjacency (consecutive beats of one thread,
/// earlier -> later) and typed provenance (source -> derived for both
/// summaries and decompositions; sources forgotten from the log are
/// skipped), self-edges are never created, and the frame keeps the top
/// [cap] families ranked by fan-in, then member count, then id. Archived
/// beats count as evidence and are reported separately in
/// [FamilyRecord.archivedMembers].
FamiliesView buildFamilies(
  final ContextState state, {
  final int cap = defaultFamiliesCap,
}) {
  if (cap < 1) {
    throw ArgumentError.value(cap, 'cap', 'must be >= 1');
  }
  final members = <BehaviourSignature, List<int>>{};
  final archived = <BehaviourSignature, int>{};
  final signatureOf = <int, BehaviourSignature>{};
  for (final beat in state.beats.values) {
    final signature = BehaviourSignature.of(beat);
    signatureOf[beat.id] = signature;
    members.putIfAbsent(signature, () => <int>[]).add(beat.id);
    if (beat.archived) {
      archived[signature] = (archived[signature] ?? 0) + 1;
    }
  }
  for (final list in members.values) {
    list.sort();
  }

  final weights = <String, Map<String, int>>{};
  void link(final int fromBeatId, final int toBeatId) {
    final from = signatureOf[fromBeatId];
    final to = signatureOf[toBeatId];
    if (from == null || to == null || from == to) return;
    final row = weights.putIfAbsent(from.familyId, () => <String, int>{});
    row[to.familyId] = (row[to.familyId] ?? 0) + 1;
  }

  // Thread adjacency: consecutive beats of one thread, earlier -> later.
  final byThread = <String, List<ContextBeat>>{};
  for (final beat in state.beats.values) {
    byThread.putIfAbsent(beat.threadId, () => <ContextBeat>[]).add(beat);
  }
  for (final thread in byThread.values) {
    thread.sort((final a, final b) => a.id.compareTo(b.id));
    for (var i = 1; i < thread.length; i++) {
      link(thread[i - 1].id, thread[i].id);
    }
  }
  // Provenance: source -> derived, skipped when the source was forgotten.
  for (final beat in state.beats.values) {
    switch (beat.kind) {
      case BeatKind.summary:
        for (final sourceId in beat.summarizes) {
          if (state.beats.containsKey(sourceId)) link(sourceId, beat.id);
        }
      case BeatKind.decomposition:
        final original = beat.decomposedFrom;
        if (original != null && state.beats.containsKey(original)) {
          link(original, beat.id);
        }
      case BeatKind.raw:
        break;
    }
  }

  final fanIn = <String, int>{};
  final incident = <String, List<FamilyConnection>>{};
  for (final row in weights.entries) {
    for (final entry in row.value.entries) {
      final connection = FamilyConnection._(row.key, entry.key, entry.value);
      incident.putIfAbsent(row.key, () => <FamilyConnection>[]).add(connection);
      incident.putIfAbsent(entry.key, () => <FamilyConnection>[]).add(
        connection,
      );
    }
  }
  final records = <FamilyRecord>[];
  for (final entry in members.entries) {
    final id = entry.key.familyId;
    var inbound = 0;
    for (final row in weights.entries) {
      final weight = row.value[id];
      if (weight != null) inbound += weight;
    }
    final connections = List<FamilyConnection>.of(
      incident[id] ?? const <FamilyConnection>[],
    )..sort((final a, final b) {
      final byTo = a.toFamilyId.compareTo(b.toFamilyId);
      if (byTo != 0) return byTo;
      return a.fromFamilyId.compareTo(b.fromFamilyId);
    });
    fanIn[id] = inbound;
    records.add(
      FamilyRecord._(
        id,
        entry.key,
        List<int>.unmodifiable(entry.value),
        archived[entry.key] ?? 0,
        List<FamilyConnection>.unmodifiable(connections),
        inbound,
      ),
    );
  }
  records.sort((final a, final b) {
    final byFanIn = b.fanIn.compareTo(a.fanIn);
    if (byFanIn != 0) return byFanIn;
    final byMembers = b.memberIds.length.compareTo(a.memberIds.length);
    if (byMembers != 0) return byMembers;
    return a.id.compareTo(b.id);
  });
  final kept = records.length > cap ? records.sublist(0, cap) : records;
  return FamiliesView._(
    List<FamilyRecord>.unmodifiable(kept),
    records.length,
    cap,
  );
}

/// Lowercase 8-digit hex of a 32-bit value, without string-padding
/// primitives (the plugin's no-rewrite guard bans them).
String _hex8(final int value) {
  const digits = '0123456789abcdef';
  final out = StringBuffer();
  for (var shift = 28; shift >= 0; shift -= 4) {
    out.write(digits[(value >> shift) & 0xF]);
  }
  return out.toString();
}
