/// Renderer-independent art direction values. Hosts choose their widget adapter.
class VisualizationTokens {
  const VisualizationTokens({required this.dark});
  final bool dark;
  int get ink => dark ? 0xFFE8EAE8 : 0xFF252B2C;
  int get paper => dark ? 0xFF131B1D : 0xFFF4F2ED;
  int get panel => dark ? 0xFF1D282B : 0xFFFCFBF7;
  int get outline => dark ? 0xFF3A494C : 0xFFD5D9D2;
}

/// Live-session probe; a method body so reload can change existing instances.
String visualizationCodeRevision() => 'design-1';
