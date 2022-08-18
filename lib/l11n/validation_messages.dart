import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

Map<String, String Function(Object o)> kValidationMessages(
    AppLocalizations localizations) {
  return {
    ValidationMessage.required: (_) => localizations.validationRequired,
    ValidationMessage.pattern: (_) => localizations.validationInvalid,
    AppValidationMessage.passwordIncorrect: (_) =>
        localizations.validationPasswordIncorrect,
    AppValidationMessage.driveAttachDriveNotFound: (_) =>
        localizations.validationAttachDriveCouldNotBeFound,
    AppValidationMessage.driveAttachInvalidDriveKey: (_) =>
        localizations.validationInvalidKey,
    AppValidationMessage.driveAttachUserLoggedOut: (_) =>
        localizations.validationAttachUserLoggedOut,
    AppValidationMessage.fsEntryNameAlreadyPresent: (_) =>
        localizations.validationEntityNameAlreadyPresent,
    AppValidationMessage.driveNameAlreadyPresent: (_) =>
        localizations.validationDriveNameAlreadyPresent,
    AppValidationMessage.fsEntryNameUnchanged: (_) =>
        localizations.validationNameUnchanged,
    AppValidationMessage.sharedFileIncorrectFileKey: (_) =>
        localizations.validationSharedFileIncorrectFileKey,
  };
}

class AppValidationMessage {
  static const String passwordIncorrect = 'password-incorrect';
  static const String driveAttachDriveNotFound = 'drive-not-found';
  static const String driveAttachUserLoggedOut = 'drive-attach-user-logged-out';
  static const String driveAttachInvalidDriveKey =
      'drive-attach-invalid-drive-key';
  static const String sharedFileIncorrectFileKey =
      'shared-file-incorrect-file-key';
  static const String fsEntryNameAlreadyPresent = 'name-already-present';
  static const String fsEntryNameUnchanged = 'name-unchanged';
  static const String driveNameAlreadyPresent = 'drive-name-already-present';
}
