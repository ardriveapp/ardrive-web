import 'package:app_settings/app_settings.dart';
import 'package:ardrive/components/app_dialog.dart';
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
              // TODO(@thiagocarvalhodev): Localize
              Text(appLocalizationsOf(context).enableBiometricsOnSettings),
              const SizedBox(
                height: 24,
              ),
              ElevatedButton(
                onPressed: () {
                  AppSettings.openAppSettings();
                },
                // TODO(@thiagocarvalhodev): Localize
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
