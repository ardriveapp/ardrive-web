import 'package:ardrive/components/plus_button.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';

/// A page letting the user know that they have no personal or attached drives
/// with a call to action for them to add new ones.
class NoDrivesPage extends StatelessWidget {
  final String version;

  const NoDrivesPage({
    Key? key,
    required this.version,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => ScreenTypeLayout(
        desktop: Center(
          child: Text(
            appLocalizationsOf(context).noDrives,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headline6,
          ),
        ),
        mobile: Stack(
          children: [
            Center(
              child: Text(
                appLocalizationsOf(context).noDrives,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headline6,
              ),
            ),
            PlusButton(
              version: version,
            ),
          ],
        ),
      );
}
