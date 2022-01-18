import 'package:flutter/material.dart';
import 'package:flutter_portal/flutter_portal.dart';
import 'package:url_launcher/url_launcher.dart';

/// A link help button which floats over the provided child widget.
class FloatingHelpButtonPortalEntry extends StatelessWidget {
  const FloatingHelpButtonPortalEntry({
    Key? key,
    required this.child,
  }) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) => PortalEntry(
        portal: Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 16),
          child: FloatingActionButton(
            tooltip: 'Help',
            onPressed: () => launch('https://ardrive.typeform.com/to/pGeAVvtg'),
            child: const Icon(Icons.help_outline),
          ),
        ),
        portalAnchor: Alignment.bottomLeft,
        childAnchor: Alignment.bottomLeft,
        child: child,
      );
}
