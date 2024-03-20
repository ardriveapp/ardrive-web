import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../misc/resources.dart';

class LoginCard extends StatelessWidget {
  const LoginCard({super.key, required this.content, this.showLattice = false});

  final Widget content;
  final bool showLattice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

      return Stack(
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
          content
        ],
      );
      // content,
    });
  }
}
