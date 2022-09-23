import 'package:ardrive/components/app_dialog.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';

showBiometricPermissionDialog(
  BuildContext context, {
  void Function()? cancelAction,
}) {
  showDialog(
      context: context,
      builder: (context) {
        return AppDialog(
          title: appLocalizationsOf(context).enableBiometricLogin,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(appLocalizationsOf(context).enableBiometricsOnSettings),
              const SizedBox(
                height: 24,
              ),
              ElevatedButton(
                onPressed: () {
                  openSettingsToEnableBiometrics();
                },
                child: Text(appLocalizationsOf(context).goToDeviceSettings),
              ),
              TextButton(
                onPressed: () {
                  cancelAction?.call();

                  Navigator.pop(context);
                },
                child: Text(appLocalizationsOf(context).cancel),
              )
            ],
          ),
        );
      });
}
