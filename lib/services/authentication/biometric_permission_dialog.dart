import 'package:app_settings/app_settings.dart';
import 'package:ardrive/components/app_dialog.dart';
import 'package:flutter/material.dart';

showBiometricPermissionDialog(
  BuildContext context, {
  void Function()? cancelAction,
}) {
  showDialog(
      context: context,
      builder: (context) {
        return AppDialog(
          title: 'Enable Biometric Login',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TODO(@thiagocarvalhodev): Localize
              Text(
                'Biometric authentication has been disabled. Please enable it in Settings.',
              ),
              const SizedBox(
                height: 24,
              ),
              ElevatedButton(
                onPressed: () {
                  AppSettings.openAppSettings();
                },
                // TODO(@thiagocarvalhodev): Localize
                child: const Text('Go to Settings'),
              ),
              TextButton(
                onPressed: () {
                  cancelAction?.call();

                  Navigator.pop(context);
                },
                child: Text('Cancel'),
              )
            ],
          ),
        );
      });
}
