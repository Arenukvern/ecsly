import 'dart:convert';

import 'package:ecsly_flutter/ecsly_flutter.dart';

/// Versioned recipe data, independent of a Flutter widget or renderer instance.
/// This first schema deliberately supports the three installed recipes.
class VisualizationDocument {
  VisualizationDocument({
    required this.id,
    required this.revision,
    required this.title,
    required this.description,
    required this.accent,
    required List<String> graphLabels,
    required List<List<double>> graphPositions,
  }) : graphLabels = List.unmodifiable(graphLabels),
       graphPositions = List.unmodifiable(
         graphPositions.map(List<double>.unmodifiable),
       );
  final String id, title, description;
  final int revision, accent;
  final List<String> graphLabels;
  final List<List<double>> graphPositions;

  factory VisualizationDocument.fromJson(Map<String, dynamic> json) {
    const keys = {
      'schema',
      'id',
      'revision',
      'title',
      'description',
      'accent',
      'nodes',
    };
    if (json.keys.any((k) => !keys.contains(k)) || json['schema'] != 1) {
      throw const FormatException('Unsupported document schema or fields');
    }
    String text(String key, int limit) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty || value.length > limit) {
        throw FormatException('Invalid $key');
      }
      return value;
    }

    final id = text('id', 80);
    final revision = json['revision'];
    if (revision is! int || revision < 1) {
      throw const FormatException('Invalid revision');
    }
    final accent = json['accent'];
    if (accent is! int || accent < 0xFF000000 || accent > 0xFFFFFFFF) {
      throw const FormatException('Accent must be opaque ARGB');
    }
    final nodes = json['nodes'];
    if (nodes is! List || nodes.length != 6) {
      throw const FormatException('Dependency recipe requires six nodes');
    }
    final labels = <String>[], positions = <List<double>>[];
    for (final node in nodes) {
      if (node is! Map ||
          node.keys.any((k) => k != 'label' && k != 'position')) {
        throw const FormatException('Invalid node');
      }
      final label = node['label'], position = node['position'];
      if (label is! String ||
          label.isEmpty ||
          label.length > 24 ||
          position is! List ||
          position.length != 3) {
        throw const FormatException('Invalid node label or position');
      }
      if (labels.contains(label)) {
        throw const FormatException('Duplicate node label');
      }
      final xyz = <double>[];
      for (final n in position) {
        if (n is! num || !n.isFinite || n.abs() > 4) {
          throw const FormatException('Node coordinate outside scene bounds');
        }
        xyz.add(n.toDouble());
      }
      labels.add(label);
      positions.add(xyz);
    }
    return VisualizationDocument(
      id: id,
      revision: revision,
      title: text('title', 100),
      description: text('description', 240),
      accent: accent,
      graphLabels: labels,
      graphPositions: positions,
    );
  }

  Map<String, Object?> toJson() => {
    'schema': 1,
    'id': id,
    'revision': revision,
    'title': title,
    'description': description,
    'accent': accent,
    'nodes': [
      for (var i = 0; i < graphLabels.length; i++)
        {'label': graphLabels[i], 'position': graphPositions[i]},
    ],
  };
  String encode() => jsonEncode(toJson());
}

final defaultDocument = VisualizationDocument(
  id: 'ecsly.lab',
  revision: 1,
  title: 'Ecsly visualization lab',
  description:
      'Follow a dependency, freeze a signal, connect a point to its evidence.',
  accent: 0xFFDA603D,
  graphLabels: const [
    'Source',
    'Parse',
    'Layout',
    'Scene',
    'Labels',
    'Preview',
  ],
  graphPositions: const [
    [-3, 0, 0],
    [-1.5, 0, 0],
    [0, 0.8, 0],
    [1.5, 0.8, 0],
    [1.5, -0.8, 0],
    [3, 0, 0],
  ],
);

class DocumentResource extends Resource {
  DocumentResource(this.value);
  VisualizationDocument value;
}
