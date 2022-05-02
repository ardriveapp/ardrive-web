import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';

/// A page letting the user know that they have no personal or attached drives
/// with a call to action for them to add new ones.
class NoDrivesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          appLocalizationsOf(context).noDrives,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headline6,
        ),
      );
}
