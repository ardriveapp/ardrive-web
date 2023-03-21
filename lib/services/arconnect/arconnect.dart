import 'dart:typed_data';

import 'package:ardrive/utils/html/html_util.dart';
import 'package:equatable/equatable.dart';

import 'implementations/arconnect_web.dart'
    if (dart.library.io) 'implementations/arconnect_stub.dart'
    as implementation;

class ArConnectService {
  /// Returns true is the ArConnect browser extension is installed and available
  bool isExtensionPresent() => implementation.isExtensionPresent();

  /// Connects with ArConnect. If the user is not logged into it, asks user to login and
  /// requests permissions.
  Future<void> connect() => implementation.connect();

  Future<bool> safelyGetPermissionsWhenTabFocused() async {
    late bool hasPermissions;

    // FIXME: inject this value for testing purposes
    final TabVisibilitySingleton tabVisibility = TabVisibilitySingleton();

    await tabVisibility.onTabGetsFocusedFuture(() {}).then((_) {
      print(
        '[ArConnectService::safelyGetPermissionsWhenTabFocused] '
        'checking permissions after tab focus',
      );
      return safelyCheckPermissions().then(
        (value) {
          hasPermissions = value;
          return value;
        },
      );
    });

    return hasPermissions;
  }

  Future<bool> safelyCheckPermissions({
    int maxTries = 5,
    Duration cooldownDuration = const Duration(milliseconds: 100),
    Future<bool> Function() checkPermissions = implementation.checkPermissions,
  }) async {
    bool permissionsGranted = await checkPermissions();

    if (permissionsGranted) {
      return true;
    }

    // FIXME: inject this value for testing purposes
    final TabVisibilitySingleton tabVisibility = TabVisibilitySingleton();

    int triesLeft = maxTries;
    while (triesLeft-- > 0 && tabVisibility.isTabFocused()) {
      permissionsGranted = await checkPermissions();

      if (permissionsGranted) {
        return true;
      } else {
        await Future.delayed(cooldownDuration);
      }
    }

    if (!tabVisibility.isTabFocused()) {
      throw FocusError('Tab is not focused');
    }

    return false;
  }

  /// Returns true if necessary permissions have been provided
  Future<bool> checkPermissions() => implementation.checkPermissions();

  /// Disonnects from the extensions and revokes permissions
  Future<void> disconnect() => implementation.disconnect();

  /// Posts a 'walletSwitch' message to the window.parent DOM object when a wallet
  /// switch occurs
  void listenForWalletSwitch() => implementation.listenForWalletSwitch();

  /// Returns the wallet address
  Future<String> getWalletAddress() => implementation.getWalletAddress();

  /// Returns the wallet public key
  Future<String> getPublicKey() async => await implementation.getPublicKey();

  /// Takes a message and returns the signature
  Future<Uint8List> getSignature(Uint8List message) async =>
      await implementation.getSignature(message);
}

class FocusError implements Exception, Equatable {
  final String message;

  FocusError(this.message);

  @override
  List<Object> get props => [message];

  @override
  bool? get stringify => true;

  @override
  String toString() => 'FocusError: $message';
}
