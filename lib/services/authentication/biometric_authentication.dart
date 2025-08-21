import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as error_codes;
import 'package:local_auth/local_auth.dart';

class BiometricAuthentication {
  BiometricAuthentication(
    this._auth,
    this._secureStore,
  );

  final LocalAuthentication _auth;
  final SecureKeyValueStore _secureStore;

  final StreamController<bool> _enabledStream =
      StreamController<bool>.broadcast();

  Stream<bool> get enabledStream => _enabledStream.stream;

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

  Future<void> disable() async {
    final localStore = await LocalKeyValueStore.getInstance();
    localStore.putBool('biometricEnabled', false);
    _enabledStream.sink.add(false);
  }

  Future<void> enable() async {
    final localStore = await LocalKeyValueStore.getInstance();
    localStore.putBool('biometricEnabled', true);
    _enabledStream.sink.add(true);
  }

  Future<bool> isActive() async {
    final hasPassword = await _secureStore.getString('password');

    return hasPassword != null;
  }

  bool _authenticated = false;
  DateTime _lastAuthenticatedTime = DateTime.now();

  Future<bool> authenticate({
    bool biometricOnly = true,
    required String localizedReason,
    bool useCached = false, // Add a new flag for using cached authentication
  }) async {
    if (useCached &&
        _authenticated &&
        _lastAuthenticatedTime
            .isAfter(DateTime.now().subtract(const Duration(seconds: 5)))) {
      // Return the cached authentication state if it was authenticated less than 5 seconds ago
      return _authenticated;
    }

    try {
      final canAuthenticate = await checkDeviceSupport();

      if (!canAuthenticate) {
        throw BiometricUnknownException();
      }

      final authenticated = await _auth.authenticate(
        localizedReason: localizedReason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          useErrorDialogs: false,
        ),
      );

      _authenticated = authenticated;
      _lastAuthenticatedTime = DateTime.now();

      return authenticated;
    } on PlatformException catch (e) {
      logger.e('Error authenticating', e);
      disable();

      switch (e.code) {
        case error_codes.notAvailable:

          /// If there is available biometrics and yet received a `NotAvailable`,
          /// it failed to authenticate. It can happen when user use the wrong fingerprint or faceid
          /// for many times. Yet the error code is not precisely,
          /// this is how it is handled in iOS 16 iPhone 11.
          final enrolled = await _auth.getAvailableBiometrics();

          /// Have enrolled biometrics but yet failed, so it is locked.
          if (enrolled.isNotEmpty) {
            throw BiometricLockedException();
          }

          final deviceSupports = await _auth.isDeviceSupported();

          /// The device supports but biometrics are not enrolled
          if (deviceSupports) {
            throw BiometricNotEnrolledException();
          }

          /// This was achieved by testing on a real device.
          if (await _auth.canCheckBiometrics) {
            throw BiometricPasscodeNotSetException();
          }

          /// If there is not any biometrics available, show the correct modal
          throw BiometricNotAvailableException();
        case error_codes.lockedOut:
          throw BiometricLockedException();
        case error_codes.passcodeNotSet:
          throw BiometricPasscodeNotSetException();
        case error_codes.notEnrolled:
          throw BiometricNotEnrolledException();
        case error_codes.permanentlyLockedOut:
          throw BiometriPermanentlyLockedOutException();
        default:
          throw BiometricUnknownException();
      }
    } on BiometricException {
      rethrow;
    }
  }
}

/// Open the Platform specific settings where biometrics option can be enabled
Future<void> openSettingsToEnableBiometrics() async {
  if (Platform.isAndroid) {
    await AppSettings.openAppSettings(type: AppSettingsType.device);
    return;
  }
  await AppSettings.openAppSettings();
  return;
}

class BiometricException implements Exception {}

class BiometricUnknownException implements BiometricException {}

class BiometricNotAvailableException implements BiometricException {}

class BiometricLockedException implements BiometricException {}

class BiometricPasscodeNotSetException implements BiometricException {}

class BiometricNotEnrolledException implements BiometricException {}

class BiometriPermanentlyLockedOutException implements BiometricException {}
