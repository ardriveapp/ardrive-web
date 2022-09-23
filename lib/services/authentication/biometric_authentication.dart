import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthentication {
  BiometricAuthentication(
    this._auth,
    this._secureStore,
  );

  final LocalAuthentication _auth;
  final SecureKeyValueStore _secureStore;

  Future<bool> checkDeviceSupport() async {
    final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;

    final bool canAuthenticate =
        canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

    return canAuthenticate;
  }

  Future<bool> isEnabled() async {
    final localStore = await LocalKeyValueStore.getInstance();
    final isEnabled = localStore.getBool('biometricEnabled');

    return isEnabled ?? false;
  }

  Future<bool> isActive() async {
    final hasPassword = await _secureStore.getString('password');

    return hasPassword != null;
  }

  Future<bool> authenticate() async {
    try {
      final canAuthenticate = await checkDeviceSupport();

      if (!canAuthenticate) {
        throw BiometricUnsupportedException();
      }

      final authenticated = await _auth.authenticate(
          // TODO(@thiagocarvalhodev): Validate message and localize
          localizedReason: 'Please authenticate to log in',
          options: const AuthenticationOptions(biometricOnly: true));

      return authenticated;
    } on PlatformException catch (e) {
      if (e.code == 'NotAvailable') {
        throw BiometricPermissionException();
      }

      throw BiometricUnknownException();
    }
  }
}

/// Open the Platform specific settings where biometrics option can be enabled
Future<void> openSettingsToEnableBiometrics() async {
  if (Platform.isAndroid) {
    await AppSettings.openDeviceSettings();
    return;
  }
  await AppSettings.openAppSettings();
  return;
}

class BiometricPermissionException implements Exception {}

class BiometricUnknownException implements Exception {}

class BiometricUnsupportedException implements Exception {}
