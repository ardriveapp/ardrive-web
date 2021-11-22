import 'package:reactive_forms/reactive_forms.dart';

const kValidationMessages = {
  ValidationMessage.required: 'This field is required.',
  ValidationMessage.pattern: 'This field is invalid.',
  AppValidationMessage.passwordIncorrect: 'This password is incorrect.',
  AppValidationMessage.driveNotFound: 'The specified drive could not be found.',
  AppValidationMessage.fsEntryNameAlreadyPresent:
      'A folder/file with this name is already present here.',
  AppValidationMessage.driveNameAlreadyPresent:
      'A drive with this name is already present.',
  AppValidationMessage.fsEntryNameUnchanged:
      'This name is identical to the current name.',
};

class AppValidationMessage {
  static const String passwordIncorrect = 'password-incorrect';
  static const String driveNotFound = 'drive-not-found';
  static const String fsEntryNameAlreadyPresent = 'name-already-present';
  static const String fsEntryNameUnchanged = 'name-unchanged';
  static const String driveNameAlreadyPresent = 'drive-name-already-present';
}
