import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/utils/html/html_util.dart';
import 'package:equatable/equatable.dart';

import 'implementations/arconnect_web.dart'
    if (dart.library.io) 'implementations/arconnect_stub.dart'
    as implementation;

const permissionsRetryDelayInMs = 100;
const permissionsRetryAttempts = 5;

class ArConnectService {
  final TabVisibilitySingleton tabVisibility;

  const ArConnectService({
    required this.tabVisibility,
  });

  /// Returns true is the ArConnect browser extension is installed and available
  bool isExtensionPresent() => implementation.isExtensionPresent();

  /// Connects with ArConnect. If the user is not logged into it, asks user to login and
  /// requests permissions.
  Future<void> connect() => implementation.connect();

  Future<bool> safelyGetPermissionsWhenTabFocused() async {
    late bool hasPermissions;

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
    int maxTries = 10,
    Duration cooldownDuration = const Duration(milliseconds: 10),
    Future<bool> Function() checkPermissions = implementation.checkPermissions,
  }) async {
    bool permissionsGranted = await checkPermissions();

    if (permissionsGranted) {
      print(
        '[ArConnectService::safelyCheckPermissions] Permissions granted on first try',
      );
      return true;
    }

    int triesLeft = maxTries;
    while (triesLeft-- > 0 && tabVisibility.isTabFocused()) {
      permissionsGranted = await checkPermissions();

      if (permissionsGranted) {
        print(
          '[ArConnectService::safelyCheckPermissions] It took ${maxTries - triesLeft} retries to get permissions - SUCCESS',
        );
        return true;
      } else {
        print(
          '[ArConnectService::safelyCheckPermissions] Retrying in ${cooldownDuration.inMilliseconds} ms ... ($triesLeft tries left)',
        );
        await Future.delayed(cooldownDuration);
      }
    }

    if (!tabVisibility.isTabFocused()) {
      print(
        '[ArConnectService::safelyCheckPermissions] Tab is not focused, throwing...',
      );
      throw FocusError('Tab is not focused');
    }

    print(
      '[ArConnectService::safelyCheckPermissions] Failed $maxTries times to get permissions while tab is focused',
    );
    return false;
  }

  // /// Returns true if necessary permissions have been provided
  Future<bool> checkPermissions() => implementation.checkPermissions();

  // Future<bool> checkPermissions({int attemptNumber = 1}) async {
  //   final hasPermissions = await implementation.checkPermissions();

  //   if (!hasPermissions && attemptNumber <= permissionsRetryAttempts) {
  //     print(
  //       '[ArConnectService::checkPermissions] '
  //       'Permissions yet not granted. Retrying in $permissionsRetryDelayInMs ms.',
  //     );

  //     return await Future.delayed(
  //       const Duration(milliseconds: permissionsRetryDelayInMs),
  //       () async {
  //         return await checkPermissions(attemptNumber: attemptNumber + 1);
  //       },
  //     );
  //   } else if (!hasPermissions && attemptNumber > permissionsRetryAttempts) {
  //     print(
  //       '[ArConnectService::checkPermissions] '
  //       'Permissions yet not granted after $permissionsRetryAttempts attempts. '
  //       'Total waiting time: ${permissionsRetryDelayInMs * permissionsRetryAttempts} ms.',
  //     );
  //     return false;
  //   }

  //   print(
  //     '[ArConnectService::checkPermissions] Permissions granted at attempt $attemptNumber: $hasPermissions.',
  //   );

  //   return hasPermissions;
  // }

  /// Disonnects from the extensions and revokes permissions
  Future<void> disconnect() => implementation.disconnect();

  /// Posts a 'walletSwitch' message to the window.parent DOM object when a wallet
  /// switch occurs
  void listenForWalletSwitch() => implementation.listenForWalletSwitch();

  /// Returns the wallet address
  Future<String> getWalletAddress() async {
    final hasPermissions = await safelyCheckPermissions();
    if (!hasPermissions) {
      throw Exception('Permissions not granted for getWalletAddress');
    }
    return implementation.getWalletAddress();
  }

  /// Returns the wallet public key
  Future<String> getPublicKey() async {
    final hasPermissions = await safelyCheckPermissions();
    if (!hasPermissions) {
      throw Exception('Permissions not granted for getPublicKey');
    }
    return implementation.getPublicKey();
  }

  /// Takes a message and returns the signature
  Future<Uint8List> getSignature(Uint8List message) async {
    final hasPermissions = await safelyCheckPermissions();
    if (!hasPermissions) {
      throw Exception('Permissions not granted for getSignature');
    }
    return implementation.getSignature(message);
  }
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
