import 'package:flutter/material.dart';

/// Reusable Flutter shell with no ECS domain, renderer or checkpoint dependency.
class VisualizationFrame extends StatelessWidget {
  const VisualizationFrame({
    required this.child,
    this.maxWidth = 1120,
    this.padding = 20,
    super.key,
  });
  final Widget child;
  final double maxWidth, padding;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: EdgeInsets.all(padding), child: child),
          ),
        ),
      ),
    ),
  );
}

/// Linked visuals stay simultaneous; narrow viewports stack rather than shrink.
class AdaptiveVisualPair extends StatelessWidget {
  const AdaptiveVisualPair({
    required this.first,
    required this.second,
    this.breakpoint = 800,
    this.spacing = 16,
    super.key,
  });
  final Widget first, second;
  final double breakpoint, spacing;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < breakpoint
        ? Column(
            children: [
              first,
              SizedBox(height: spacing),
              second,
            ],
          )
        : Row(
            children: [
              Expanded(child: first),
              SizedBox(width: spacing),
              Expanded(child: second),
            ],
          ),
  );
}
