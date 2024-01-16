import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../../misc/resources.dart';

class LoginCard extends StatelessWidget {
  const LoginCard({required this.content, this.showLattice = false});

  final Widget content;
  final bool showLattice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      double horizontalPadding = 72;

      final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

      final deviceType = getDeviceType(MediaQuery.of(context).size);

      switch (deviceType) {
        case DeviceScreenType.desktop:
          if (constraints.maxWidth >= 512) {
            horizontalPadding = 72;
          } else {
            horizontalPadding = constraints.maxWidth * 0.15 >= 72
                ? 72
                : constraints.maxWidth * 0.15;
          }
          break;
        case DeviceScreenType.tablet:
          horizontalPadding = 32;
          break;
        case DeviceScreenType.mobile:
          horizontalPadding = 16;
          break;
        default:
          horizontalPadding = 72;
      }

      return ArDriveCard(
          backgroundColor:
              ArDriveTheme.of(context).themeData.colors.themeBgSurface,
          borderRadius: 24,
          boxShadow: BoxShadowCard.shadow80,
          contentPadding: EdgeInsets.zero,
          content: Stack(
            children: [
              if (showLattice)
                Positioned(
                  bottom: 30,
                  right: 0,
                  child: SvgPicture.asset(
                    isDarkMode
                        ? Resources.images.login.lattice
                        : Resources.images.login.latticeLight,
                    // fit: BoxFit.fitHeight,
                  ),
                ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  _topPadding(context),
                  horizontalPadding,
                  _bottomPadding(context),
                ),
                child: content,
              )
            ],
          )
          // content,
          );
    });
  }

  double _topPadding(BuildContext context) {
    if (MediaQuery.of(context).size.height * 0.05 > 53) {
      return 53;
    } else {
      return MediaQuery.of(context).size.height * 0.05;
    }
  }

  double _bottomPadding(BuildContext context) {
    if (MediaQuery.of(context).size.height * 0.05 > 43) {
      return 43;
    } else {
      return MediaQuery.of(context).size.height * 0.05;
    }
  }
}
