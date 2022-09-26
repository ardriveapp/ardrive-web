import 'dart:io';

import 'package:ardrive/components/app_dialog.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';

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
    action: () {
      openSettingsToEnableBiometrics();
    },
    cancelAction: () {
      cancelAction?.call();
    },
    actionTitle: appLocalizationsOf(context).goToDeviceSettings,
    cancelTitle: appLocalizationsOf(context).ok,
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
  return showDialog(
      context: context,
      builder: (context) {
        return AppDialog(
          title: appLocalizationsOf(context).enableBiometricLogin,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(description),
              const SizedBox(
                height: 24,
              ),
              if (action != null && actionTitle != null)
                ElevatedButton(
                  onPressed: () {
                    action.call();
                  },
                  child: Text(actionTitle),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);

                  cancelAction?.call();
                },
                child: Text(cancelTitle),
              )
            ],
          ),
        );
      });
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
  }
}
