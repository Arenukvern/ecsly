import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ecsly_visualization_tokens/ecsly_visualization_tokens.dart';

/// Consumer-owned visual vocabulary. Material remains an optional widget adapter,
/// not the art direction or state owner.
ThemeData visualizationTheme(bool dark, Color accent) {
  final tokens = VisualizationTokens(dark: dark);
  final ink = Color(tokens.ink);
  final paper = Color(tokens.paper);
  final panel = Color(tokens.panel);
  final outline = Color(tokens.outline);
  final colors =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: accent,
        onPrimary: Colors.white,
        surface: panel,
        onSurface: ink,
        outline: outline,
        outlineVariant: outline,
        onSurfaceVariant: dark
            ? const Color(0xFFA4B2B3)
            : const Color(0xFF637172),
      );
  return ThemeData(
    fontFamily: 'PreviewRoboto',
    colorScheme: colors,
    scaffoldBackgroundColor: paper,
    useMaterial3: false,
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
      labelMedium: TextStyle(fontSize: 12, height: 1.4, color: ink),
    ),
    sliderTheme: SliderThemeData(
      showValueIndicator: ShowValueIndicator.never,
      activeTrackColor: accent,
      inactiveTrackColor: outline,
      thumbColor: accent,
      overlayColor: accent.withValues(alpha: .12),
      trackHeight: 2,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
  );
}

class ViewerButton extends StatefulWidget {
  const ViewerButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.primary = false,
    super.key,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool selected, primary;
  @override
  State<ViewerButton> createState() => _ViewerButtonState();
}

class _ViewerButtonState extends State<ViewerButton> {
  bool hover = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final active = widget.selected || widget.primary;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.onPressed != null,
      child: FocusableActionDetector(
        enabled: widget.onPressed != null,
        onShowFocusHighlight: (v) => setState(() => focused = v),
        onShowHoverHighlight: (v) => setState(() => hover = v),
        mouseCursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: active
                  ? c.primary
                  : (hover ? c.primary.withValues(alpha: .08) : c.surface),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: focused ? c.primary : (active ? c.primary : c.outline),
                width: focused ? 2 : 1,
              ),
            ),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.labelLarge!.copyWith(
                color: widget.onPressed == null
                    ? c.onSurfaceVariant
                    : (active ? c.onPrimary : c.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VisualPanel extends StatelessWidget {
  const VisualPanel({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: Theme.of(context).colorScheme.outline),
      borderRadius: BorderRadius.circular(8),
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
  );
}
