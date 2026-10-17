import 'package:flutter/widgets.dart';

/// Runs one startup read per mounted host, before constructing its world.
/// Metric changes rebuild the widget without repeating storage operations.
class CheckpointBootstrap extends StatefulWidget {
  const CheckpointBootstrap({
    super.key,
    required this.read,
    required this.builder,
  });
  final Future<String?> Function() read;
  final Widget Function(BuildContext context, String? saved) builder;

  @override
  State<CheckpointBootstrap> createState() => _CheckpointBootstrapState();
}

class _CheckpointBootstrapState extends State<CheckpointBootstrap> {
  late final Future<String?> loaded = Future.sync(widget.read);

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: loaded,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Text('Loading preview checkpoint…')),
        );
      }
      if (snapshot.hasError) {
        return const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Text('Preview checkpoint could not be loaded')),
        );
      }
      return widget.builder(context, snapshot.data);
    },
  );
}
