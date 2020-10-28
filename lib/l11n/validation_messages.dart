import 'package:reactive_forms/reactive_forms.dart';

const kValidationMessages = {
  ValidationMessage.required: 'This field is required.',
  AppValidationMessage.passwordIncorrect: 'This password is incorrect',
  AppValidationMessage.driveNotFound: 'The specified drive could not be found.',
};

class AppValidationMessage {
  static const String passwordIncorrect = 'password-incorrect';
  static const String driveNotFound = 'drive-not-found';
}
