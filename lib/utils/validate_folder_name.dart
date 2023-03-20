import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';

String? validateFolderAndDriveName(String? value, BuildContext context) {
  final nameRegex = RegExp(kFileNameRegex);
  final trimTrailingRegex = RegExp(kTrimTrailingRegex);

  if (value == null || value.isEmpty) {
    return appLocalizationsOf(context).validationRequired;
  } else if (!nameRegex.hasMatch(value) || !trimTrailingRegex.hasMatch(value)) {
    return appLocalizationsOf(context).validationInvalid;
  }

  return null;
}
