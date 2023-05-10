import 'dart:io';

import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showBiometricIsLocked({
  required BuildContext context,
  Function()? cancelAction,
}) async {
  return showBiometricExceptionDialog(
    context,
    description: appLocalizationsOf(context).biometricTemporarilyDisabled,
    actionTitle: appLocalizationsOf(context).goToDeviceSettings,
    cancelTitle: appLocalizationsOf(context).cancel,
    cancelAction: cancelAction,
  );
}

Future<void> showBiometricNotEnrolled({
  required BuildContext context,
  Function()? cancelAction,
}) async {
  return showBiometricExceptionDialog(
    context,
    description: appLocalizationsOf(context).biometricsDisabledOnYourDevice,
    actionTitle: appLocalizationsOf(context).goToDeviceSettings,
    action: () {
      openSettingsToEnableBiometrics();
    },
    cancelTitle: appLocalizationsOf(context).cancel,
    cancelAction: cancelAction,
  );
}

Future<void> showBiometricNotAvailable({
  required BuildContext context,
  Function()? cancelAction,
}) async {
  return showBiometricExceptionDialog(
    context,
    description: appLocalizationsOf(context).deviceNotSupportBiometrics,
    cancelTitle: appLocalizationsOf(context).ok,
    cancelAction: cancelAction,
  );
}

Future<void> showBiometricPermanentlyLockedOut({
  required BuildContext context,
  Function()? cancelAction,
}) async {
  return showBiometricExceptionDialog(
    context,
    description: appLocalizationsOf(context).biometricsPermanentlyLockedOut,
    actionTitle: appLocalizationsOf(context).ok,
    action: () {
      final biometricsAuth = context.read<BiometricAuthentication>();

      /// let the user use password/pin
      biometricsAuth.authenticate(
          biometricOnly: false, localizedReason: 'TODO');
    },
    cancelTitle: appLocalizationsOf(context).cancel,
    cancelAction: cancelAction,
  );
}

Future<void> showBiometricPasscodeNotSet({
  required BuildContext context,
  Function()? cancelAction,
}) async {
  late String description;

  if (Platform.isAndroid) {
    description = appLocalizationsOf(context).biometricsPasscodeNotSetAndroid;
  } else if (Platform.isIOS) {
    description = appLocalizationsOf(context).biometricsPasscodeNotSetIOS;
  } else {
    return;
  }

  return showBiometricExceptionDialog(
    context,
    description: description,
    action: Platform.isAndroid
        ? () {
            openSettingsToEnableBiometrics();
          }
        : null,
    cancelAction: () {
      cancelAction?.call();
    },
    actionTitle: Platform.isAndroid
        ? appLocalizationsOf(context).goToDeviceSettings
        : null,
    cancelTitle: appLocalizationsOf(context).cancel,
  );
}

Future<void> showBiometricExceptionDialog(
  BuildContext context, {
  required String description,
  String? actionTitle,
  required String cancelTitle,
  void Function()? action,
  void Function()? cancelAction,
}) async {
  return showAnimatedDialog(
    context,
    content: ArDriveStandardModal(
      title: appLocalizationsOf(context).enableBiometricLogin,
      description: description,
      actions: [
        ModalAction(
          action: () {
            Navigator.pop(context);

            cancelAction?.call();
          },
          title: cancelTitle,
        ),
        if (action != null && actionTitle != null)
          ModalAction(action: action, title: actionTitle),
      ],
    ),
  );
}

Future<void> showBiometricExceptionDialogForException(
  BuildContext context,
  BiometricException exception,
  Function()? cancelAction,
) async {
  if (exception is BiometricNotAvailableException) {
    showBiometricNotAvailable(
      context: context,
      cancelAction: () {
        cancelAction?.call();
      },
    );
  } else if (exception is BiometricLockedException) {
    showBiometricIsLocked(
      context: context,
      cancelAction: () {
        cancelAction?.call();
      },
    );
  } else if (exception is BiometricNotEnrolledException) {
    showBiometricNotEnrolled(
      context: context,
      cancelAction: () {
        cancelAction?.call();
      },
    );
  } else if (exception is BiometricPasscodeNotSetException) {
    showBiometricPasscodeNotSet(
      context: context,
      cancelAction: () {
        cancelAction?.call();
      },
    );
  } else if (exception is BiometriPermanentlyLockedOutException) {
    showBiometricPermanentlyLockedOut(
        context: context,
        cancelAction: () {
          cancelAction?.call();
        });
  }
}
