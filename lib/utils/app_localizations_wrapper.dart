import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

AppLocalizations appLocalizationsOf(BuildContext context) {
  final localizations = AppLocalizations.of(context);
  if (localizations == null) {
    throw Exception('Could not load localizations for this context!');
  }
  return localizations;
}
