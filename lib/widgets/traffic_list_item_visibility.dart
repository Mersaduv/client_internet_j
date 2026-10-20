import 'package:flutter/widgets.dart';

/// Kept around the connected-list row. Traffic is one print for every
/// connected device, so this wrapper does not measure rows while scrolling.
class TrafficListItemVisibility extends StatelessWidget {
  const TrafficListItemVisibility({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Kept around the connected list. Scrolling does not reschedule traffic polls.
class TrafficListScrollScope extends StatelessWidget {
  const TrafficListScrollScope({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => _keep(controller, child);

  static Widget _keep(ScrollController controller, Widget child) => child;
}
