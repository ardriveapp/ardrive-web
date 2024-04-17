// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

const TABLET = 834;
const SMALL_DESKTOP = 1280;
const LARGE_DESKTOP = 1440;

class BreakpointLayoutBuilder extends StatelessWidget {
  final WidgetBuilder? largeDesktop;
  final WidgetBuilder? smallDesktop;
  final WidgetBuilder? tablet;
  final WidgetBuilder phone;

  const BreakpointLayoutBuilder({
    super.key,
    this.largeDesktop,
    this.smallDesktop,
    this.tablet,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < TABLET) {
        return phone(context);
      } else if (constraints.maxWidth < SMALL_DESKTOP && tablet != null) {
        return tablet!(context);
      } else if (constraints.maxWidth < LARGE_DESKTOP) {
        if (smallDesktop != null) {
          return smallDesktop!(context);
        } else if (largeDesktop != null) {
          return largeDesktop!(context);
        } else if (tablet != null) {
          return tablet!(context);
        } else {
          return phone(context);
        }
      }
      return largeDesktop != null ? largeDesktop!(context) : Container();
    });
  }
}

bool isMobile(BuildContext context) {
  return MediaQuery.of(context).size.width < TABLET;
}
