import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

// TODO(@thiagocarvalhodev): should we keep this?
abstract class AuthenticationService {
  Future<bool> authenticate();
}

class BiometricAuthentication implements AuthenticationService {
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

  @override
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

class BiometricPermissionException implements Exception {}

class BiometricUnknownException implements Exception {}

class BiometricUnsupportedException implements Exception {}
