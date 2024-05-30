import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:flutter/material.dart';

/// A wrapper widget that tracks a page view event when the widget is built.
///
/// This widget should be used to wrap the root widget of a page to track a page view event.
class PlausiblePageViewWrapper extends StatefulWidget {
  const PlausiblePageViewWrapper({
    super.key,
    required this.pageView,
    required this.child,
    this.props,
  });

  final PlausiblePageView pageView;
  final Widget child;
  final Map<String, dynamic>? props;

  @override
  State<PlausiblePageViewWrapper> createState() =>
      _PlausiblePageViewWrapperState();
}

class _PlausiblePageViewWrapperState extends State<PlausiblePageViewWrapper> {
  @override
  void initState() {
    PlausibleEventTracker.trackPageview(
        page: widget.pageView, props: widget.props);

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
