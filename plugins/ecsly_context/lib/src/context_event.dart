import 'context_exception.dart';

/// One append-only mutation of the context store.
///
/// Events are the single source of truth; state is their fold. Text travels
/// through events verbatim — encoding never rewrites it.
sealed class ContextEvent {
  /// Subclasses only.
  const ContextEvent();

  /// Serializes the event to a JSON-compatible map (with a `type` tag).
  Map<String, Object?> toJson();

  /// Deserializes an event from a JSON map.
  ///
  /// Throws [ContextEventException] for unknown types and malformed fields;
  /// field-level problems never surface as raw cast errors.
  static ContextEvent fromJson(final Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String) {
      throw const ContextEventException('event is missing a string "type"');
    }
    switch (type) {
      case 'beatAppended':
        return BeatAppended(
          id: _intField(json, 'id', type),
          date: _stringField(json, 'date', type),
          text: _stringField(json, 'text', type),
          threadId: _stringField(json, 'threadId', type),
        );
      case 'summaryAdded':
        return SummaryAdded(
          id: _intField(json, 'id', type),
          date: _stringField(json, 'date', type),
          text: _stringField(json, 'text', type),
          threadId: _stringField(json, 'threadId', type),
          summarizes: _intListField(json, 'summarizes', type),
        );
      case 'decompositionAdded':
        final childrenRaw = json['children'];
        if (childrenRaw is! List<Object?>) {
          throw const ContextEventException(
            'decompositionAdded event needs a "children" list',
          );
        }
        final children = <DecompositionPart>[];
        for (final child in childrenRaw) {
          if (child is! Map<String, Object?>) {
            throw const ContextEventException(
              'decompositionAdded children must be objects',
            );
          }
          children.add(
            DecompositionPart(
              id: _intField(child, 'id', 'decompositionAdded child'),
              text: _stringField(child, 'text', 'decompositionAdded child'),
            ),
          );
        }
        return DecompositionAdded(
          originalId: _intField(json, 'originalId', type),
          children: children,
        );
      case 'beatForgotten':
        return BeatForgotten(id: _intField(json, 'id', type));
      case 'beatsArchived':
        return BeatsArchived(ids: _intListField(json, 'ids', type));
    }
    throw ContextEventException('unknown event type: $type');
  }

  static int _intField(
    final Map<String, Object?> json,
    final String key,
    final String type,
  ) {
    final value = json[key];
    if (value is! int) {
      throw ContextEventException('$type event needs an int "$key"');
    }
    return value;
  }

  static String _stringField(
    final Map<String, Object?> json,
    final String key,
    final String type,
  ) {
    final value = json[key];
    if (value is! String) {
      throw ContextEventException('$type event needs a string "$key"');
    }
    return value;
  }

  static List<int> _intListField(
    final Map<String, Object?> json,
    final String key,
    final String type,
  ) {
    final value = json[key];
    if (value is! List<Object?>) {
      throw ContextEventException('$type event needs an int list "$key"');
    }
    return List<int>.unmodifiable(
      value.map(
        (final item) => item is int
            ? item
            : throw ContextEventException(
                '$type event needs only ints in "$key"',
              ),
      ),
    );
  }
}

/// A raw beat joins the graph: the original, permanent record.
final class BeatAppended extends ContextEvent {
  /// Creates the event. [text] is stored verbatim.
  const BeatAppended({
    required this.id,
    required this.date,
    required this.text,
    this.threadId = 'main',
  });

  /// Monotonic beat id (must equal the state's next id).
  final int id;

  /// ISO calendar date (`yyyy-mm-dd`).
  final String date;

  /// Whole text, stored verbatim.
  final String text;

  /// Conversation thread this beat belongs to.
  final String threadId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'beatAppended',
    'id': id,
    'date': date,
    'text': text,
    'threadId': threadId,
  };
}

/// A derived summary beat joins the graph, linking its sources.
final class SummaryAdded extends ContextEvent {
  /// Creates the event. [text] is stored verbatim; [summarizes] records the
  /// typed provenance links to the summarized source beats.
  const SummaryAdded({
    required this.id,
    required this.date,
    required this.text,
    required this.summarizes,
    this.threadId = 'main',
  });

  /// Monotonic summary beat id.
  final int id;

  /// ISO calendar date (`yyyy-mm-dd`).
  final String date;

  /// Whole summary text, stored verbatim.
  final String text;

  /// Conversation thread this summary belongs to.
  final String threadId;

  /// Source beat ids covered by this summary.
  final List<int> summarizes;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'summaryAdded',
    'id': id,
    'date': date,
    'text': text,
    'threadId': threadId,
    'summarizes': summarizes,
  };
}

/// One child beat of a decomposition, created together with its siblings.
final class DecompositionPart {
  /// Creates a child record. [text] is stored verbatim.
  const DecompositionPart({required this.id, required this.text});

  /// Monotonic beat id of this child.
  final int id;

  /// Whole part text, stored verbatim.
  final String text;

  @override
  String toString() => 'DecompositionPart(#$id)';
}

/// A decomposition joins the graph and archives its original.
///
/// Children inherit date and thread from the original at fold time; the
/// original is only flipped to `archived` — it persists verbatim.
final class DecompositionAdded extends ContextEvent {
  /// Creates the event over the decomposed [originalId] and its [children].
  ///
  /// The children list is copied into an unmodifiable list.
  DecompositionAdded({
    required this.originalId,
    required final List<DecompositionPart> children,
  }) : children = List<DecompositionPart>.unmodifiable(children);

  /// Beat id of the decomposed original.
  final int originalId;

  /// Child beats, in part order.
  final List<DecompositionPart> children;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'decompositionAdded',
    'originalId': originalId,
    'children': <Object?>[
      for (final child in children)
        <String, Object?>{'id': child.id, 'text': child.text},
    ],
  };
}

/// A derived beat is forgotten. Raw beats never receive this event.
final class BeatForgotten extends ContextEvent {
  /// Creates the event for the derived beat [id].
  const BeatForgotten({required this.id});

  /// Beat id to forget.
  final int id;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'beatForgotten',
    'id': id,
  };
}

/// A view-archive: the listed beats leave the projected frame but persist
/// verbatim and stay readable. This is lifecycle selection, never
/// destruction — the task-boundary counterpart of a thread going cold.
final class BeatsArchived extends ContextEvent {
  /// Creates the event for the beat ids being archived.
  const BeatsArchived({required this.ids});

  /// Beat ids to archive out of the frame (they still exist).
  final List<int> ids;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'beatsArchived',
    'ids': ids,
  };
}
