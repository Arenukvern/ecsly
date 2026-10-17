import 'package:flutter/widgets.dart';

/// One widget subtree per Flutter view; keyed addresses retain surviving state.
class MultiViewHost extends StatefulWidget {
  const MultiViewHost({super.key, required this.viewBuilder});
  final WidgetBuilder viewBuilder;
  @override
  State<MultiViewHost> createState() => _MultiViewHostState();
}

class _MultiViewHostState extends State<MultiViewHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ViewCollection(
    views: [
      for (final view in WidgetsBinding.instance.platformDispatcher.views)
        View(
          key: ValueKey(view.viewId),
          view: view,
          child: Builder(builder: widget.viewBuilder),
        ),
    ],
  );
}
