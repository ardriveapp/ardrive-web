import 'package:reactive_forms/reactive_forms.dart';

const kValidationMessages = {
  ValidationMessage.required: 'This field is required.',
  ValidationMessage.pattern: 'This field is invalid.',
  AppValidationMessage.passwordIncorrect: 'This password is incorrect.',
  AppValidationMessage.driveNotFound: 'The specified drive could not be found.',
  AppValidationMessage.nameAlreadyPresent:
      'A folder/file with this name is already present here.',
};

class AppValidationMessage {
  static const String passwordIncorrect = 'password-incorrect';
  static const String driveNotFound = 'drive-not-found';
  static const String nameAlreadyPresent = 'name-already-present';
}
