import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/widgets.dart';
import 'package:reactive_forms/reactive_forms.dart';

Map<String, String> kValidationMessages(BuildContext context) {
  return {
    ValidationMessage.required: appLocalizationsOf(context).validationRequired,
    ValidationMessage.pattern: appLocalizationsOf(context).validationInvalid,
    AppValidationMessage.passwordIncorrect:
        appLocalizationsOf(context).validationPasswordIncorrect,
    AppValidationMessage.driveAttachDriveNotFound:
        appLocalizationsOf(context).validationAttachDriveCouldNotBeFound,
    AppValidationMessage.driveAttachInvalidDriveKey:
        appLocalizationsOf(context).validationInvalidKey,
    AppValidationMessage.driveAttachUserLoggedOut:
        appLocalizationsOf(context).validationAttachUserLoggedOut,
    AppValidationMessage.fsEntryNameAlreadyPresent:
        appLocalizationsOf(context).validationEntityNameAlreadyPresent,
    AppValidationMessage.driveNameAlreadyPresent:
        appLocalizationsOf(context).validationDriveNameAlreadyPresent,
    AppValidationMessage.fsEntryNameUnchanged:
        appLocalizationsOf(context).validationNameUnchanged,
  };
}

class AppValidationMessage {
  static const String passwordIncorrect = 'password-incorrect';
  static const String driveAttachDriveNotFound = 'drive-not-found';
  static const String driveAttachUserLoggedOut = 'drive-attach-user-logged-out';
  static const String driveAttachInvalidDriveKey =
      'drive-attach-invalid-drive-key';
  static const String fsEntryNameAlreadyPresent = 'name-already-present';
  static const String fsEntryNameUnchanged = 'name-unchanged';
  static const String driveNameAlreadyPresent = 'drive-name-already-present';
}
