import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// A page letting the user know that they have no personal or attached drives
/// with a call to action for them to add new ones.
class NoDrivesPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          AppLocalizations.of(context)!.noDrives,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headline6,
        ),
      );
}
