import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:reactive_forms/reactive_forms.dart';

Map<String, String> kValidationMessages(AppLocalizations localizations) {
  return {
    ValidationMessage.required: localizations.validationRequired,
    ValidationMessage.pattern: localizations.validationInvalid,
    AppValidationMessage.passwordIncorrect:
        localizations.validationPasswordIncorrect,
    AppValidationMessage.driveAttachDriveNotFound:
        localizations.validationAttachDriveCouldNotBeFound,
    AppValidationMessage.driveAttachInvalidDriveKey:
        localizations.validationInvalidKey,
    AppValidationMessage.driveAttachUserLoggedOut:
        localizations.validationAttachUserLoggedOut,
    AppValidationMessage.fsEntryNameAlreadyPresent:
        localizations.validationEntityNameAlreadyPresent,
    AppValidationMessage.driveNameAlreadyPresent:
        localizations.validationDriveNameAlreadyPresent,
    AppValidationMessage.fsEntryNameUnchanged:
        localizations.validationNameUnchanged,
    AppValidationMessage.sharedFileIncorrectFileKey:
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
